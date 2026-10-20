import Foundation

/// How long a generated trip should be.
enum TripLength: Hashable, Sendable {
    /// Decide from how many interesting places there are around.
    case auto
    case hours(Int)
    case days(Int)

    var dayCount: Int {
        if case .days(let days) = self { return max(1, days) }
        return 1
    }
}

struct GeneratorRequest: Sendable {
    var cityName: String
    var center: Coordinate
    /// Where every day starts: hotel, station, the traveller's position.
    /// `nil` starts the day at the first stop.
    var start: Coordinate?
    var startTitle: String = "Start"
    var returnToStart: Bool = false
    var length: TripLength = .auto
    var pace: Pace = .normal
    var mobility: Mobility = .car
    /// Preferred kinds of places; empty means "everything".
    var interests: Set<PlaceCategory> = []
    var language: String = "ru"
}

enum GeneratorStage: Sendable {
    case searching, selecting, describing
}

struct GeneratedPlan: Sendable {
    var days: [RouteDay]
    /// The length actually planned (never `.auto`).
    var length: TripLength
    var language: String
    var isSmallTown: Bool
    /// How many interesting places were considered.
    var candidateCount: Int
}

enum GeneratorError: Error {
    case nothingFound
}

/// Builds a route for any town from Wikipedia articles with coordinates:
/// finds places, keeps the ones that look like sights, ranks them by how
/// notable they are and how far they are, then plans days with `RoutePlanner`.
struct CityRouteGenerator {
    var client: WikipediaClient

    func generate(
        _ request: GeneratorRequest,
        progress: @escaping @Sendable (GeneratorStage) -> Void = { _ in }
    ) async throws -> GeneratedPlan {
        progress(.searching)
        var pages = try await client.places(around: request.center, radius: 10_000, limit: 500)
        // Fewer results than the limit means we got everything within 10 km.
        let isSmallTown = pages.count < 450
        var candidates = classify(pages, request: request)

        let length = request.length == .auto ? suggestedLength(for: candidates) : request.length
        if !isSmallTown, case .days = length {
            // Big cities have so many articles that the 500 nearest cover only
            // the very center; sample a ring (or two) around it as well.
            for point in ringPoints(around: request.center, length: length) {
                if let more = try? await client.places(around: point.center, radius: point.radius, limit: 200) {
                    pages += more
                }
            }
            candidates = classify(pages, request: request)
        }

        progress(.selecting)
        let scored = diversified(score(candidates, request: request, length: length))
        guard !scored.isEmpty else { throw GeneratorError.nothingFound }

        let options = plannerOptions(for: request, length: length)
        let planned = RoutePlanner.plan(scored.map(\.plannerCandidate), options: options)
        guard !planned.isEmpty else { throw GeneratorError.nothingFound }

        progress(.describing)
        let byID = Dictionary(scored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pageIDs = planned.flatMap { $0 }.compactMap { byID[$0.id]?.page.pageID }
        let summaries = (try? await client.summaries(for: pageIDs)) ?? [:]

        var days: [RouteDay] = []
        for (dayIndex, day) in planned.enumerated() {
            var stops: [Stop] = []
            if let start = request.start {
                stops.append(Stop(id: "start-\(dayIndex)", title: request.startTitle, coordinate: start,
                                  category: .other, visitMinutes: 0))
            }
            for item in day {
                guard let candidate = byID[item.id] else { continue }
                let summary = summaries[candidate.page.pageID]
                var details = summary?.extract ?? ""
                if details.isEmpty, let description = candidate.page.shortDescription {
                    details = description.prefix(1).uppercased() + description.dropFirst()
                }
                stops.append(Stop(
                    id: candidate.id,
                    title: candidate.page.title,
                    coordinate: candidate.page.coordinate,
                    details: details,
                    category: candidate.category,
                    visitMinutes: candidate.visitMinutes,
                    wikiTitle: candidate.page.title,
                    wikiLanguage: client.language,
                    imageURL: summary?.thumbnail
                ))
            }
            if let start = request.start, request.returnToStart {
                stops.append(Stop(id: "finish-\(dayIndex)", title: request.startTitle, coordinate: start,
                                  category: .other, visitMinutes: 0))
            }
            for index in stops.indices.dropFirst() {
                let distance = Geo.distance(stops[index - 1].coordinate, stops[index].coordinate)
                stops[index].arrival = Arrival(mode: request.mobility.mode(forDistance: distance, pace: request.pace))
            }
            days.append(RouteDay(stops: stops))
        }

        return GeneratedPlan(
            days: days,
            length: length,
            language: client.language,
            isSmallTown: isSmallTown,
            candidateCount: scored.count
        )
    }

    // MARK: - Steps

    struct Candidate {
        var page: WikiPage
        var category: PlaceCategory
        /// log2 of the article size in KB: 2 KB → 1, 32 KB → 5, 128 KB → 7.
        var notability: Double
        var distance: Double
        var score: Double = 0

        var id: String { "wiki-\(page.pageID)" }

        var visitMinutes: Int {
            switch category {
            case .museum: notability >= 6.5 ? 120 : notability >= 5 ? 75 : 45
            case .palace, .castle: notability >= 6 ? 90 : 50
            case .church: notability >= 6 ? 40 : 20
            default: category.defaultVisitMinutes
            }
        }

        var plannerCandidate: PlannerCandidate {
            PlannerCandidate(id: id, coordinate: page.coordinate, score: score, visitMinutes: visitMinutes)
        }
    }

    func classify(_ pages: [WikiPage], request: GeneratorRequest) -> [Candidate] {
        var seen = Set<Int>()
        var result: [Candidate] = []
        for page in pages where seen.insert(page.pageID).inserted {
            guard page.coordinate.isValid,
                  let category = PlaceClassifier.classify(
                      title: page.title,
                      description: page.shortDescription,
                      geoType: page.geoType,
                      cityName: request.cityName
                  ) else { continue }
            result.append(Candidate(
                page: page,
                category: category,
                notability: log2(Double(max(page.length, 2000)) / 1000),
                distance: Geo.distance(request.center, page.coordinate)
            ))
        }
        return result
    }

    /// Small town with a handful of sights → half a day; a big city → three days.
    func suggestedLength(for candidates: [Candidate]) -> TripLength {
        let notable = candidates.filter { $0.notability >= 4 && $0.distance <= 6000 }.count
        switch notable {
        case ..<6: return .hours(4)
        case ..<15: return .days(1)
        case ..<31: return .days(2)
        default: return .days(3)
        }
    }

    func score(_ candidates: [Candidate], request: GeneratorRequest, length: TripLength) -> [Candidate] {
        let reach: Double
        var penaltyPerKm: Double
        switch length {
        case .hours(let hours) where hours <= 2:
            reach = request.mobility == .walking ? 1500 : 3000
            penaltyPerKm = 1.2
        case .hours:
            reach = request.mobility == .walking ? 2500 : request.mobility == .transit ? 5000 : 8000
            penaltyPerKm = 0.8
        case .days(let days) where days >= 2:
            reach = 16_000
            penaltyPerKm = 0.12
        default:
            reach = request.mobility == .walking ? 4000 : request.mobility == .transit ? 8000 : 12_000
            penaltyPerKm = 0.3
        }
        if request.mobility == .car { penaltyPerKm *= 0.5 }
        if request.mobility == .transit { penaltyPerKm *= 0.7 }
        let origin = request.start ?? request.center

        return candidates.compactMap { (candidate: Candidate) -> Candidate? in
            let distance = Geo.distance(origin, candidate.page.coordinate)
            guard distance <= reach else { return nil }
            var item = candidate
            var score = candidate.notability * PlaceClassifier.weight(of: candidate.category)
            if !request.interests.isEmpty {
                score *= request.interests.contains(candidate.category) ? 1.4 : 0.75
            }
            score -= distance / 1000 * penaltyPerKm
            guard score > 0.5 else { return nil }
            item.score = score
            return item
        }
    }

    /// Drops near-duplicates (a tower and the wall it stands in) and gently
    /// pushes down places crowded around ones already chosen, so a walk is
    /// not ten stops in one square.
    func diversified(_ candidates: [Candidate]) -> [Candidate] {
        var kept: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            let distances = kept.map { Geo.distance($0.page.coordinate, candidate.page.coordinate) }
            if distances.contains(where: { $0 < 40 }) { continue }
            var item = candidate
            let crowd = distances.filter { $0 < 150 }.count
            if crowd >= 2 { item.score *= 0.7 }
            kept.append(item)
        }
        return kept.sorted { $0.score > $1.score }
    }

    func plannerOptions(for request: GeneratorRequest, length: TripLength) -> PlannerOptions {
        var options = PlannerOptions()
        options.pace = request.pace
        options.mobility = request.mobility
        options.start = request.start
        options.returnToStart = request.returnToStart && request.start != nil
        switch length {
        case .hours(let hours):
            options.days = 1
            options.minutesPerDay = max(60, hours * 60)
            options.maxStopsPerDay = min(12, hours * 2 + 2)
        case .days(let days):
            options.days = max(1, days)
            options.minutesPerDay = request.pace.minutesPerDay
            switch request.pace {
            case .relaxed: options.maxStopsPerDay = 8
            case .normal: options.maxStopsPerDay = 10
            case .active: options.maxStopsPerDay = 12
            }
        case .auto:
            options.minutesPerDay = request.pace.minutesPerDay
        }
        return options
    }

    struct SamplePoint {
        var center: Coordinate
        var radius: Int
    }

    func ringPoints(around center: Coordinate, length: TripLength) -> [SamplePoint] {
        var points: [SamplePoint] = []
        for index in 0..<6 {
            let bearing = Double(index) * 60
            points.append(SamplePoint(center: Geo.destination(from: center, distance: 2800, bearing: bearing), radius: 1800))
        }
        if length.dayCount >= 2 {
            for index in 0..<8 {
                let bearing = Double(index) * 45 + 22.5
                points.append(SamplePoint(center: Geo.destination(from: center, distance: 6000, bearing: bearing), radius: 2800))
            }
        }
        return points
    }
}
