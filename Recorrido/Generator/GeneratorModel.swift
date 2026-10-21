import CoreLocation
import Observation
import SwiftUI

/// State of the "any town" route builder.
@MainActor
@Observable
final class GeneratorModel {
    enum Phase {
        case form
        case working(GeneratorStage)
        case done(Route)
        case failed(String)
    }

    enum LengthChoice: CaseIterable, Hashable {
        case auto, twoHours, halfDay, oneDay, twoDays, threeDays

        var title: String {
            switch self {
            case .auto: String(localized: "Auto")
            case .twoHours: String(localized: "2 hours")
            case .halfDay: String(localized: "Half a day")
            case .oneDay: String(localized: "1 day")
            case .twoDays: String(localized: "2 days")
            case .threeDays: String(localized: "3 days")
            }
        }

        var length: TripLength {
            switch self {
            case .auto: .auto
            case .twoHours: .hours(2)
            case .halfDay: .hours(4)
            case .oneDay: .days(1)
            case .twoDays: .days(2)
            case .threeDays: .days(3)
            }
        }
    }

    enum Interest: CaseIterable, Hashable {
        case history, churches, museums, nature, views, streets

        var title: String {
            switch self {
            case .history: String(localized: "History")
            case .churches: String(localized: "Churches")
            case .museums: String(localized: "Museums")
            case .nature: String(localized: "Parks & nature")
            case .views: String(localized: "Views")
            case .streets: String(localized: "Streets & squares")
            }
        }

        var symbol: String {
            switch self {
            case .history: "building.columns"
            case .churches: "bell"
            case .museums: "photo.artframe"
            case .nature: "leaf"
            case .views: "binoculars"
            case .streets: "signpost.right"
            }
        }

        var categories: Set<PlaceCategory> {
            switch self {
            case .history: [.castle, .palace, .monument, .landmark, .district]
            case .churches: [.church]
            case .museums: [.museum, .theater]
            case .nature: [.park, .nature]
            case .views: [.viewpoint, .bridge]
            case .streets: [.street, .square, .market, .food]
            }
        }
    }

    var phase: Phase = .form
    var townQuery = ""
    private(set) var town: PlaceSearch.Place?
    var length: LengthChoice = .auto
    var mobility: Mobility = .car
    var pace: Pace = .normal
    var interests: Set<Interest> = []
    var startFromHere = false
    var returnToStart = false
    private(set) var isLocating = false

    let search = PlaceSearch(kind: .towns)

    var canGenerate: Bool {
        town != nil || !townQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func prefill(_ launch: GeneratorLaunch) {
        if let name = launch.townName {
            townQuery = name
        }
        if let coordinate = launch.coordinate {
            town = PlaceSearch.Place(name: launch.townName ?? "", coordinate: coordinate, locality: launch.townName,
                                     country: nil, address: nil, category: .other)
        }
    }

    func queryChanged() {
        if town?.name != townQuery { town = nil }
        search.update(query: townQuery)
    }

    func choose(_ suggestion: PlaceSearch.Suggestion) async {
        townQuery = suggestion.title
        search.update(query: "")
        if let place = await search.resolve(suggestion) {
            town = place
            townQuery = place.locality ?? place.name
        }
    }

    func useCurrentLocation(_ location: LocationService) async {
        isLocating = true
        defer { isLocating = false }
        guard let here = await location.currentLocation() else { return }
        let coordinate = Coordinate(here.coordinate)
        if let place = await PlaceSearch.town(at: coordinate) {
            town = place
            townQuery = place.name
        } else {
            town = PlaceSearch.Place(name: String(localized: "Around me"), coordinate: coordinate, locality: nil,
                                     country: nil, address: nil, category: .other)
            townQuery = town?.name ?? ""
        }
        search.update(query: "")
    }

    func generate(location: LocationService) async {
        phase = .working(.searching)
        var place = town
        if place == nil {
            place = await search.resolve(text: townQuery)
        }
        guard let place else {
            phase = .failed(String(localized: "Can't find this town. Check the name or pick it from the list."))
            return
        }
        town = place

        var start: Coordinate?
        if startFromHere, let here = await location.currentLocation() {
            start = Coordinate(here.coordinate)
        }

        let language = ContentLanguage.current
        let request = GeneratorRequest(
            cityName: place.locality ?? place.name,
            center: place.coordinate,
            start: start,
            startTitle: String(localized: "Start"),
            returnToStart: returnToStart && start != nil,
            length: length.length,
            pace: pace,
            mobility: mobility,
            interests: interests.reduce(into: Set<PlaceCategory>()) { $0.formUnion($1.categories) },
            language: language
        )
        let generator = CityRouteGenerator(client: WikipediaClient(language: language, userAgent: AppConfig.wikipediaUserAgent))
        do {
            let plan = try await generator.generate(request) { stage in
                Task { @MainActor in
                    if case .working = self.phase { self.phase = .working(stage) }
                }
            }
            phase = .done(makeRoute(from: plan, place: place))
        } catch GeneratorError.nothingFound {
            phase = .failed(String(localized: "No sights found around this place. Try a longer trip or a different town."))
        } catch WikipediaError.busy {
            phase = .failed(String(localized: "Wikipedia is busy right now. Try again in a minute."))
        } catch {
            phase = .failed(String(localized: "Couldn't reach Wikipedia. Check the internet connection and try again."))
        }
    }

    private func makeRoute(from plan: GeneratedPlan, place: PlaceSearch.Place) -> Route {
        let town = place.locality ?? place.name
        let title: String
        switch plan.length {
        case .hours(let hours) where hours <= 2:
            title = String(localized: "\(town): a short walk")
        case .hours:
            title = String(localized: "\(town) in half a day")
        case .days(let days) where days > 1:
            title = String(localized: "\(town) in \(days) days")
        default:
            title = String(localized: "\(town) in a day")
        }
        let stops = plan.days.flatMap(\.stops).filter { $0.visitMinutes > 0 }
        let summary = String(localized: "Built automatically from \(stops.count) notable places on Wikipedia. Check opening hours before you go.")
        let emoji: String
        switch stops.first?.category ?? .other {
        case .church: emoji = "⛪"
        case .castle: emoji = "🏰"
        case .museum: emoji = "🏛️"
        case .park, .nature: emoji = "🌳"
        case .viewpoint: emoji = "🔭"
        default: emoji = plan.isSmallTown ? "🏡" : "🏙️"
        }
        return Route(
            title: title,
            summary: summary,
            city: town,
            country: place.country,
            emoji: emoji,
            source: .generated,
            author: nil,
            language: plan.language,
            days: plan.days
        )
    }
}
