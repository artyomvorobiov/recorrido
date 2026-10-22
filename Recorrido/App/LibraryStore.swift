import Foundation
import Observation

/// The user's own routes, bookmarks, finished routes and check-ins.
@MainActor
@Observable
final class LibraryStore {
    private(set) var data = LibraryData()
    private(set) var visits: [Visit] = []
    @ObservationIgnored private let storage: StorageLayout

    init(storage: StorageLayout) {
        self.storage = storage
        reload()
    }

    /// Own, generated and imported routes, newest first.
    var routes: [Route] {
        data.routes.sorted { $0.updatedAt > $1.updatedAt }
    }

    var savedRouteIDs: [String] { data.savedRouteIDs }

    func route(id: String) -> Route? {
        data.routes.first { $0.id == id }
    }

    func isSaved(_ routeID: String) -> Bool {
        data.savedRouteIDs.contains(routeID)
    }

    func reload() {
        data = storage.library.readSafely() ?? LibraryData()
        reloadVisits()
    }

    func reloadVisits() {
        visits = storage.visits.readSafely() ?? []
    }

    func upsert(_ route: Route) {
        var route = route
        route.updatedAt = Date()
        if let index = data.routes.firstIndex(where: { $0.id == route.id }) {
            data.routes[index] = route
        } else {
            data.routes.append(route)
        }
        persist()
    }

    func delete(routeID: String) {
        data.routes.removeAll { $0.id == routeID }
        persist()
    }

    func toggleSaved(_ routeID: String) {
        if let index = data.savedRouteIDs.firstIndex(of: routeID) {
            data.savedRouteIDs.remove(at: index)
        } else {
            data.savedRouteIDs.insert(routeID, at: 0)
        }
        persist()
    }

    func markCompleted(_ route: Route) {
        data.completed.append(CompletedRoute(routeID: route.id, title: route.title, city: route.city, date: Date()))
        persist()
    }

    // MARK: - Guide

    var progress: GuideProgress { data.progress }

    func toggleFound(_ stop: Stop, item: Int) {
        data.progress.toggle(stop.guideKey, item: item)
        persist()
    }

    /// The quiz of an own stop, by the key progress is stored under.
    func quiz(forKey key: String) -> Quiz? {
        for route in data.routes {
            if let stop = route.allStops.first(where: { $0.guideKey == key }), let quiz = stop.guide?.quiz {
                return quiz
            }
        }
        return nil
    }

    func answer(_ stop: Stop, option: Int) {
        guard data.progress.answers[stop.guideKey] == nil else { return }
        data.progress.answer(stop.guideKey, option: option)
        persist()
    }

    // MARK: - Community feed

    func publication(for routeID: String) -> Publication? {
        data.publications[routeID]
    }

    func setPublication(_ publication: Publication?, for routeID: String) {
        data.publications[routeID] = publication
        persist()
    }

    var blockedAuthors: Set<String> { Set(data.blockedAuthors) }
    var hiddenRecords: Set<String> { Set(data.hiddenRecords) }

    func block(author: String) {
        guard !data.blockedAuthors.contains(author) else { return }
        data.blockedAuthors.append(author)
        persist()
    }

    func unblockAll() {
        data.blockedAuthors = []
        persist()
    }

    func hide(record: String) {
        guard !data.hiddenRecords.contains(record) else { return }
        data.hiddenRecords.append(record)
        persist()
    }

    func eraseEverything() {
        data = LibraryData()
        visits = []
        storage.library.remove()
        storage.visits.remove()
    }

    private func persist() {
        do {
            try storage.library.write(data)
        } catch {
            print("Recorrido: cannot save the library: \(error)")
        }
    }

    // MARK: - Passport

    struct TownStamp: Identifiable, Hashable {
        var id: String { town }
        var town: String
        var firstVisit: Date
        var places: Int
    }

    var stamps: [TownStamp] {
        Dictionary(grouping: visits, by: \.city)
            .map { town, visits in
                TownStamp(town: town, firstVisit: visits.map(\.date).min() ?? Date(), places: Set(visits.map(\.stopID)).count)
            }
            .sorted { $0.firstVisit > $1.firstVisit }
    }

    var walkedMeters: Double {
        visits.reduce(0) { $0 + $1.walked }
    }

    var placesVisited: Int {
        Set(visits.map(\.stopID)).count
    }
}
