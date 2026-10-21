import MapKit
import Observation

/// Path and time of one leg of a route.
struct LegGeometry: Codable, Hashable, Sendable {
    var points: [Coordinate]
    /// Meters along the path.
    var distance: Double
    var seconds: Double
    /// `true` when there was no real path (offline, transit, ferry…):
    /// the map then draws a dashed straight line.
    var isEstimate: Bool

    var minutes: Double { seconds / 60 }
}

/// Real walking and driving paths from Apple Maps, cached on disk so a
/// route viewed once still shows its paths offline.
actor DirectionsService {
    private var memory: [String: LegGeometry] = [:]
    private var inFlight: [String: Task<LegGeometry, Never>] = [:]
    private var loadedFromDisk = false
    private var saveTask: Task<Void, Never>?
    private let cacheURL: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheURL = caches.appendingPathComponent("directions-v1.json")
    }

    static func key(from a: Coordinate, to b: Coordinate, mode: TransportMode) -> String {
        let from = a.rounded(toDigits: 5)
        let to = b.rounded(toDigits: 5)
        return "\(from.latitude),\(from.longitude)>\(to.latitude),\(to.longitude)>\(mode.rawValue)"
    }

    func leg(from a: Coordinate, to b: Coordinate, mode: TransportMode) async -> LegGeometry {
        loadFromDiskIfNeeded()
        let key = Self.key(from: a, to: b, mode: mode)
        if let cached = memory[key] { return cached }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await Self.compute(from: a, to: b, mode: mode) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if !result.isEstimate || !mode.hasRoadRouting {
            memory[key] = result
            scheduleSave()
        }
        return result
    }

    private static func compute(from a: Coordinate, to b: Coordinate, mode: TransportMode) async -> LegGeometry {
        let estimate = RouteEstimator.leg(from: a, to: b, mode: mode)
        let straight = LegGeometry(points: [a, b], distance: estimate.distance, seconds: estimate.minutes * 60, isEstimate: true)
        guard Geo.distance(a, b) > 30 else { return straight }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a.cl))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.cl))
        switch mode {
        case .walk, .bike:
            request.transportType = .walking
        case .car:
            request.transportType = .automobile
        case .metro, .tram, .bus, .train, .transit:
            // Apple Maps gives transit times but no drawable path.
            request.transportType = .transit
            if let eta = try? await MKDirections(request: request).calculateETA() {
                return LegGeometry(points: [a, b], distance: estimate.distance, seconds: eta.expectedTravelTime, isEstimate: true)
            }
            return straight
        case .ferry, .funicular, .cableCar:
            return straight
        }

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return straight }
            let points = Geo.simplify(route.polyline.coordinateList.map { Coordinate($0) }, tolerance: 3)
            var seconds = route.expectedTravelTime
            if mode == .bike {
                seconds = route.distance / (TransportMode.bike.speedKmh / 3.6)
            }
            return LegGeometry(points: points, distance: route.distance, seconds: seconds, isEstimate: false)
        } catch {
            return straight
        }
    }

    private func loadFromDiskIfNeeded() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: LegGeometry].self, from: data) {
            memory.merge(saved) { current, _ in current }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self.save()
        }
    }

    private func save() {
        // Keep the cache small: the most recent few thousand legs are plenty.
        if memory.count > 3000 {
            memory = Dictionary(uniqueKeysWithValues: memory.prefix(2000).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(memory) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

private extension TransportMode {
    var hasRoadRouting: Bool {
        switch self {
        case .walk, .bike, .car: true
        default: false
        }
    }
}

/// Paths for the stops of one day, filled in as directions arrive.
@MainActor
@Observable
final class RouteDirections {
    private(set) var legs: [String: LegGeometry] = [:]
    private(set) var isLoading = false

    func leg(from: Stop, to: Stop) -> LegGeometry? {
        legs[DirectionsService.key(from: from.coordinate, to: to.coordinate, mode: to.arrivalMode)]
    }

    func load(_ stops: [Stop], using service: DirectionsService) async {
        isLoading = true
        defer { isLoading = false }
        for index in stops.indices.dropFirst() {
            if Task.isCancelled { return }
            let from = stops[index - 1]
            let to = stops[index]
            let key = DirectionsService.key(from: from.coordinate, to: to.coordinate, mode: to.arrivalMode)
            if legs[key] != nil { continue }
            legs[key] = await service.leg(from: from.coordinate, to: to.coordinate, mode: to.arrivalMode)
        }
    }

    /// Legs for the given stops in order; missing ones are estimated.
    func geometry(for stops: [Stop]) -> [LegGeometry] {
        stops.indices.dropFirst().map { index in
            let from = stops[index - 1]
            let to = stops[index]
            if let leg = leg(from: from, to: to) { return leg }
            let estimate = RouteEstimator.leg(from: from.coordinate, to: to.coordinate, mode: to.arrivalMode)
            return LegGeometry(points: [from.coordinate, to.coordinate], distance: estimate.distance,
                               seconds: estimate.minutes * 60, isEstimate: true)
        }
    }
}
