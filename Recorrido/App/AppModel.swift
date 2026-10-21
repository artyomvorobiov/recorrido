import Observation
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case explore, library, passport
}

/// A route someone sent us, waiting for "Save".
struct ImportRequest: Identifiable {
    let id = UUID()
    var route: Route
}

/// Opens the any-town generator, optionally for a known town.
struct GeneratorLaunch: Identifiable {
    let id = UUID()
    var townName: String?
    var coordinate: Coordinate?
}

/// App-wide state shared by all screens.
@MainActor
@Observable
final class AppModel {
    var tab: AppTab = .explore
    var explorePath = NavigationPath()
    var libraryPath = NavigationPath()
    private(set) var catalog: Catalog = .empty
    var importRequest: ImportRequest?
    var generatorLaunch: GeneratorLaunch?
    var alertMessage: String?

    let library: LibraryStore
    let trip: TripController
    let media = WikiMedia()
    @ObservationIgnored let directions = DirectionsService()

    init() {
        let storage = AppGroup.storage
        library = LibraryStore(storage: storage)
        trip = TripController(storage: storage)
        catalog = CatalogLoader.load()
        trip.routeLookup = { [weak self] id in self?.route(id: id) }
        trip.onCheckIn = { [weak self] in self?.library.reloadVisits() }
        trip.onFinish = { [weak self] route in self?.library.markCompleted(route) }
        trip.restore()
    }

    func reloadCatalog() {
        catalog = CatalogLoader.load()
    }

    // MARK: - Routes

    func route(id: String) -> Route? {
        library.route(id: id) ?? catalog.route(id: id)
    }

    /// The freshest version of a route (it may have been edited).
    func latest(_ route: Route) -> Route {
        self.route(id: route.id) ?? route
    }

    func isInLibrary(_ route: Route) -> Bool {
        library.route(id: route.id) != nil
    }

    func isSaved(_ route: Route) -> Bool {
        route.source == .curated ? library.isSaved(route.id) : isInLibrary(route)
    }

    /// Bookmarks a catalog route; for other routes adds them to My routes.
    func toggleSaved(_ route: Route) {
        if route.source == .curated {
            library.toggleSaved(route.id)
        } else if isInLibrary(route) {
            library.delete(routeID: route.id)
        } else {
            library.upsert(route)
        }
    }

    /// An editable copy of a catalog or received route.
    func makeEditableCopy(of route: Route) -> Route {
        let copy = route.userCopy()
        library.upsert(copy)
        return copy
    }

    func savedCatalogRoutes() -> [Route] {
        library.savedRouteIDs.compactMap { catalog.route(id: $0) }
    }

    func city(for route: Route) -> City? {
        catalog.city(id: route.cityID)
    }

    /// "190 km from Moscow" for towns within a day's drive of a big city.
    func distanceHint(for coordinate: Coordinate) -> String? {
        let nearest = AppConfig.hubs
            .map { (name: $0.name, distance: Geo.distance($0.coordinate, coordinate)) }
            .min { $0.distance < $1.distance }
        guard let nearest, nearest.distance > 15_000, nearest.distance < 700_000 else { return nil }
        let kilometers = Int((nearest.distance * 1.25 / 1000 / 10).rounded() * 10)
        return String(localized: "≈ \(kilometers) km from \(nearest.name)")
    }

    // MARK: - Links and files

    func handle(url: URL) {
        if url.isFileURL {
            importFile(at: url)
            return
        }
        if url.scheme == ShareCodec.urlScheme {
            switch url.host {
            case "trip":
                if trip.active != nil { trip.isPresented = true }
                return
            case "route":
                open(routeID: url.lastPathComponent)
                return
            case "generate":
                generatorLaunch = GeneratorLaunch()
                return
            default:
                break
            }
        }
        guard let payload = ShareCodec.payload(in: url) else { return }
        do {
            importRequest = ImportRequest(route: try ShareCodec.route(fromPayload: payload))
        } catch {
            alertMessage = String(localized: "This link doesn't contain a route. Maybe it was cut off — ask for the link again.")
        }
    }

    func open(routeID: String) {
        guard let route = route(id: routeID) else { return }
        trip.isPresented = false
        tab = .explore
        explorePath = NavigationPath()
        explorePath.append(route)
    }

    private func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let route = try RouteFile.read(from: url)
            importRequest = ImportRequest(route: route)
        } catch {
            alertMessage = String(localized: "This file can't be opened as a route.")
        }
    }

    /// Stores a received route in My routes and shows it.
    func saveImported(_ route: Route) {
        var route = route
        if library.route(id: route.id) != nil { route.id = UUID().uuidString }
        library.upsert(route)
        tab = .library
        libraryPath = NavigationPath()
        libraryPath.append(route)
    }

    func didBecomeActive() {
        trip.reloadFromDisk()
        library.reloadVisits()
        if trip.arrivedStopID != nil, trip.active != nil {
            trip.isPresented = true
        }
    }
}
