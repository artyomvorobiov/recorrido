import Foundation

/// How the traveller is ready to move around.
enum Mobility: String, CaseIterable, Codable, Sendable {
    /// Everything on foot.
    case walking
    /// Walk, and take public transport for long hops.
    case transit
    /// Walk, and drive (or take a taxi) for long hops — handy for small towns
    /// with sights outside.
    case car

    /// The transport for a hop of the given straight-line length.
    func mode(forDistance meters: Double, pace: Pace) -> TransportMode {
        guard meters > pace.comfortableWalkMeters else { return .walk }
        switch self {
        case .walking: return .walk
        case .transit: return .transit
        case .car: return .car
        }
    }

    /// Rough travel time per stop before the exact order is known, minutes.
    var travelGuessMinutes: Double {
        switch self {
        case .walking: 15
        case .transit: 18
        case .car: 16
        }
    }

    /// How far from a day's area a place may be and still join that day, meters.
    var dayReach: Double {
        switch self {
        case .walking: 2500
        case .transit: 6000
        case .car: 25000
        }
    }
}

struct PlannerCandidate: Hashable, Sendable {
    var id: String
    var coordinate: Coordinate
    /// Higher is more worth visiting.
    var score: Double
    var visitMinutes: Int
}

struct PlannerOptions: Sendable {
    var days: Int = 1
    var minutesPerDay: Int = 420
    var pace: Pace = .normal
    var mobility: Mobility = .walking
    /// Hotel, station or the traveller's position. `nil` lets the route start
    /// at whichever stop makes the walk shortest.
    var start: Coordinate?
    var returnToStart: Bool = false
    var maxStopsPerDay: Int = 12
}

/// Picks places that fit a time budget, splits them into days and orders
/// them for the shortest path.
enum RoutePlanner {
    static func plan(_ candidates: [PlannerCandidate], options: PlannerOptions) -> [[PlannerCandidate]] {
        let pool = candidates
            .filter { $0.coordinate.isValid }
            .sorted { $0.score > $1.score }
        guard !pool.isEmpty else { return [] }
        let days = max(1, options.days)

        if days == 1 {
            let day = fillDay([], from: pool, options: options)
            return day.isEmpty ? [] : [day]
        }

        // Several days: take enough good places for all of them, split them
        // geographically so each day explores one area, then tune each day.
        let budget = Double(options.minutesPerDay)
        var selected: [PlannerCandidate] = []
        var load = 0.0
        for candidate in pool where selected.count < days * options.maxStopsPerDay {
            let cost = visitCost(candidate, options) + options.mobility.travelGuessMinutes
            if load + cost <= budget * Double(days) {
                selected.append(candidate)
                load += cost
            }
        }
        var groups = clusters(of: selected, count: min(days, selected.count), capacityMinutes: budget, options: options)
        var used = Set<String>()
        for index in groups.indices {
            groups[index] = trim(order(groups[index], options: options), options: options)
            used.formUnion(groups[index].map(\.id))
        }
        // Top up days that ended light with nearby places nobody took.
        for index in groups.indices where !groups[index].isEmpty {
            let remaining = pool.filter { !used.contains($0.id) }
            let center = Geo.centroid(of: groups[index].map(\.coordinate))
            groups[index] = fillDay(groups[index], from: remaining, options: options, near: center)
            used.formUnion(groups[index].map(\.id))
        }
        return groups
            .filter { !$0.isEmpty }
            .sorted { totalScore($0) > totalScore($1) }
    }

    /// Greedily adds the best places that still fit into one day.
    static func fillDay(
        _ initial: [PlannerCandidate],
        from pool: [PlannerCandidate],
        options: PlannerOptions,
        near center: Coordinate? = nil
    ) -> [PlannerCandidate] {
        var day = order(initial, options: options)
        let budget = Double(options.minutesPerDay)
        var taken = Set(day.map(\.id))
        for candidate in pool where day.count < options.maxStopsPerDay {
            if taken.contains(candidate.id) { continue }
            if let center, Geo.distance(center, candidate.coordinate) > options.mobility.dayReach { continue }
            let trial = order(day + [candidate], options: options)
            if cost(of: trial, options: options) <= budget {
                day = trial
                taken.insert(candidate.id)
            }
        }
        if day.isEmpty, let best = pool.first(where: { !taken.contains($0.id) }), initial.isEmpty, center == nil {
            day = [best]
        }
        return day
    }

    /// Drops the weakest places until the day fits its budget.
    static func trim(_ day: [PlannerCandidate], options: PlannerOptions) -> [PlannerCandidate] {
        var day = day
        let limit = Double(options.minutesPerDay) * 1.1
        while day.count > 1, cost(of: day, options: options) > limit {
            if let weakest = day.indices.min(by: { day[$0].score < day[$1].score }) {
                day.remove(at: weakest)
            }
            day = order(day, options: options)
        }
        return day
    }

    /// Minutes needed for the stops in the given order, including the way
    /// from the start point (and back to it when asked).
    static func cost(of day: [PlannerCandidate], options: PlannerOptions) -> Double {
        guard !day.isEmpty else { return 0 }
        var points = day.map(\.coordinate)
        if let start = options.start {
            points.insert(start, at: 0)
            if options.returnToStart { points.append(start) }
        }
        var minutes = day.reduce(0) { $0 + visitCost($1, options) }
        for (a, b) in zip(points, points.dropFirst()) {
            let mode = options.mobility.mode(forDistance: Geo.distance(a, b), pace: options.pace)
            minutes += RouteEstimator.leg(from: a, to: b, mode: mode, pace: options.pace).minutes
        }
        return minutes
    }

    static func order(_ items: [PlannerCandidate], options: PlannerOptions) -> [PlannerCandidate] {
        orderedIndices(of: items.map(\.coordinate), start: options.start, returnToStart: options.returnToStart)
            .map { items[$0] }
    }

    /// Reorders a day's stops for the shortest path. The first stop stays put
    /// when `keepFirst` — it is usually the hotel or a meeting point.
    static func optimize(_ stops: [Stop], keepFirst: Bool = true) -> [Stop] {
        guard stops.count > 2 else { return stops }
        if keepFirst {
            let rest = Array(stops.dropFirst())
            let order = orderedIndices(of: rest.map(\.coordinate), start: stops[0].coordinate, returnToStart: false)
            return [stops[0]] + order.map { rest[$0] }
        }
        return orderedIndices(of: stops.map(\.coordinate), start: nil, returnToStart: false).map { stops[$0] }
    }

    /// Visiting order with the shortest total distance found by nearest
    /// neighbour plus 2-opt. With a `start` the path begins there (and returns
    /// to it when `returnToStart`); otherwise both ends are free.
    static func orderedIndices(of points: [Coordinate], start: Coordinate?, returnToStart: Bool) -> [Int] {
        if points.count < 2 { return Array(points.indices) }
        var nodes = points
        if let start { nodes.insert(start, at: 0) }
        let count = nodes.count
        var distances = [[Double]](repeating: [Double](repeating: 0, count: count), count: count)
        for i in 0..<count {
            for j in (i + 1)..<count {
                let d = Geo.distance(nodes[i], nodes[j])
                distances[i][j] = d
                distances[j][i] = d
            }
        }
        let fixedStart = start != nil
        let closed = fixedStart && returnToStart
        var best: [Int] = []
        var bestLength = Double.infinity
        for first in (fixedStart ? [0] : Array(0..<count)) {
            var path = nearestNeighbour(from: first, distances: distances)
            improve(&path, distances: distances, fixedStart: fixedStart, closed: closed)
            let length = pathLength(path, distances: distances, closed: closed)
            if length < bestLength - 1e-9 {
                bestLength = length
                best = path
            }
        }
        return fixedStart ? best.dropFirst().map { $0 - 1 } : best
    }

    static func totalScore(_ day: [PlannerCandidate]) -> Double {
        day.reduce(0) { $0 + $1.score }
    }

    /// Splits places into `count` geographic groups with a similar workload:
    /// k-means where each group has a soft time capacity.
    static func clusters(
        of items: [PlannerCandidate],
        count: Int,
        capacityMinutes: Double,
        options: PlannerOptions
    ) -> [[PlannerCandidate]] {
        guard count > 1, items.count > count else {
            return count <= 1 ? [items] : items.map { [$0] }
        }
        let byScore = items.sorted { $0.score > $1.score }
        // Seeds: the best place, then places that are both important and far
        // from the seeds chosen so far.
        var centers = [byScore[0].coordinate]
        while centers.count < count {
            var bestSeed = byScore[0].coordinate
            var bestWeight = -1.0
            for item in byScore {
                let weight = nearestDistance(item.coordinate, to: centers) * item.score
                if weight > bestWeight {
                    bestWeight = weight
                    bestSeed = item.coordinate
                }
            }
            centers.append(bestSeed)
        }
        var groups: [[PlannerCandidate]] = []
        for _ in 0..<12 {
            groups = Array(repeating: [], count: count)
            var load = [Double](repeating: 0, count: count)
            for item in byScore {
                let cost = visitCost(item, options) + options.mobility.travelGuessMinutes
                let nearest = centers.indices.sorted {
                    Geo.distance(item.coordinate, centers[$0]) < Geo.distance(item.coordinate, centers[$1])
                }
                let target = nearest.first { load[$0] + cost <= capacityMinutes * 1.15 } ?? nearest[0]
                groups[target].append(item)
                load[target] += cost
            }
            let updated = groups.indices.map { Geo.centroid(of: groups[$0].map(\.coordinate)) ?? centers[$0] }
            if updated == centers { break }
            centers = updated
        }
        return groups
    }

    // MARK: - Helpers

    private static func visitCost(_ candidate: PlannerCandidate, _ options: PlannerOptions) -> Double {
        Double(candidate.visitMinutes) * options.pace.visitFactor
    }

    private static func nearestDistance(_ point: Coordinate, to centers: [Coordinate]) -> Double {
        centers.map { Geo.distance(point, $0) }.min() ?? 0
    }

    private static func nearestNeighbour(from first: Int, distances: [[Double]]) -> [Int] {
        let count = distances.count
        var path = [first]
        var visited = [Bool](repeating: false, count: count)
        visited[first] = true
        while path.count < count {
            let last = path[path.count - 1]
            var next = -1
            var nextDistance = Double.infinity
            for candidate in 0..<count where !visited[candidate] && distances[last][candidate] < nextDistance {
                next = candidate
                nextDistance = distances[last][candidate]
            }
            if next < 0 { break }
            visited[next] = true
            path.append(next)
        }
        return path
    }

    /// 2-opt: reverses segments while that makes the path shorter.
    private static func improve(_ path: inout [Int], distances: [[Double]], fixedStart: Bool, closed: Bool) {
        let count = path.count
        guard count >= 3 else { return }
        var improved = true
        var rounds = 0
        while improved && rounds < 50 {
            improved = false
            rounds += 1
            for i in (fixedStart ? 1 : 0)..<(count - 1) {
                for k in (i + 1)..<count {
                    let b = path[i]
                    let c = path[k]
                    var delta = 0.0
                    if i > 0 {
                        let a = path[i - 1]
                        delta += distances[a][c] - distances[a][b]
                    }
                    if k + 1 < count {
                        let d = path[k + 1]
                        delta += distances[b][d] - distances[c][d]
                    } else if closed {
                        let d = path[0]
                        delta += distances[b][d] - distances[c][d]
                    }
                    if delta < -1e-6 {
                        path[i...k].reverse()
                        improved = true
                    }
                }
            }
        }
    }

    private static func pathLength(_ path: [Int], distances: [[Double]], closed: Bool) -> Double {
        var length = zip(path, path.dropFirst()).reduce(0.0) { $0 + distances[$1.0][$1.1] }
        if closed, let first = path.first, let last = path.last {
            length += distances[last][first]
        }
        return length
    }
}
