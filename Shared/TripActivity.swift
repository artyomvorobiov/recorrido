import ActivityKit
import AppIntents
import Foundation
import WidgetKit

/// The Live Activity shown on the lock screen and in the Dynamic Island
/// while a walk is in progress.
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var nextTitle: String
        /// 1-based number of the stop the traveller is heading to.
        var nextNumber: Int
        var total: Int
        /// Stops already passed (visited or skipped).
        var passed: Int
        /// Meters to the next stop, when known.
        var distance: Double?
        var modeRaw: String
        var categoryRaw: String
        var finished: Bool

        var mode: TransportMode { TransportMode(rawValue: modeRaw) ?? .walk }
        var category: PlaceCategory { PlaceCategory(rawValue: categoryRaw) ?? .other }
        var progress: Double { total == 0 ? 1 : Double(passed) / Double(total) }
    }

    var routeID: String
    var routeTitle: String
    var city: String
    var emoji: String
}

extension TripActivityAttributes {
    init(trip: ActiveTrip) {
        self.init(routeID: trip.routeID, routeTitle: trip.routeTitle, city: trip.city, emoji: trip.emoji)
    }
}

extension TripActivityAttributes.ContentState {
    init(trip: ActiveTrip, distance: Double?) {
        let next = trip.nextStop
        self.init(
            nextTitle: next?.title ?? trip.routeTitle,
            nextNumber: min(trip.currentIndex + 1, max(1, trip.stops.count)),
            total: trip.stops.count,
            passed: min(trip.currentIndex, trip.stops.count),
            distance: next == nil ? nil : distance,
            modeRaw: (next?.mode ?? .walk).rawValue,
            categoryRaw: (next?.category ?? .other).rawValue,
            finished: trip.isFinished
        )
    }
}

/// Keeps every running Live Activity in step with the saved trip.
enum LiveActivitySync {
    static func update(trip: ActiveTrip?, distance: Double?) async {
        for activity in Activity<TripActivityAttributes>.activities {
            guard let trip, trip.routeID == activity.attributes.routeID else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let state = TripActivityAttributes.ContentState(trip: trip, distance: distance)
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func endAll() async {
        for activity in Activity<TripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

enum TripSync {
    /// Posted in the app process when the trip changed outside the app UI
    /// (widget or Live Activity button).
    static let changed = Notification.Name("RecorridoTripChanged")
}

/// "I'm here": marks the current stop of the walk as visited. Used by the
/// widget button and the Live Activity button. Being a `LiveActivityIntent`,
/// it runs in the app's process, so it can update the Live Activity too.
struct CheckInIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Check in at the stop"
    static let description = IntentDescription("Marks the current stop of your walk as visited.")

    init() {}

    func perform() async throws -> some IntentResult {
        let trip = TripLog.checkIn(in: AppGroup.storage)
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivitySync.update(trip: trip, distance: nil)
        await MainActor.run {
            NotificationCenter.default.post(name: TripSync.changed, object: nil)
        }
        return .result()
    }
}
