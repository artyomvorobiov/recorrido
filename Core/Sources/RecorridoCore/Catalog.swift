import Foundation

/// Text in several languages: `{"ru": "…", "en": "…"}` or a plain string.
struct LocalizedText: Hashable, Sendable {
    var values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    /// The text in `language`, falling back to Russian, English, then anything.
    func resolve(_ language: String) -> (text: String, language: String)? {
        for key in [language, "ru", "en", "*"] {
            if let text = values[key]?.nilIfEmpty { return (text, key == "*" ? language : key) }
        }
        if let key = values.keys.sorted().first, let text = values[key]?.nilIfEmpty {
            return (text, key)
        }
        return nil
    }

    func text(_ language: String) -> String {
        resolve(language)?.text ?? ""
    }

    var allTexts: [String] { Array(values.values) }
}

extension LocalizedText: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            values = ["*": text]
        } else {
            values = try container.decode([String: String].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1, let text = values["*"] {
            try container.encode(text)
        } else {
            try container.encode(values)
        }
    }
}

enum CitySize: String, CaseIterable, Sendable {
    /// Up to roughly 150 000 people: one day on foot, maybe a short drive.
    case small
    case medium
    /// Two or three days.
    case large
}

extension CitySize: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CitySize(rawValue: raw) ?? .small
    }
}

struct City: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var region: String?
    var country: String
    var summary: String
    /// How to get there from the nearest big city.
    var gettingThere: String?
    var coordinate: Coordinate
    var emoji: String
    var size: CitySize
    /// Collections the city belongs to, e.g. "golden-ring", "volga".
    var tags: [String]
    var wikiTitle: String?
    var wikiLanguage: String?
    /// Names in every language, for search.
    var searchTerms: [String]
}

/// Routes that ship with the app: one JSON file per city in Shared/Catalog.
struct Catalog: Sendable {
    var language: String
    var cities: [City]
    var routes: [Route]

    static let empty = Catalog(language: "en", cities: [], routes: [])

    /// Curated routes keep a fixed date so they look the same everywhere.
    static let publishedDate = Date(timeIntervalSince1970: 1_767_225_600)

    /// Loads every `city-*.json` file; broken files are skipped and reported.
    static func load(files: [URL], language: String, onError: (URL, Error) -> Void = { _, _ in }) -> Catalog {
        var cities: [City] = []
        var routes: [Route] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let (city, cityRoutes) = try decodeCityFile(Data(contentsOf: url), language: language)
                cities.append(city)
                routes += cityRoutes
            } catch {
                onError(url, error)
            }
        }
        return Catalog(language: language, cities: cities, routes: routes)
    }

    static func decodeCityFile(_ data: Data, language: String) throws -> (City, [Route]) {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        let source = file.city
        let wiki = source.wiki?.resolve(language)
        let city = City(
            id: source.id,
            name: source.name.text(language),
            region: source.region?.text(language).nilIfEmpty,
            country: source.country.text(language),
            summary: source.summary.text(language),
            gettingThere: source.gettingThere?.text(language).nilIfEmpty,
            coordinate: source.coordinate,
            emoji: source.emoji ?? "📍",
            size: source.size ?? .small,
            tags: source.tags ?? [],
            wikiTitle: wiki?.text,
            wikiLanguage: wiki?.language,
            searchTerms: source.name.allTexts
        )
        let routes = file.routes.map { makeRoute($0, city: city, language: language) }
        return (city, routes)
    }

    private static func makeRoute(_ route: CatalogRoute, city: City, language: String) -> Route {
        var days: [RouteDay] = []
        for (index, day) in route.days.enumerated() {
            days.append(RouteDay(
                id: "\(route.id)-day\(index + 1)",
                title: day.title?.text(language).nilIfEmpty,
                stops: day.stops.map { makeStop($0, language: language) }
            ))
        }
        return Route(
            id: route.id,
            title: route.title.text(language),
            summary: route.summary.text(language),
            city: city.name,
            country: city.country,
            cityID: city.id,
            emoji: route.emoji ?? city.emoji,
            source: .curated,
            author: "Recorrido",
            language: route.title.resolve(language)?.language ?? language,
            days: days,
            tags: route.tags ?? [],
            createdAt: publishedDate,
            updatedAt: publishedDate
        )
    }

    private static func makeStop(_ stop: CatalogStop, language: String) -> Stop {
        let wiki = stop.wiki?.resolve(language)
        var arrival: Arrival?
        if let source = stop.arrival {
            arrival = Arrival(mode: source.mode, note: source.note?.text(language).nilIfEmpty)
        }
        return Stop(
            id: stop.id,
            title: stop.title.text(language),
            coordinate: stop.coordinate,
            details: stop.details.text(language),
            tip: stop.tip?.text(language).nilIfEmpty,
            category: stop.category,
            visitMinutes: stop.visit,
            address: stop.address?.text(language).nilIfEmpty,
            wikiTitle: wiki?.text,
            wikiLanguage: wiki?.language,
            arrival: arrival
        )
    }

    func city(id: String?) -> City? {
        guard let id else { return nil }
        return cities.first { $0.id == id }
    }

    func route(id: String?) -> Route? {
        guard let id else { return nil }
        return routes.first { $0.id == id }
    }

    func routes(inCity cityID: String) -> [Route] {
        routes.filter { $0.cityID == cityID }
    }

    /// A different route every day, the same one all day long.
    func routeOfTheDay(for date: Date, calendar: Calendar = .current) -> Route? {
        guard !routes.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return routes[day % routes.count]
    }

    struct SearchResult {
        var cities: [City] = []
        var routes: [Route] = []
        var isEmpty: Bool { cities.isEmpty && routes.isEmpty }
    }

    func search(_ query: String) -> SearchResult {
        let needle = PlaceClassifier.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return SearchResult() }
        func found(_ text: String?) -> Bool {
            guard let text else { return false }
            return PlaceClassifier.normalize(text).contains(needle)
        }
        var result = SearchResult()
        result.cities = cities.filter { city in
            city.searchTerms.contains(where: found) || found(city.name) || found(city.region)
        }
        let cityIDs = Set(result.cities.map(\.id))
        result.routes = routes.filter { route in
            !cityIDs.contains(route.cityID ?? "")
                && (found(route.title) || route.allStops.contains { found($0.title) })
        }
        return result
    }
}

// MARK: - File format

struct CatalogFile: Decodable {
    var city: CatalogCity
    var routes: [CatalogRoute]
}

struct CatalogCity: Decodable {
    var id: String
    var name: LocalizedText
    var region: LocalizedText?
    var country: LocalizedText
    var summary: LocalizedText
    var gettingThere: LocalizedText?
    var coordinate: Coordinate
    var emoji: String?
    var size: CitySize?
    var tags: [String]?
    var wiki: LocalizedText?
}

struct CatalogRoute: Decodable {
    var id: String
    var title: LocalizedText
    var summary: LocalizedText
    var emoji: String?
    var tags: [String]?
    var days: [CatalogDay]
}

struct CatalogDay: Decodable {
    var title: LocalizedText?
    var stops: [CatalogStop]
}

struct CatalogStop: Decodable {
    var id: String
    var title: LocalizedText
    var coordinate: Coordinate
    var category: PlaceCategory
    /// Minutes to spend here; defaults by category.
    var visit: Int?
    var details: LocalizedText
    var tip: LocalizedText?
    var address: LocalizedText?
    var wiki: LocalizedText?
    var arrival: CatalogArrival?
}

struct CatalogArrival: Decodable {
    var mode: TransportMode
    var note: LocalizedText?
}
