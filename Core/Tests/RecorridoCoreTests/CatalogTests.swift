import XCTest
@testable import RecorridoCore

/// Checks the curated routes in Shared/Catalog: every file decodes, ids are
/// unique, texts exist in Russian and English, and the routes make sense
/// on the map.
final class CatalogTests: XCTestCase {
    /// Every stop, route and city must have a guide, not just a description.
    private let guidesRequired = false

    private var catalogDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RecorridoCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Core
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Shared/Catalog")
    }

    private func cityFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: catalogDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("city-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testEveryFileLoadsInBothLanguages() throws {
        let files = try cityFiles()
        XCTAssertGreaterThanOrEqual(files.count, 10, "expected the catalog in \(catalogDirectory.path)")
        for language in ["ru", "en"] {
            var errors: [String] = []
            let catalog = Catalog.load(files: files, language: language) { url, error in
                errors.append("\(url.lastPathComponent): \(error)")
            }
            XCTAssertEqual(errors, [], "language \(language)")
            XCTAssertEqual(catalog.cities.count, files.count)
            XCTAssertFalse(catalog.routes.isEmpty)
            XCTAssertNotNil(catalog.routeOfTheDay(for: Date()))
        }
    }

    func testContentIsCompleteAndConsistent() throws {
        var problems: [String] = []
        var routeIDs = Set<String>()
        var stopIDs = Set<String>()
        var cityIDs = Set<String>()

        func requireBoth(_ text: LocalizedText?, _ what: String, minLength: Int = 1) {
            for language in ["ru", "en"] {
                let value = text?.values[language]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if value.count < minLength {
                    problems.append("\(what): missing or too short \(language) text")
                }
            }
        }

        /// Both languages, the same number of items, none empty.
        func requireBothLists(_ list: LocalizedList?, _ what: String, minCount: Int = 1) {
            let ru = list?.values["ru"] ?? []
            let en = list?.values["en"] ?? []
            if ru.count < minCount || en.count < minCount {
                problems.append("\(what): needs at least \(minCount) item(s) in both languages")
            } else if ru.count != en.count {
                problems.append("\(what): \(ru.count) Russian items but \(en.count) English")
            }
            if (ru + en).contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                problems.append("\(what): empty item")
            }
        }

        func checkGuide(_ guide: CatalogStopGuide?, _ label: String) -> Int {
            guard let guide else {
                if guidesRequired { problems.append("\(label): no guide") }
                return 0
            }
            requireBoth(guide.story, "\(label) story", minLength: 250)
            requireBothLists(guide.lookFor, "\(label) look for", minCount: guidesRequired ? 2 : 1)
            if guide.facts != nil || guidesRequired { requireBothLists(guide.facts, "\(label) facts") }
            if guide.legend != nil { requireBoth(guide.legend, "\(label) legend", minLength: 60) }
            if guide.approach != nil { requireBoth(guide.approach, "\(label) approach", minLength: 30) }
            guard let quiz = guide.quiz else { return 0 }
            requireBoth(quiz.question, "\(label) quiz question")
            requireBoth(quiz.explanation, "\(label) quiz explanation", minLength: 20)
            requireBothLists(quiz.options, "\(label) quiz options", minCount: 3)
            if !(0..<(quiz.options.values["ru"]?.count ?? 0)).contains(quiz.answer) {
                problems.append("\(label): quiz answer out of range")
            }
            return 1
        }

        for url in try cityFiles() {
            let file = try JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: url))
            let city = file.city
            let name = url.lastPathComponent
            if !cityIDs.insert(city.id).inserted { problems.append("\(name): duplicate city id \(city.id)") }
            if name != "city-\(city.id).json" { problems.append("\(name): file name should be city-\(city.id).json") }
            requireBoth(city.name, "\(city.id) name")
            requireBoth(city.summary, "\(city.id) summary", minLength: 60)
            requireBoth(city.gettingThere, "\(city.id) getting there", minLength: 40)
            requireBoth(city.region, "\(city.id) region")
            if !city.coordinate.isValid { problems.append("\(city.id): bad coordinate") }
            if let guide = city.guide {
                requireBoth(guide.story, "\(city.id) guide story", minLength: 400)
                if (guide.history ?? []).count < 3 { problems.append("\(city.id): fewer than 3 history moments") }
                for moment in guide.history ?? [] {
                    if moment.year.text("ru").isEmpty { problems.append("\(city.id): history moment without a year") }
                    requireBoth(moment.text, "\(city.id) history \(moment.year.text("ru"))", minLength: 20)
                }
                requireBothLists(guide.taste, "\(city.id) taste")
                requireBothLists(guide.souvenirs, "\(city.id) souvenirs")
                requireBothLists(guide.tips, "\(city.id) tips")
            } else if guidesRequired {
                problems.append("\(city.id): no city guide")
            }
            if file.routes.isEmpty { problems.append("\(city.id): no routes") }

            for route in file.routes {
                if !routeIDs.insert(route.id).inserted { problems.append("duplicate route id \(route.id)") }
                if !route.id.hasPrefix(city.id) { problems.append("\(route.id): route id should start with \(city.id)") }
                requireBoth(route.title, "\(route.id) title")
                requireBoth(route.summary, "\(route.id) summary", minLength: 40)
                if route.intro != nil || guidesRequired { requireBoth(route.intro, "\(route.id) intro", minLength: 60) }
                if route.days.isEmpty { problems.append("\(route.id): no days") }
                var quizzes = 0

                for (dayIndex, day) in route.days.enumerated() {
                    if day.stops.count < 3 { problems.append("\(route.id) day \(dayIndex + 1): fewer than 3 stops") }
                    var previous: CatalogStop?
                    for stop in day.stops {
                        let label = "\(route.id)/\(stop.id)"
                        if !stopIDs.insert(stop.id).inserted { problems.append("duplicate stop id \(stop.id)") }
                        requireBoth(stop.title, "\(label) title")
                        requireBoth(stop.details, "\(label) details", minLength: 60)
                        quizzes += checkGuide(stop.guide, label)
                        if !stop.coordinate.isValid { problems.append("\(label): bad coordinate") }
                        let fromCenter = Geo.distance(city.coordinate, stop.coordinate)
                        if fromCenter > 80_000 { problems.append("\(label): \(Int(fromCenter / 1000)) km from the city") }
                        if let visit = stop.visit, !(0...300).contains(visit) { problems.append("\(label): odd visit time") }
                        if let previous {
                            let hop = Geo.distance(previous.coordinate, stop.coordinate)
                            let mode = stop.arrival?.mode ?? .walk
                            if mode == .walk && hop > 4500 {
                                problems.append("\(label): \(Int(hop)) m on foot from \(previous.id); set a transport mode")
                            }
                        } else if stop.arrival != nil && dayIndex == 0 {
                            problems.append("\(label): the first stop of a route needs no arrival")
                        }
                        previous = stop
                    }
                }
                if guidesRequired && quizzes < route.days.count {
                    problems.append("\(route.id): needs at least one quiz a day")
                }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testSearchFindsCitiesInAnyLanguage() throws {
        let catalog = Catalog.load(files: try cityFiles(), language: "ru")
        XCTAssertFalse(catalog.search("суздаль").cities.isEmpty)
        XCTAssertFalse(catalog.search("Suzdal").cities.isEmpty)
        XCTAssertTrue(catalog.search("   ").isEmpty)
    }
}
