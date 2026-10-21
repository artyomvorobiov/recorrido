import ActivityKit
import UserNotifications

/// Starts, updates and ends the walk's Live Activity.
@MainActor
final class LiveActivityController {
    private var lastUpdate = Date.distantPast
    private var lastDistance: Double?

    func start(trip: ActiveTrip) async {
        await LiveActivitySync.endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: TripActivityAttributes.ContentState(trip: trip, distance: nil), staleDate: nil)
        _ = try? Activity.request(attributes: TripActivityAttributes(trip: trip), content: content, pushType: nil)
        lastUpdate = Date()
        lastDistance = nil
    }

    /// Sends a new state; distance-only changes are throttled to save battery.
    func update(trip: ActiveTrip, distance: Double?, force: Bool = false) {
        if !force, let distance, let lastDistance {
            let moved = abs(distance - lastDistance)
            if moved < 25 && Date().timeIntervalSince(lastUpdate) < 20 { return }
        }
        lastUpdate = Date()
        lastDistance = distance
        Task { await LiveActivitySync.update(trip: trip, distance: distance) }
    }

    func end() {
        lastDistance = nil
        Task { await LiveActivitySync.endAll() }
    }
}

/// Local notifications for arrivals while the phone is in a pocket.
enum Notifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func arrival(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "arrival-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
