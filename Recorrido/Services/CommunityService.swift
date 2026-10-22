import CloudKit
import CoreLocation
import Observation

/// A route someone published to the community feed.
struct CommunityRoute: Identifiable, Hashable {
    /// The CloudKit record name.
    var id: String
    var title: String
    var city: String
    var country: String?
    var emoji: String
    var summary: String
    var authorName: String
    /// The author's CloudKit user record name; `nil` for one's own routes.
    var authorID: String?
    var isMine: Bool
    var stopCount: Int
    var dayCount: Int
    var createdAt: Date
    var payload: String

    init?(record: CKRecord) {
        guard let payload = record["payload"] as? String, let title = record["title"] as? String else { return nil }
        id = record.recordID.recordName
        self.title = title
        self.payload = payload
        city = record["city"] as? String ?? ""
        country = record["country"] as? String
        emoji = record["emoji"] as? String ?? "🗺️"
        summary = record["summary"] as? String ?? ""
        authorName = (record["authorName"] as? String)?.nilIfEmpty ?? String(localized: "A traveller")
        let creator = record.creatorUserRecordID?.recordName
        isMine = creator == CKCurrentUserDefaultName
        authorID = isMine ? nil : creator
        stopCount = (record["stopCount"] as? Int) ?? 0
        dayCount = max(1, (record["dayCount"] as? Int) ?? 1)
        createdAt = record.creationDate ?? Date()
    }

    /// The route itself, unpacked from the same format as shared links.
    func route() throws -> Route {
        var route = try ShareCodec.route(fromPayload: payload)
        route.author = authorName
        return route
    }
}

enum CommunityError: LocalizedError {
    case unavailable, notSignedIn, notClean, tooShort

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "The community feed is not available in this version of the app.")
        case .notSignedIn:
            String(localized: "Sign in to iCloud in the iPhone settings to publish routes.")
        case .notClean:
            String(localized: "The route contains words that are not allowed in the feed.")
        case .tooShort:
            String(localized: "Add at least two stops before publishing.")
        }
    }
}

/// The community feed: routes travellers publish for everyone, kept in the
/// public CloudKit database of the app's iCloud container. No own server.
///
/// CloudKit crashes an app that lacks the iCloud entitlement, and a free
/// Apple ID cannot sign with it, so the feed exists only when the app's code
/// signature includes a CloudKit container.
@MainActor
@Observable
final class Community {
    static let routeType = "SharedRoute"
    static let reportType = "RouteReport"

    /// The CloudKit container from the app's entitlements, if any.
    static let containerID: String? = CodeSignature.cloudKitContainers(in: CodeSignature.current()).first

    private(set) var isSignedIn = false
    @ObservationIgnored private let container: CKContainer?

    init() {
        container = Self.containerID.map { CKContainer(identifier: $0) }
    }

    var isAvailable: Bool { container != nil }

    private func database() throws -> CKDatabase {
        guard let container else { throw CommunityError.unavailable }
        return container.publicCloudDatabase
    }

    func refreshAccount() async {
        guard let container else { return }
        isSignedIn = (try? await container.accountStatus()) == .available
    }

    /// Lowercased name without diacritics: "Плёс" and "плес" match.
    static func cityKey(_ name: String) -> String {
        PlaceClassifier.normalize(name).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reading

    func latest() async throws -> [CommunityRoute] {
        try await run(NSPredicate(value: true))
    }

    /// Routes of a town by any of its names.
    func routes(inCity names: [String]) async throws -> [CommunityRoute] {
        let keys = Array(Set(names.map(Self.cityKey).filter { !$0.isEmpty }))
        guard !keys.isEmpty else { return [] }
        return try await run(NSPredicate(format: "cityKey IN %@", keys))
    }

    /// Towns whose name starts with what the user typed.
    func search(city text: String) async throws -> [CommunityRoute] {
        let key = Self.cityKey(text)
        guard !key.isEmpty else { return [] }
        return try await run(NSPredicate(format: "cityKey BEGINSWITH %@", key))
    }

    /// Routes starting within `radius` meters, nearest first. The location is
    /// rounded to about a kilometre before it leaves the phone.
    func nearby(_ coordinate: Coordinate, radius: Double = 60_000) async throws -> [CommunityRoute] {
        let rounded = coordinate.rounded(toDigits: 2)
        let location = CLLocation(latitude: rounded.latitude, longitude: rounded.longitude)
        let predicate = NSPredicate(format: "distanceToLocation:fromLocation:(location, %@) < %f", location, radius)
        return try await run(predicate, sort: CKLocationSortDescriptor(key: "location", relativeLocation: location))
    }

    private func run(_ predicate: NSPredicate, sort: NSSortDescriptor? = nil) async throws -> [CommunityRoute] {
        let query = CKQuery(recordType: Self.routeType, predicate: predicate)
        query.sortDescriptors = [sort ?? NSSortDescriptor(key: "creationDate", ascending: false)]
        let (results, _) = try await database().records(matching: query, resultsLimit: 60)
        return results.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return CommunityRoute(record: record)
        }
    }

    // MARK: - Writing

    /// Publishes a route, or updates the copy published before.
    func publish(_ route: Route, author: String, replacing publication: Publication?) async throws -> Publication {
        let database = try self.database()
        await refreshAccount()
        guard isSignedIn else { throw CommunityError.notSignedIn }
        guard route.stopCount >= 2 else { throw CommunityError.tooShort }
        var route = route
        route.author = author
        guard ContentFilter.isClean(route) else { throw CommunityError.notClean }

        var record = CKRecord(recordType: Self.routeType)
        if let publication, let existing = try? await database.record(for: CKRecord.ID(recordName: publication.recordName)) {
            record = existing
        }
        record["payload"] = try ShareCodec.payload(for: route, detail: .full)
        record["title"] = route.title
        record["city"] = route.city
        record["cityKey"] = Self.cityKey(route.city)
        record["country"] = route.country
        record["emoji"] = route.emoji
        record["summary"] = route.summary
        record["language"] = route.language
        record["authorName"] = author
        record["stopCount"] = route.stopCount
        record["dayCount"] = route.days.count
        if let start = route.allStops.first?.coordinate {
            record["location"] = CLLocation(latitude: start.latitude, longitude: start.longitude)
        }
        let saved = try await database.save(record)
        return Publication(recordName: saved.recordID.recordName, date: Date())
    }

    func unpublish(_ publication: Publication) async throws {
        _ = try await database().deleteRecord(withID: CKRecord.ID(recordName: publication.recordName))
    }

    /// Sends a complaint for the developer to review in the CloudKit Console.
    func report(_ route: CommunityRoute, reason: String) async throws {
        let report = CKRecord(recordType: Self.reportType)
        report["route"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: route.id), action: .none)
        report["routeTitle"] = route.title
        report["reason"] = reason
        _ = try await database().save(report)
    }
}
