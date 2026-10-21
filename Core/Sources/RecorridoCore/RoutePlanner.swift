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

    /// Score points a kilometre of travelling costs when comparing ways to
    /// split places into days.
    var travelPenaltyPerKm: Double {
        switch self {
        case .walking: 0.8
        case .transit: 0.35
        case .car: 0.15
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
        var groups = bestSplit(of: selected, days: min(days, selected.count), options: options)
        var used = Set(groups.flatMap { $0.map(\.id) })
        // Top up days that ended light with places nobody took, each place
        // going only to the day whose area is closest to it.
        let centers = groups.map { Geo.centroid(of: $0.map(\.coordinate)) }
        for index in groups.indices {
            guard let center = centers[index] else { continue }
            let remaining = pool.filter {
                !used.contains($0.id) && nearestDay(to: $0.coordinate, centers: centers) == index
            }
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

    /// Splits places into days. Tries several sets of seed places for the
    /// day areas and keeps the split whose days hold the most worthwhile
    /// places for the least travelling.
    static func bestSplit(of items: [PlannerCandidate], days: Int, options: PlannerOptions) -> [[PlannerCandidate]] {
        guard days > 1, items.count > days else {
            return days <= 1 ? [trim(order(items, options: options), options: options)] : items.map { [$0] }
        }
        let poolSize = max(days, days >= 4 ? 7 : days == 3 ? 8 : 10)
        let seedPool = Array(items.sorted { $0.score > $1.score }.prefix(poolSize))
        var best: [[PlannerCandidate]] = []
        var bestValue = -Double.infinity
        for seeds in combinations(seedPool.count, choose: days) {
            let groups = clusters(of: items, seeds: seeds.map { seedPool[$0].coordinate },
                                  capacityMinutes: Double(options.minutesPerDay), options: options)
                .map { trim(order($0, options: options), options: options) }
            var value = 0.0
            for day in groups {
                value += totalScore(day) - pathMeters(day, options: options) / 1000 * options.mobility.travelPenaltyPerKm
            }
            if value > bestValue + 1e-9 {
                bestValue = value
                best = groups
            }
        }
        return best
    }

    /// Groups places around the seeds: k-means where each group has a soft
    /// time capacity. Places that clearly belong to one area are placed
    /// first; the ones in between fill whatever room is left.
    static func clusters(
        of items: [PlannerCandidate],
        seeds: [Coordinate],
        capacityMinutes: Double,
        options: PlannerOptions
    ) -> [[PlannerCandidate]] {
        guard seeds.count > 1 else { return [items] }
        var centers = seeds
        var groups: [[PlannerCandidate]] = []
        for _ in 0..<12 {
            let ranked = items.map { item -> (item: PlannerCandidate, nearest: [Int], regret: Double) in
                let distances = centers.map { Geo.distance(item.coordinate, $0) }
                let nearest = distances.indices.sorted { distances[$0] < distances[$1] }
                return (item, nearest, distances[nearest[1]] - distances[nearest[0]])
            }.sorted { $0.regret != $1.regret ? $0.regret > $1.regret : $0.item.id < $1.item.id }
            groups = Array(repeating: [], count: centers.count)
            var load = [Double](repeating: 0, count: centers.count)
            for entry in ranked {
                let cost = visitCost(entry.item, options) + options.mobility.travelGuessMinutes
                let target = entry.nearest.first { load[$0] + cost <= capacityMinutes * 1.15 } ?? entry.nearest[0]
                groups[target].append(entry.item)
                load[target] += cost
            }
            let updated = groups.indices.map { Geo.centroid(of: groups[$0].map(\.coordinate)) ?? centers[$0] }
            if updated == centers { break }
            centers = updated
        }
        return groups
    }

    /// Every way to choose `size` of `count` indices, in lexicographic order.
    static func combinations(_ count: Int, choose size: Int) -> [[Int]] {
        guard size > 0, size <= count else { return [] }
        var result: [[Int]] = []
        var current: [Int] = []
        func extend(from start: Int) {
            if current.count == size {
                result.append(current)
                return
            }
            for index in start..<count where count - index >= size - current.count {
                current.append(index)
                extend(from: index + 1)
                current.removeLast()
            }
        }
        extend(from: 0)
        return result
    }

    /// Length of the day's path in the given order, meters, including the
    /// way from the start point (and back to it when asked).
    static func pathMeters(_ day: [PlannerCandidate], options: PlannerOptions) -> Double {
        var points = day.map(\.coordinate)
        if let start = options.start, !points.isEmpty {
            points.insert(start, at: 0)
            if options.returnToStart { points.append(start) }
        }
        return Geo.pathLength(points)
    }

    // MARK: - Helpers

    private static func nearestDay(to point: Coordinate, centers: [Coordinate?]) -> Int? {
        var nearest: Int?
        var nearestDistance = Double.infinity
        for (index, center) in centers.enumerated() {
            guard let center else { continue }
            let distance = Geo.distance(point, center)
            if distance < nearestDistance {
                nearest = index
                nearestDistance = distance
            }
        }
        return nearest
    }

    private static func visitCost(_ candidate: PlannerCandidate, _ options: PlannerOptions) -> Double {
        Double(candidate.visitMinutes) * options.pace.visitFactor
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
