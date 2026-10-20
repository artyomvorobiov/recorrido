import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Wikipedia article that has coordinates.
struct WikiPage: Hashable, Sendable {
    var pageID: Int
    var title: String
    var coordinate: Coordinate
    /// Short description from Wikidata, e.g. "cathedral in Suzdal".
    var shortDescription: String?
    /// Article size in bytes — a decent hint of how notable the place is.
    var length: Int
    /// Type from the coordinates template: "landmark", "church", "city"…
    var geoType: String?
    /// Position in Wikipedia's own relevance ranking, when the page came
    /// from a search (0 is the most prominent).
    var searchRank: Int?
}

struct WikiSummary: Hashable, Sendable {
    var extract: String
    var thumbnail: URL?
}

enum WikipediaError: Error {
    case badRequest
    case http(Int)
    case api(String)
    /// Wikipedia's search cluster stayed overloaded after several retries.
    case busy
}

/// Minimal client for the MediaWiki Action API. No API key needed.
/// https://www.mediawiki.org/wiki/API:Main_page
struct WikipediaClient {
    static let defaultUserAgent = "Recorrido/1.0 (iOS travel routes; https://github.com/artyomvorobiov/recorrido)"

    var language: String
    var userAgent: String = WikipediaClient.defaultUserAgent
    var session: URLSession = .shared

    init(language: String, userAgent: String = WikipediaClient.defaultUserAgent, session: URLSession = .shared) {
        let cleaned = language.lowercased().filter { $0.isLetter || $0 == "-" }
        self.language = cleaned.isEmpty ? "en" : cleaned
        self.userAgent = userAgent
        self.session = session
    }

    /// Articles with coordinates within `radius` meters (max 10 km).
    func places(around center: Coordinate, radius: Int, limit: Int) async throws -> [WikiPage] {
        let pages = try await queryPages([
            "generator": "geosearch",
            "ggscoord": "\(center.latitude)|\(center.longitude)",
            "ggsradius": String(min(10_000, max(10, radius))),
            "ggslimit": String(min(500, max(1, limit))),
            "prop": "coordinates|description|info",
            "colimit": "max",
            "coprop": "type",
        ])
        return pages.values.compactMap { page in
            guard let id = page.pageid, page.missing != true,
                  let point = page.coordinates?.first else { return nil }
            return WikiPage(
                pageID: id,
                title: page.title,
                coordinate: Coordinate(point.lat, point.lon),
                shortDescription: page.description?.nilIfEmpty,
                length: page.length ?? 0,
                geoType: point.type
            )
        }
    }

    /// The most prominent articles within `radiusKm` of a point, in
    /// Wikipedia's relevance order (incoming links, popularity). Great for
    /// big cities where the nearest articles are not the most interesting.
    func prominentPlaces(near center: Coordinate, radiusKm: Int, limit: Int) async throws -> [WikiPage] {
        let pages = try await queryPages([
            "generator": "search",
            "gsrsearch": "nearcoord:\(max(1, radiusKm))km,\(center.latitude),\(center.longitude)",
            "gsrnamespace": "0",
            "gsrlimit": String(min(500, max(1, limit))),
            "prop": "coordinates|description|info",
            "colimit": "max",
            "coprop": "type",
        ], maxRounds: 1)
        return pages.values.compactMap { page in
            guard let id = page.pageid, page.missing != true,
                  let point = page.coordinates?.first else { return nil }
            return WikiPage(
                pageID: id,
                title: page.title,
                coordinate: Coordinate(point.lat, point.lon),
                shortDescription: page.description?.nilIfEmpty,
                length: page.length ?? 0,
                geoType: point.type,
                searchRank: page.index.map { max(0, $0 - 1) }
            )
        }
    }

    /// Intro text and a picture for each page id.
    func summaries(for pageIDs: [Int], sentences: Int = 4, thumbnailWidth: Int = 800) async throws -> [Int: WikiSummary] {
        var result: [Int: WikiSummary] = [:]
        for batch in pageIDs.chunked(into: 20) {
            let pages = try await queryPages([
                "pageids": batch.map(String.init).joined(separator: "|"),
                "prop": "extracts|pageimages",
                "exintro": "1",
                "explaintext": "1",
                "exsentences": String(sentences),
                "exlimit": "20",
                "piprop": "thumbnail",
                "pithumbsize": String(thumbnailWidth),
                "pilimit": "20",
            ])
            for page in pages.values {
                guard let id = page.pageid else { continue }
                result[id] = WikiSummary(
                    extract: WikiText.clean(page.extract ?? ""),
                    thumbnail: page.thumbnail?.source
                )
            }
        }
        return result
    }

    /// Picture URLs for article titles. Keys are the titles exactly as asked.
    func thumbnails(for titles: [String], width: Int = 800) async throws -> [String: URL] {
        var result: [String: URL] = [:]
        for batch in titles.chunked(into: 40) {
            let response = try await request([
                "titles": batch.joined(separator: "|"),
                "redirects": "1",
                "prop": "pageimages",
                "piprop": "thumbnail",
                "pithumbsize": String(width),
                "pilimit": "50",
            ])
            let query = response.query
            var images: [String: URL] = [:]
            for page in query?.pages ?? [] {
                if let url = page.thumbnail?.source { images[page.title] = url }
            }
            for title in batch {
                if let url = images[WikiText.resolve(title, query: query)] { result[title] = url }
            }
        }
        return result
    }

    /// Intro text and picture for one article title.
    func summary(title: String, sentences: Int = 6) async throws -> WikiSummary? {
        let response = try await request([
            "titles": title,
            "redirects": "1",
            "prop": "extracts|pageimages",
            "exintro": "1",
            "explaintext": "1",
            "exsentences": String(sentences),
            "piprop": "thumbnail",
            "pithumbsize": "800",
        ])
        guard let page = response.query?.pages?.first, page.missing != true else { return nil }
        let text = WikiText.clean(page.extract ?? "")
        guard !text.isEmpty || page.thumbnail != nil else { return nil }
        return WikiSummary(extract: text, thumbnail: page.thumbnail?.source)
    }

    static func articleURL(language: String, title: String) -> URL? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://\(language).m.wikipedia.org/wiki/\(encoded)")
    }

    // MARK: - Transport

    /// Runs a query following `continue` and merges page properties.
    private func queryPages(_ parameters: [String: String], maxRounds: Int = 6) async throws -> [Int: QueryResponse.Page] {
        var pages: [Int: QueryResponse.Page] = [:]
        var continuation: [String: String] = [:]
        for _ in 0..<maxRounds {
            let response = try await request(parameters.merging(continuation) { _, new in new })
            for page in response.query?.pages ?? [] {
                guard let id = page.pageid else { continue }
                if let existing = pages[id] {
                    pages[id] = existing.merged(with: page)
                } else {
                    pages[id] = page
                }
            }
            guard let next = response.continuation, !next.isEmpty else { break }
            continuation = next
        }
        return pages
    }

    private func request(_ parameters: [String: String]) async throws -> QueryResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(language).wikipedia.org"
        components.path = "/w/api.php"
        var all = parameters
        all["action"] = "query"
        all["format"] = "json"
        all["formatversion"] = "2"
        all["utf8"] = "1"
        components.queryItems = all.keys.sorted().map { URLQueryItem(name: $0, value: all[$0]) }
        // "+" is legal in a query but MediaWiki reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw WikipediaError.badRequest }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Geo search is backed by a search cluster that sometimes answers
        // "too busy"; such errors go away after a short pause.
        let attempts = 5
        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 429 || status == 503 {
                guard attempt < attempts else { throw WikipediaError.busy }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                continue
            }
            guard (200..<300).contains(status) else { throw WikipediaError.http(status) }
            let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
            if let error = decoded.error {
                let code = error.code ?? ""
                if code.contains("busy") || code.contains("maxlag") || code.contains("ratelimit") {
                    guard attempt < attempts else { throw WikipediaError.busy }
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    continue
                }
                throw WikipediaError.api(error.info ?? code)
            }
            return decoded
        }
    }
}

/// The parts of an Action API response Recorrido reads (formatversion=2).
struct QueryResponse: Decodable {
    struct Query: Decodable {
        var pages: [Page]?
        var normalized: [TitleMapping]?
        var redirects: [TitleMapping]?
    }

    struct TitleMapping: Decodable {
        var from: String
        var to: String
    }

    struct Page: Decodable {
        var pageid: Int?
        var title: String
        var missing: Bool?
        var description: String?
        var extract: String?
        var length: Int?
        var thumbnail: Thumbnail?
        var coordinates: [PageCoordinate]?
        /// 1-based position in search results (generator=search).
        var index: Int?

        func merged(with other: Page) -> Page {
            var page = self
            page.description = page.description ?? other.description
            page.extract = page.extract ?? other.extract
            page.length = page.length ?? other.length
            page.thumbnail = page.thumbnail ?? other.thumbnail
            page.coordinates = page.coordinates ?? other.coordinates
            page.index = page.index ?? other.index
            return page
        }
    }

    struct Thumbnail: Decodable {
        var source: URL
    }

    struct PageCoordinate: Decodable {
        var lat: Double
        var lon: Double
        var type: String?
    }

    struct APIError: Decodable {
        var code: String?
        var info: String?
    }

    var query: Query?
    var error: APIError?
    /// The `continue` object, values turned into strings.
    var continuation: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case query, error
        case continuation = "continue"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decodeIfPresent(Query.self, forKey: .query)
        error = try? container.decodeIfPresent(APIError.self, forKey: .error)
        if let raw = try? container.decodeIfPresent([String: LooseString].self, forKey: .continuation) {
            continuation = raw.mapValues(\.value)
        }
    }
}

/// Decodes a JSON string, number or bool as text.
struct LooseString: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "1" : "0"
        } else {
            value = ""
        }
    }
}

enum WikiText {
    /// Follows `normalized` and `redirects` to the final page title.
    static func resolve(_ title: String, query: QueryResponse.Query?) -> String {
        var current = title
        if let mapping = query?.normalized?.first(where: { $0.from == current }) { current = mapping.to }
        if let mapping = query?.redirects?.first(where: { $0.from == current }) { current = mapping.to }
        return current
    }

    /// Removes pronunciation guides, stress marks and leftovers of templates
    /// from an article intro so it reads well and sounds right when spoken.
    static func clean(_ text: String) -> String {
        // Stress marks (combining acute accents) in Russian intros.
        var result = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value != 0x301 }))
        result = removeParentheses(in: result) { inner in
            let lowered = inner.lowercased()
            return inner.contains("[") || lowered.contains("мфа") || lowered.contains("ipa")
                || lowered.contains("pronunci") || lowered.contains("pronounced") || lowered.contains("listen")
                || inner.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–")).isEmpty
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: "\n", with: "\n\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops `( … )` groups (including nested ones) for which `shouldRemove` is true.
    private static func removeParentheses(in text: String, where shouldRemove: (String) -> Bool) -> String {
        var output = ""
        var stack: [String] = []
        for character in text {
            if character == "(" {
                stack.append("")
            } else if character == ")", !stack.isEmpty {
                let inner = stack.removeLast()
                let group = shouldRemove(inner) ? "" : "(\(inner))"
                if stack.isEmpty {
                    output += group
                } else {
                    stack[stack.count - 1] += group
                }
            } else if stack.isEmpty {
                output.append(character)
            } else {
                stack[stack.count - 1].append(character)
            }
        }
        for unclosed in stack {
            output += "(" + unclosed
        }
        return output
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
