import Foundation

/// How a traveller gets from one stop to the next.
enum TransportMode: String, CaseIterable, Sendable {
    case walk, bike, metro, tram, bus, train, ferry, funicular, cableCar, transit, car

    /// Average speed used for estimates, km/h.
    var speedKmh: Double {
        switch self {
        case .walk: 4.5
        case .bike: 14
        case .metro: 28
        case .tram: 14
        case .bus: 16
        case .train: 45
        case .ferry: 18
        case .funicular: 8
        case .cableCar: 12
        case .transit: 20
        case .car: 32
        }
    }

    /// Fixed overhead in minutes: waiting, tickets, parking.
    var overheadMinutes: Double {
        switch self {
        case .walk: 0
        case .bike: 3
        case .metro, .tram, .bus, .transit: 7
        case .train: 12
        case .ferry: 10
        case .funicular, .cableCar: 8
        case .car: 6
        }
    }

    /// Real paths are longer than straight lines.
    var detourFactor: Double {
        switch self {
        case .walk, .bike: 1.3
        case .car: 1.4
        case .metro, .tram, .bus, .transit, .train: 1.25
        case .ferry, .funicular, .cableCar: 1.1
        }
    }

    var isPublicTransport: Bool {
        switch self {
        case .walk, .bike, .car: false
        default: true
        }
    }
}

extension TransportMode: Codable {
    /// Unknown values (e.g. from a newer app version) fall back to walking.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransportMode(rawValue: raw) ?? .walk
    }
}

/// What kind of place a stop is. Drives icons, colors and visit-time estimates.
enum PlaceCategory: String, CaseIterable, Sendable {
    case landmark, museum, church, palace, castle, park, viewpoint, square, street,
         bridge, monument, market, theater, district, nature, food, other

    /// Typical time spent at such a place, minutes.
    var defaultVisitMinutes: Int {
        switch self {
        case .museum: 90
        case .palace, .castle: 75
        case .park, .nature: 45
        case .food: 45
        case .market, .district: 40
        case .church: 25
        case .street: 25
        case .landmark, .theater: 20
        case .viewpoint, .square: 15
        case .bridge, .monument: 10
        case .other: 20
        }
    }
}

extension PlaceCategory: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlaceCategory(rawValue: raw) ?? .other
    }
}

/// How to reach a stop from the previous one.
struct Arrival: Codable, Hashable, Sendable {
    var mode: TransportMode
    var note: String?

    init(mode: TransportMode, note: String? = nil) {
        self.mode = mode
        self.note = note
    }
}

struct Stop: Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var coordinate: Coordinate
    /// A short description: two or three sentences for lists and the map.
    var details: String
    /// A practical local tip.
    var tip: String?
    var category: PlaceCategory
    /// Suggested time to spend here, minutes.
    var visitMinutes: Int
    var address: String?
    /// Wikipedia article used for the photo and "read more".
    var wikiTitle: String?
    var wikiLanguage: String?
    var imageURL: URL?
    /// How to get here from the previous stop of the day. `nil` means walking.
    var arrival: Arrival?
    /// The long story, things to find, facts and a quiz.
    var guide: StopGuide?
    /// Id of the catalog stop this one comes from; survives copies and links,
    /// so the guide can be found again.
    var ref: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        coordinate: Coordinate,
        details: String = "",
        tip: String? = nil,
        category: PlaceCategory = .other,
        visitMinutes: Int? = nil,
        address: String? = nil,
        wikiTitle: String? = nil,
        wikiLanguage: String? = nil,
        imageURL: URL? = nil,
        arrival: Arrival? = nil,
        guide: StopGuide? = nil,
        ref: String? = nil
    ) {
        self.id = id
        self.title = title
        self.coordinate = coordinate
        self.details = details
        self.tip = tip
        self.category = category
        self.visitMinutes = visitMinutes ?? category.defaultVisitMinutes
        self.address = address
        self.wikiTitle = wikiTitle
        self.wikiLanguage = wikiLanguage
        self.imageURL = imageURL
        self.arrival = arrival
        self.guide = guide?.isEmpty == true ? nil : guide
        self.ref = ref
    }

    var arrivalMode: TransportMode { arrival?.mode ?? .walk }

    /// Key for what the traveller found and answered here: the same for a
    /// catalog stop and for any copy of it.
    var guideKey: String { ref ?? id }

    /// The story to tell: the guide's when there is one, else the short description.
    var fullStory: String { guide?.story.nilIfEmpty ?? details }
}

extension Stop: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, coordinate, details, tip, category, visitMinutes, address,
             wikiTitle, wikiLanguage, imageURL, arrival, guide, ref
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let category = try container.decodeIfPresent(PlaceCategory.self, forKey: .category) ?? .other
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            title: try container.decode(String.self, forKey: .title),
            coordinate: try container.decode(Coordinate.self, forKey: .coordinate),
            details: try container.decodeIfPresent(String.self, forKey: .details) ?? "",
            tip: try container.decodeIfPresent(String.self, forKey: .tip),
            category: category,
            visitMinutes: try container.decodeIfPresent(Int.self, forKey: .visitMinutes),
            address: try container.decodeIfPresent(String.self, forKey: .address),
            wikiTitle: try container.decodeIfPresent(String.self, forKey: .wikiTitle),
            wikiLanguage: try container.decodeIfPresent(String.self, forKey: .wikiLanguage),
            imageURL: try? container.decodeIfPresent(URL.self, forKey: .imageURL),
            arrival: try container.decodeIfPresent(Arrival.self, forKey: .arrival),
            guide: try? container.decodeIfPresent(StopGuide.self, forKey: .guide),
            ref: try container.decodeIfPresent(String.self, forKey: .ref)
        )
    }
}

struct RouteDay: Hashable, Identifiable, Sendable {
    var id: String
    /// Optional theme of the day, e.g. "Old town". The UI falls back to "Day N".
    var title: String?
    var stops: [Stop]

    init(id: String = UUID().uuidString, title: String? = nil, stops: [Stop] = []) {
        self.id = id
        self.title = title
        self.stops = stops
    }
}

extension RouteDay: Codable {
    private enum CodingKeys: String, CodingKey { case id, title, stops }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            title: try container.decodeIfPresent(String.self, forKey: .title),
            stops: try container.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        )
    }
}

enum RouteSource: String, Sendable {
    /// Ships with the app.
    case curated
    /// Built by the any-city generator.
    case generated
    /// Made by hand in the editor.
    case user
    /// Received from someone else via link, file or QR code.
    case imported
}

extension RouteSource: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RouteSource(rawValue: raw) ?? .user
    }
}

struct Route: Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String
    var city: String
    var country: String?
    /// Id of the catalog city, when the route belongs to one.
    var cityID: String?
    var emoji: String
    var source: RouteSource
    var author: String?
    /// Language of the texts, used to pick the audio guide voice.
    var language: String?
    var days: [RouteDay]
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    /// The route this one was copied from (customized catalog route, import).
    var originID: String?
    /// What to know before setting off: where to start, the best time, the idea of the walk.
    var intro: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        city: String,
        country: String? = nil,
        cityID: String? = nil,
        emoji: String = "🗺️",
        source: RouteSource = .user,
        author: String? = nil,
        language: String? = nil,
        days: [RouteDay] = [RouteDay()],
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        originID: String? = nil,
        intro: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.city = city
        self.country = country
        self.cityID = cityID
        self.emoji = emoji
        self.source = source
        self.author = author
        self.language = language
        self.days = days
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originID = originID
        self.intro = intro
    }

    var allStops: [Stop] { days.flatMap(\.stops) }
    var stopCount: Int { days.reduce(0) { $0 + $1.stops.count } }
    var isMultiDay: Bool { days.count > 1 }
    var isEmpty: Bool { stopCount == 0 }
    var center: Coordinate? { Geo.centroid(of: allStops.map(\.coordinate)) }

    /// Distinct ways of moving around used in the route, walking first.
    var modes: [TransportMode] {
        var result: [TransportMode] = []
        for day in days {
            for stop in day.stops.dropFirst() where !result.contains(stop.arrivalMode) {
                result.append(stop.arrivalMode)
            }
        }
        if result.isEmpty, stopCount > 0 { result = [.walk] }
        if let walk = result.firstIndex(of: .walk), walk > 0 {
            result.remove(at: walk)
            result.insert(.walk, at: 0)
        }
        return result
    }

    func stop(withID id: String) -> Stop? {
        for day in days {
            if let stop = day.stops.first(where: { $0.id == id }) { return stop }
        }
        return nil
    }

    /// An editable copy owned by the user.
    func userCopy(now: Date = Date()) -> Route {
        var copy = self
        copy.id = UUID().uuidString
        copy.source = .user
        copy.originID = originID ?? id
        copy.createdAt = now
        copy.updatedAt = now
        copy.days = days.map { day in
            var day = day
            day.id = UUID().uuidString
            day.stops = day.stops.map { stop in
                var stop = stop
                if stop.ref == nil, source == .curated { stop.ref = stop.id }
                stop.id = UUID().uuidString
                return stop
            }
            return day
        }
        return copy
    }
}

extension Route: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, summary, city, country, cityID, emoji, source, author, language,
             days, tags, createdAt, updatedAt, originID, intro
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            title: try container.decode(String.self, forKey: .title),
            summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
            city: try container.decodeIfPresent(String.self, forKey: .city) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country),
            cityID: try container.decodeIfPresent(String.self, forKey: .cityID),
            emoji: try container.decodeIfPresent(String.self, forKey: .emoji) ?? "🗺️",
            source: try container.decodeIfPresent(RouteSource.self, forKey: .source) ?? .user,
            author: try container.decodeIfPresent(String.self, forKey: .author),
            language: try container.decodeIfPresent(String.self, forKey: .language),
            days: try container.decodeIfPresent([RouteDay].self, forKey: .days) ?? [RouteDay()],
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now,
            originID: try container.decodeIfPresent(String.self, forKey: .originID),
            intro: try container.decodeIfPresent(String.self, forKey: .intro)
        )
    }
}

/// JSON coders with the date format used for everything Recorrido stores.
enum JSONCoders {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
