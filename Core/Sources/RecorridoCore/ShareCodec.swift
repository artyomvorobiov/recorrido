import Foundation

/// Packs a whole route into a short URL-safe string, so routes can be shared
/// as links and QR codes without any server.
///
/// Payload = base64url( version byte + body ):
/// - version 0: body is UTF-8 JSON of `SharedRoute`;
/// - version 1: body is the same JSON compressed with raw DEFLATE (RFC 1951).
///
/// The format is documented in docs/SHARE_FORMAT.md so other platforms
/// (the web viewer, a future Android app) can read the same links.
enum ShareCodec {
    static let urlScheme = "recorrido"

    /// How much text to keep. Shorter payloads fit into QR codes.
    enum Detail: Int, CaseIterable, Sendable {
        case full, compact, minimal
    }

    enum Failure: Error {
        case invalidPayload
        case unsupportedVersion(UInt8)
    }

    static func payload(for route: Route, detail: Detail = .full) throws -> String {
        let json = try JSONEncoder().encode(SharedRoute(route, detail: detail))
        var bytes = Data()
        if let deflated = deflate(json), deflated.count < json.count {
            bytes.append(1)
            bytes.append(deflated)
        } else {
            bytes.append(0)
            bytes.append(json)
        }
        return Base64URL.encode(bytes)
    }

    static func route(fromPayload payload: String, now: Date = Date()) throws -> Route {
        guard let bytes = Base64URL.decode(payload), let version = bytes.first else {
            throw Failure.invalidPayload
        }
        let body = Data(bytes.dropFirst())
        let json: Data
        switch version {
        case 0:
            json = body
        case 1:
            guard let inflated = inflate(body) else { throw Failure.invalidPayload }
            json = inflated
        default:
            throw Failure.unsupportedVersion(version)
        }
        return try JSONDecoder().decode(SharedRoute.self, from: json).route(now: now)
    }

    /// A link to the route. With a web viewer `base` URL the link opens in any
    /// browser (and offers to open the app); otherwise it is an app link.
    static func link(for route: Route, base: URL?, detail: Detail = .full) throws -> URL {
        let payload = try payload(for: route, detail: detail)
        if let base, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            components.fragment = payload
            if let url = components.url { return url }
        }
        return appLink(payload: payload)
    }

    static func appLink(payload: String) -> URL {
        URL(string: "\(urlScheme)://import#\(payload)")!
    }

    /// Finds a route payload in a shared link: `recorrido://import#…`,
    /// `https://…/#…`, or a `?r=…` query item.
    static func payload(in url: URL) -> String? {
        if let fragment = url.fragment, !fragment.isEmpty {
            let value = fragment.hasPrefix("r=") ? String(fragment.dropFirst(2)) : fragment
            return value.isEmpty ? nil : value
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let value = items.first(where: { $0.name == "r" })?.value, !value.isEmpty {
            return value
        }
        return nil
    }

    // MARK: - Compression

    private static func deflate(_ data: Data) -> Data? {
        #if canImport(Darwin)
        return try? (data as NSData).compressed(using: .zlib) as Data
        #else
        return nil
        #endif
    }

    private static func inflate(_ data: Data) -> Data? {
        #if canImport(Darwin)
        return try? (data as NSData).decompressed(using: .zlib) as Data
        #else
        return nil
        #endif
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: text)
    }
}

/// Compact wire format of a shared route. Short keys keep links small.
struct SharedRoute: Codable {
    var v: Int
    /// Title, summary, city, country, emoji, author, language, origin id.
    var t: String
    var s: String?
    var c: String
    var cc: String?
    var e: String?
    var a: String?
    var l: String?
    var o: String?
    var d: [SharedDay]

    struct SharedDay: Codable {
        var t: String?
        var p: [SharedStop]
    }

    struct SharedStop: Codable {
        /// Name, latitude, longitude.
        var n: String
        var y: Double
        var x: Double
        /// Details, tip, category, visit minutes, address.
        var d: String?
        var tp: String?
        var k: String?
        var m: Int?
        var ad: String?
        /// Wikipedia title and language, image URL.
        var w: String?
        var wl: String?
        var i: String?
        /// Arrival mode and note.
        var am: String?
        var an: String?
    }

    init(_ route: Route, detail: ShareCodec.Detail) {
        v = 1
        t = route.title
        s = detail == .full ? route.summary.nilIfEmpty : nil
        c = route.city
        cc = route.country
        e = route.emoji
        a = route.author
        l = route.language
        o = route.originID ?? (route.source == .curated ? route.id : nil)
        d = route.days.map { day in
            SharedDay(t: day.title, p: day.stops.map { stop in
                let point = stop.coordinate.rounded(toDigits: 5)
                var shared = SharedStop(n: stop.title, y: point.latitude, x: point.longitude)
                shared.k = stop.category == .other ? nil : stop.category.rawValue
                shared.m = stop.visitMinutes == stop.category.defaultVisitMinutes ? nil : stop.visitMinutes
                shared.w = stop.wikiTitle
                shared.wl = stop.wikiLanguage
                if let arrival = stop.arrival, arrival.mode != .walk || arrival.note != nil {
                    shared.am = arrival.mode.rawValue
                }
                switch detail {
                case .full:
                    shared.d = stop.details.nilIfEmpty
                    shared.tp = stop.tip?.nilIfEmpty
                    shared.ad = stop.address?.nilIfEmpty
                    shared.i = stop.imageURL?.absoluteString
                    shared.an = stop.arrival?.note?.nilIfEmpty
                case .compact:
                    shared.d = stop.details.truncated(to: 160).nilIfEmpty
                    shared.an = stop.arrival?.note?.truncated(to: 80).nilIfEmpty
                case .minimal:
                    break
                }
                return shared
            })
        }
    }

    func route(now: Date) -> Route {
        Route(
            title: t,
            summary: s ?? "",
            city: c,
            country: cc,
            emoji: e ?? "🗺️",
            source: .imported,
            author: a,
            language: l,
            days: d.map { day in
                RouteDay(title: day.t, stops: day.p.map { stop in
                    let category = stop.k.flatMap(PlaceCategory.init(rawValue:)) ?? .other
                    var arrival: Arrival?
                    if let mode = stop.am.flatMap(TransportMode.init(rawValue:)) {
                        arrival = Arrival(mode: mode, note: stop.an)
                    } else if let note = stop.an {
                        arrival = Arrival(mode: .walk, note: note)
                    }
                    return Stop(
                        title: stop.n,
                        coordinate: Coordinate(stop.y, stop.x),
                        details: stop.d ?? "",
                        tip: stop.tp,
                        category: category,
                        visitMinutes: stop.m,
                        address: stop.ad,
                        wikiTitle: stop.w,
                        wikiLanguage: stop.wl,
                        imageURL: stop.i.flatMap(URL.init(string:)),
                        arrival: arrival
                    )
                })
            },
            createdAt: now,
            updatedAt: now,
            originID: o
        )
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }

    func truncated(to length: Int) -> String {
        guard count > length else { return self }
        return String(prefix(length - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
