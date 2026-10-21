import CoreLocation
import Observation

/// The traveller's position and heading. Location keeps flowing in the
/// background during a walk (when allowed) so arrivals are noticed with the
/// phone in a pocket.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    /// Degrees clockwise from true north, when the compass is available.
    private(set) var heading: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored var onUpdate: ((CLLocation) -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var isTracking = false
    @ObservationIgnored private var oneShotContinuations: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start(background: Bool) {
        requestPermission()
        isTracking = true
        let canRunInBackground = background && Self.hasBackgroundLocationMode
        manager.allowsBackgroundLocationUpdates = canRunInBackground
        manager.showsBackgroundLocationIndicator = canRunInBackground
        manager.pausesLocationUpdatesAutomatically = !canRunInBackground
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        isTracking = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// A single fresh position, e.g. to plan a route from where the user is.
    func currentLocation() async -> CLLocation? {
        if let location, location.timestamp.timeIntervalSinceNow > -60 { return location }
        requestPermission()
        if isDenied { return nil }
        return await withCheckedContinuation { continuation in
            oneShotContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    private static var hasBackgroundLocationMode: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }

    private func finishOneShots(with location: CLLocation?) {
        let waiting = oneShotContinuations
        oneShotContinuations.removeAll()
        for continuation in waiting { continuation.resume(returning: location) }
    }

    // MARK: - CLLocationManagerDelegate (called on the main thread)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isTracking && self.isAuthorized {
                self.manager.startUpdatingLocation()
            }
            if status == .denied || status == .restricted {
                self.finishOneShots(with: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            self.finishOneShots(with: last)
            self.onUpdate?(last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = value
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finishOneShots(with: nil)
        }
    }
}
