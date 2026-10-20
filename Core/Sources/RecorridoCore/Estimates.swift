import Foundation

/// How intense the day should be.
enum Pace: String, CaseIterable, Codable, Sendable {
    case relaxed, normal, active

    var walkingSpeedFactor: Double {
        switch self {
        case .relaxed: 0.85
        case .normal: 1
        case .active: 1.15
        }
    }

    /// Multiplier for the time spent at each stop.
    var visitFactor: Double {
        switch self {
        case .relaxed: 1.25
        case .normal: 1
        case .active: 0.8
        }
    }

    /// Time budget for a full day of sightseeing, minutes.
    var minutesPerDay: Int {
        switch self {
        case .relaxed: 300
        case .normal: 420
        case .active: 540
        }
    }

    /// Straight-line distance that still feels fine to walk, meters.
    var comfortableWalkMeters: Double {
        switch self {
        case .relaxed: 1300
        case .normal: 2000
        case .active: 3000
        }
    }
}

struct LegEstimate: Hashable, Sendable {
    var mode: TransportMode
    /// Meters along the way, not as the crow flies.
    var distance: Double
    var minutes: Double
}

struct DayEstimate: Hashable, Sendable {
    var visitMinutes: Double
    var travelMinutes: Double
    var distance: Double
    var walkingDistance: Double
    /// `legs[i]` leads from stop `i` to stop `i + 1`.
    var legs: [LegEstimate]

    var totalMinutes: Double { visitMinutes + travelMinutes }
}

struct RouteEstimate: Hashable, Sendable {
    var days: [DayEstimate]

    var totalMinutes: Double { days.reduce(0) { $0 + $1.totalMinutes } }
    var distance: Double { days.reduce(0) { $0 + $1.distance } }
    var walkingDistance: Double { days.reduce(0) { $0 + $1.walkingDistance } }
}

/// Quick offline time and distance estimates. The app refines legs with
/// real directions when they are available.
enum RouteEstimator {
    static func leg(from a: Coordinate, to b: Coordinate, mode: TransportMode, pace: Pace = .normal) -> LegEstimate {
        let straight = Geo.distance(a, b)
        let distance = straight * mode.detourFactor
        var speed = mode.speedKmh
        if mode == .walk { speed *= pace.walkingSpeedFactor }
        let overhead = straight < 50 ? 0 : mode.overheadMinutes
        return LegEstimate(mode: mode, distance: distance, minutes: distance / 1000 / speed * 60 + overhead)
    }

    static func day(_ day: RouteDay, pace: Pace = .normal) -> DayEstimate {
        let stops = day.stops
        var legs: [LegEstimate] = []
        for index in stops.indices.dropFirst() {
            legs.append(leg(from: stops[index - 1].coordinate, to: stops[index].coordinate,
                            mode: stops[index].arrivalMode, pace: pace))
        }
        let visit = stops.reduce(0.0) { $0 + Double($1.visitMinutes) * pace.visitFactor }
        return DayEstimate(
            visitMinutes: visit,
            travelMinutes: legs.reduce(0) { $0 + $1.minutes },
            distance: legs.reduce(0) { $0 + $1.distance },
            walkingDistance: legs.filter { $0.mode == .walk }.reduce(0) { $0 + $1.distance },
            legs: legs
        )
    }

    static func route(_ route: Route, pace: Pace = .normal) -> RouteEstimate {
        RouteEstimate(days: route.days.map { day($0, pace: pace) })
    }
}
