import MapKit
import Observation

/// Type-ahead search for towns or places, backed by Apple Maps.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    enum Kind {
        case towns, places
    }

    struct Suggestion: Identifiable, Hashable {
        let id: Int
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion

        static func == (lhs: Suggestion, rhs: Suggestion) -> Bool { lhs.id == rhs.id && lhs.title == rhs.title }
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(title)
        }
    }

    /// A resolved place.
    struct Place: Hashable {
        var name: String
        var coordinate: Coordinate
        var locality: String?
        var country: String?
        var address: String?
        var category: PlaceCategory
    }

    private(set) var suggestions: [Suggestion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    init(kind: Kind) {
        super.init()
        completer.delegate = self
        switch kind {
        case .towns:
            completer.resultTypes = .address
            completer.pointOfInterestFilter = .excludingAll
        case .places:
            completer.resultTypes = [.pointOfInterest, .address]
        }
    }

    func setRegion(around coordinate: Coordinate, radius: Double = 20_000) {
        completer.region = MKCoordinateRegion(center: coordinate.cl, latitudinalMeters: radius, longitudinalMeters: radius)
    }

    func update(query: String) {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = query
        }
    }

    func resolve(_ suggestion: Suggestion) async -> Place? {
        await resolve(request: MKLocalSearch.Request(completion: suggestion.completion))
    }

    /// Resolves free text, e.g. a town name typed without picking a suggestion.
    func resolve(text: String) async -> Place? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        return await resolve(request: request)
    }

    private func resolve(request: MKLocalSearch.Request) async -> Place? {
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        return Self.place(from: item)
    }

    static func place(from item: MKMapItem) -> Place {
        let placemark = item.placemark
        return Place(
            name: item.name ?? placemark.locality ?? "",
            coordinate: Coordinate(placemark.coordinate),
            locality: placemark.locality,
            country: placemark.country,
            address: placemark.title,
            category: category(for: item.pointOfInterestCategory)
        )
    }

    /// Name of the town at a coordinate (for "plan from where I am").
    static func town(at coordinate: Coordinate) async -> Place? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return Place(
            name: placemark.locality ?? placemark.name ?? "",
            coordinate: coordinate,
            locality: placemark.locality,
            country: placemark.country,
            address: placemark.name,
            category: .other
        )
    }

    static func category(for poi: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let poi else { return .other }
        switch poi {
        case .museum: return .museum
        case .park, .nationalPark, .beach: return .park
        case .theater, .movieTheater: return .theater
        case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife: return .food
        case .stadium, .amusementPark, .aquarium, .zoo, .library, .university: return .landmark
        case .marina: return .nature
        case .store: return .market
        default: return .other
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.prefix(8).enumerated().map { index, completion in
            Suggestion(id: index, title: completion.title, subtitle: completion.subtitle, completion: completion)
        }
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}
