import Foundation

/// A Codable value kept in a JSON file. Writes are atomic.
struct JSONFile<Value: Codable> {
    let url: URL

    func read() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONCoders.decoder.decode(Value.self, from: data)
    }

    func write(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoders.encoder.encode(value).write(to: url, options: [.atomic])
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Moves an unreadable file aside so it is never overwritten by mistake.
    func quarantine() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    /// Reads the value; a corrupt file is set aside and `nil` returned.
    func readSafely() -> Value? {
        do {
            return try read()
        } catch {
            quarantine()
            return nil
        }
    }
}

/// Everything the user keeps: own routes, bookmarks, finished routes.
struct LibraryData: Codable, Sendable {
    var routes: [Route] = []
    /// Bookmarked catalog routes.
    var savedRouteIDs: [String] = []
    var completed: [CompletedRoute] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case routes, savedRouteIDs, completed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        savedRouteIDs = try container.decodeIfPresent([String].self, forKey: .savedRouteIDs) ?? []
        completed = try container.decodeIfPresent([CompletedRoute].self, forKey: .completed) ?? []
    }
}

struct CompletedRoute: Codable, Hashable, Sendable {
    var routeID: String
    var title: String
    var city: String
    var date: Date
}

/// A stop the traveller checked in at — a stamp in the passport.
struct Visit: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var stopID: String
    var routeID: String
    var title: String
    var city: String
    var coordinate: Coordinate
    var date: Date
    /// Walking distance from the previous checked-in stop, meters.
    var walked: Double = 0
}

/// One stop of the active walk, with just what the widget needs.
struct TripStop: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var coordinate: Coordinate
    /// How to get here from the previous stop.
    var mode: TransportMode
    var category: PlaceCategory
}

/// The walk in progress. Shared with the widget and the Live Activity
/// through the app group container.
struct ActiveTrip: Codable, Hashable, Sendable {
    var routeID: String
    var routeTitle: String
    var city: String
    var emoji: String
    var dayIndex: Int
    var dayCount: Int
    var stops: [TripStop]
    /// Index of the stop the traveller is heading to.
    var currentIndex: Int
    var visitedIDs: [String]
    var startedAt: Date
    var updatedAt: Date

    init(route: Route, dayIndex: Int, now: Date = Date()) {
        let index = min(max(0, dayIndex), max(0, route.days.count - 1))
        routeID = route.id
        routeTitle = route.title
        city = route.city
        emoji = route.emoji
        self.dayIndex = index
        dayCount = route.days.count
        let day = route.days.indices.contains(index) ? route.days[index].stops : []
        stops = day.map {
            TripStop(id: $0.id, title: $0.title, coordinate: $0.coordinate, mode: $0.arrivalMode, category: $0.category)
        }
        currentIndex = 0
        visitedIDs = []
        startedAt = now
        updatedAt = now
    }

    var isFinished: Bool { currentIndex >= stops.count }
    var nextStop: TripStop? { stops.indices.contains(currentIndex) ? stops[currentIndex] : nil }
    var visitedCount: Int { visitedIDs.count }

    var progress: Double {
        stops.isEmpty ? 1 : Double(min(currentIndex, stops.count)) / Double(stops.count)
    }

    /// Marks the current stop as visited and moves on. Returns that stop.
    @discardableResult
    mutating func checkIn(now: Date = Date()) -> TripStop? {
        guard let stop = nextStop else { return nil }
        if !visitedIDs.contains(stop.id) { visitedIDs.append(stop.id) }
        currentIndex += 1
        updatedAt = now
        return stop
    }

    mutating func skip(now: Date = Date()) {
        guard !isFinished else { return }
        currentIndex += 1
        updatedAt = now
    }

    mutating func stepBack(now: Date = Date()) {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        visitedIDs.removeAll { $0 == stops[currentIndex].id }
        updatedAt = now
    }

    mutating func jump(to stopID: String, now: Date = Date()) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        currentIndex = index
        updatedAt = now
    }
}

/// File locations inside the storage directory (the app group container
/// when available, so the widget sees the same data).
struct StorageLayout: Sendable {
    var directory: URL

    var library: JSONFile<LibraryData> { JSONFile(url: directory.appendingPathComponent("library.json")) }
    var visits: JSONFile<[Visit]> { JSONFile(url: directory.appendingPathComponent("visits.json")) }
    var trip: JSONFile<ActiveTrip> { JSONFile(url: directory.appendingPathComponent("trip.json")) }
}

/// Check-ins are written here by the app and by the widget button alike.
enum TripLog {
    /// Checks in at the current stop of the saved trip and records the visit.
    /// Returns the updated trip, or `nil` when there is no trip.
    @discardableResult
    static func checkIn(in layout: StorageLayout, now: Date = Date()) -> ActiveTrip? {
        guard var trip = layout.trip.readSafely() else { return nil }
        let index = trip.currentIndex
        guard let stop = trip.checkIn(now: now) else { return trip }
        try? layout.trip.write(trip)

        var walked = 0.0
        if index > 0, stop.mode == .walk, trip.visitedIDs.contains(trip.stops[index - 1].id) {
            walked = Geo.distance(trip.stops[index - 1].coordinate, stop.coordinate) * TransportMode.walk.detourFactor
        }
        var visits = layout.visits.readSafely() ?? []
        visits.append(Visit(stopID: stop.id, routeID: trip.routeID, title: stop.title, city: trip.city,
                            coordinate: stop.coordinate, date: now, walked: walked))
        try? layout.visits.write(visits)
        return trip
    }
}
