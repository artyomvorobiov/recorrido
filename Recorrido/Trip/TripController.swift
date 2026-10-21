import CoreLocation
import Observation
import UIKit
import WidgetKit

/// Runs the walk: which stop is next, how far it is, arrival detection,
/// the audio guide, the Live Activity and the widget.
@MainActor
@Observable
final class TripController {
    private(set) var active: ActiveTrip?
    /// The full route of the active walk (stories, tips, other days).
    private(set) var route: Route?
    var isPresented = false
    /// Set when the traveller is standing at the next stop.
    private(set) var arrivedStopID: String?
    private(set) var distanceToNext: Double?
    private(set) var bearingToNext: Double?

    let location = LocationService()
    let audio = AudioGuide()

    @ObservationIgnored var routeLookup: ((String) -> Route?)?
    @ObservationIgnored var onCheckIn: (() -> Void)?
    @ObservationIgnored var onFinish: ((Route) -> Void)?
    @ObservationIgnored private let storage: StorageLayout
    @ObservationIgnored private let live = LiveActivityController()
    @ObservationIgnored private var notified = Set<String>()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(storage: StorageLayout) {
        self.storage = storage
        location.onUpdate = { [weak self] location in
            self?.handle(location)
        }
        observer = NotificationCenter.default.addObserver(forName: TripSync.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadFromDisk() }
        }
    }

    var nextStop: Stop? {
        guard let id = active?.nextStop?.id else { return nil }
        return route?.stop(withID: id)
    }

    var currentDay: RouteDay? {
        guard let active, let route, route.days.indices.contains(active.dayIndex) else { return nil }
        return route.days[active.dayIndex]
    }

    var hasNextDay: Bool {
        guard let active else { return false }
        return active.dayIndex + 1 < active.dayCount
    }

    func isActive(_ route: Route) -> Bool {
        active?.routeID == route.id
    }

    // MARK: - Lifecycle

    /// Picks up a walk that was running when the app was closed.
    func restore() {
        guard let saved = storage.trip.readSafely() else { return }
        active = saved
        route = routeLookup?(saved.routeID)
        if route == nil {
            // The route is gone (deleted); nothing to continue.
            end()
            return
        }
        if !saved.isFinished { startTracking() }
    }

    func start(_ route: Route, day: Int) {
        let trip = ActiveTrip(route: route, dayIndex: day)
        active = trip
        self.route = route
        arrivedStopID = nil
        distanceToNext = nil
        notified.removeAll()
        save()
        isPresented = true
        startTracking()
        Task {
            await Notifier.requestPermission()
            await live.start(trip: trip)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func checkIn() {
        guard active != nil else { return }
        save()
        active = TripLog.checkIn(in: storage)
        arrivedStopID = nil
        afterChange(forceActivity: true)
        onCheckIn?()
        if active?.isFinished == true { didFinish() }
    }

    func skip() {
        active?.skip()
        arrivedStopID = nil
        save()
        afterChange(forceActivity: true)
        if active?.isFinished == true { didFinish() }
    }

    func stepBack() {
        active?.stepBack()
        arrivedStopID = nil
        save()
        afterChange(forceActivity: true)
        if active?.isFinished == false { startTracking() }
    }

    func goTo(stopID: String) {
        active?.jump(to: stopID)
        arrivedStopID = nil
        save()
        afterChange(forceActivity: true)
    }

    func startNextDay() {
        guard let route, let active, hasNextDay else { return }
        start(route, day: active.dayIndex + 1)
    }

    /// Ends the walk and removes it from the widget and lock screen.
    func end() {
        audio.stop()
        location.stop()
        active = nil
        route = nil
        arrivedStopID = nil
        distanceToNext = nil
        isPresented = false
        storage.trip.remove()
        live.end()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-reads the trip after the widget or the Live Activity changed it.
    func reloadFromDisk() {
        guard let saved = storage.trip.readSafely() else { return }
        let changed = saved != active
        active = saved
        if changed {
            arrivedStopID = nil
            onCheckIn?()
            if saved.isFinished { didFinish() }
        }
    }

    // MARK: - Internals

    private func startTracking() {
        let background = AppGroup.defaults.bool(forKey: SettingsKey.backgroundTracking)
        location.start(background: background)
    }

    private func save() {
        guard let active else { return }
        try? storage.trip.write(active)
    }

    private func afterChange(forceActivity: Bool) {
        if let active {
            live.update(trip: active, distance: distanceToNext, force: forceActivity)
        }
        if let here = location.location {
            handle(here)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func didFinish() {
        location.stop()
        if let route { onFinish?(route) }
        if let active { live.update(trip: active, distance: nil, force: true) }
    }

    private func handle(_ location: CLLocation) {
        guard let next = active?.nextStop else {
            distanceToNext = nil
            bearingToNext = nil
            return
        }
        let here = Coordinate(location.coordinate)
        let distance = Geo.distance(here, next.coordinate)
        distanceToNext = distance
        bearingToNext = Geo.bearing(from: here, to: next.coordinate)

        let radius = max(35, min(80, location.horizontalAccuracy))
        if distance <= radius, arrivedStopID != next.id {
            arrivedStopID = next.id
            arrived(at: next.id)
        }
        if let active {
            live.update(trip: active, distance: distance)
        }
    }

    private func arrived(at stopID: String) {
        guard let stop = route?.stop(withID: stopID) else { return }
        if UIApplication.shared.applicationState == .active {
            if AppGroup.defaults.bool(forKey: SettingsKey.autoPlay) {
                audio.speak(id: stop.id, text: AudioGuide.script(for: stop), language: route?.language)
            }
        } else if AppGroup.defaults.bool(forKey: SettingsKey.arrivalNotifications), !notified.contains(stop.id) {
            notified.insert(stop.id)
            let body = stop.details.isEmpty ? String(localized: "Open Recorrido to hear the story.") : stop.details.truncated(to: 180)
            Notifier.arrival(title: String(localized: "You've reached \(stop.title)"), body: body)
        }
    }
}
