import Foundation

/// Settings you may want to change before publishing the app.
enum AppConfig {
    /// A web page that shows shared routes in any browser and offers to open
    /// the app (docs/index.html published with GitHub Pages, see README).
    /// Set to `nil` to share app-only links (`recorrido://…`) instead.
    static let webViewerURL: URL? = URL(string: "https://artyomvorobiov.github.io/recorrido/")

    static let projectURL = URL(string: "https://github.com/artyomvorobiov/recorrido")!

    /// Wikipedia asks API clients to introduce themselves.
    static let wikipediaUserAgent = "Recorrido/1.0 (iOS travel routes; https://github.com/artyomvorobiov/recorrido)"

    /// Big cities used to tell how far a small town is ("190 km from Moscow").
    static let hubs: [(name: String, coordinate: Coordinate)] = [
        (String(localized: "Moscow"), Coordinate(55.7558, 37.6173)),
        (String(localized: "Saint Petersburg"), Coordinate(59.9343, 30.3351)),
        (String(localized: "Kazan"), Coordinate(55.7963, 49.1088)),
        (String(localized: "Yekaterinburg"), Coordinate(56.8389, 60.6057)),
        (String(localized: "Tyumen"), Coordinate(57.1530, 65.5343)),
    ]
}
