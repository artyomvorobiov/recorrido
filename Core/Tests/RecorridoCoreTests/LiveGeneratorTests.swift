import XCTest
@testable import RecorridoCore

/// Builds real routes from Wikipedia. Skipped unless RECORRIDO_LIVE=1, so the
/// regular test run never needs the network:
///
///     RECORRIDO_LIVE=1 swift test --package-path Core --filter LiveGeneratorTests
final class LiveGeneratorTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RECORRIDO_LIVE"] == "1",
                          "set RECORRIDO_LIVE=1 to call Wikipedia")
    }

    private func run(_ name: String, _ center: Coordinate, language: String,
                     length: TripLength = .auto, mobility: Mobility = .car) async throws -> GeneratedPlan {
        let generator = CityRouteGenerator(client: WikipediaClient(language: language))
        let request = GeneratorRequest(cityName: name, center: center, length: length, mobility: mobility, language: language)
        let plan = try await generator.generate(request)
        print(describe(plan, name: name))
        return plan
    }

    func testSmallRussianTowns() async throws {
        let towns: [(String, Coordinate)] = [
            ("Суздаль", Coordinate(56.4196, 40.4492)),
            ("Переславль-Залесский", Coordinate(56.7360, 38.8543)),
            ("Коломна", Coordinate(55.1025, 38.7531)),
            ("Мышкин", Coordinate(57.7880, 38.4547)),
            ("Плёс", Coordinate(57.4606, 41.5130)),
            ("Боровск", Coordinate(55.2069, 36.4876)),
        ]
        var built = 0
        for (name, center) in towns {
            do {
                let plan = try await run(name, center, language: "ru")
                XCTAssertTrue(plan.isSmallTown, name)
                XCTAssertFalse(plan.days.isEmpty, name)
                XCTAssertGreaterThanOrEqual(plan.days[0].stops.count, 3, name)
                built += 1
            } catch WikipediaError.busy {
                // Shared CI addresses hit Wikipedia's search limits now and then.
                print("Wikipedia busy, skipped \(name)")
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        XCTAssertGreaterThan(built, 0)
    }

    func testBigCities() async throws {
        let moscow = try await run("Москва", Coordinate(55.7539, 37.6208), language: "ru", length: .days(2), mobility: .transit)
        XCTAssertFalse(moscow.isSmallTown)
        XCTAssertEqual(moscow.days.count, 2)
        let paris = try await run("Paris", Coordinate(48.8566, 2.3522), language: "en", length: .days(1), mobility: .transit)
        XCTAssertEqual(paris.days.count, 1)
    }

    private func describe(_ plan: GeneratedPlan, name: String) -> String {
        var lines = ["", "=== \(name): \(plan.length), small town: \(plan.isSmallTown), candidates: \(plan.candidateCount)"]
        for (index, day) in plan.days.enumerated() {
            let estimate = RouteEstimator.day(day)
            lines.append("  Day \(index + 1): \(Int(estimate.totalMinutes)) min, \(Int(estimate.distance)) m")
            for stop in day.stops {
                let mode = stop.arrival.map { "[\($0.mode.rawValue)] " } ?? ""
                let text = stop.details.replacingOccurrences(of: "\n", with: " ").prefix(90)
                lines.append("    \(mode)\(stop.title) · \(stop.category.rawValue) · \(stop.visitMinutes) min · photo: \(stop.imageURL != nil) — \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
