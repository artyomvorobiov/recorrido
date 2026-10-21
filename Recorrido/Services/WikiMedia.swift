import Foundation
import Observation

/// Photos for stops, taken from the Wikipedia articles they link to.
@MainActor
@Observable
final class WikiMedia {
    private var images: [String: URL] = [:]
    @ObservationIgnored private var requested = Set<String>()

    func imageURL(for stop: Stop) -> URL? {
        if let url = stop.imageURL { return url }
        guard let key = Self.key(stop) else { return nil }
        return images[key]
    }

    /// Loads pictures for the stops that link to Wikipedia (once per title).
    func prefetch(_ stops: [Stop]) async {
        var byLanguage: [String: [String]] = [:]
        for stop in stops where stop.imageURL == nil {
            guard let key = Self.key(stop), let title = stop.wikiTitle, let language = stop.wikiLanguage,
                  !requested.contains(key) else { continue }
            requested.insert(key)
            byLanguage[language, default: []].append(title)
        }
        for (language, titles) in byLanguage {
            let client = WikipediaClient(language: language, userAgent: AppConfig.wikipediaUserAgent)
            guard let found = try? await client.thumbnails(for: titles) else {
                // Try again next time (probably offline).
                for title in titles { requested.remove("\(language):\(title)") }
                continue
            }
            for (title, url) in found {
                images["\(language):\(title)"] = url
            }
        }
    }

    private static func key(_ stop: Stop) -> String? {
        guard let title = stop.wikiTitle, let language = stop.wikiLanguage else { return nil }
        return "\(language):\(title)"
    }
}
