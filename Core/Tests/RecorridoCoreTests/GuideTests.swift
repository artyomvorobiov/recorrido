import XCTest
@testable import RecorridoCore

final class GuideTests: XCTestCase {
    private let sample = """
    {
      "city": {
        "id": "plyos", "name": {"ru": "Плёс", "en": "Plyos"}, "country": {"ru": "Россия", "en": "Russia"},
        "summary": {"ru": "Городок на Волге", "en": "A town on the Volga"},
        "coordinate": [57.4606, 41.513],
        "guide": {
          "story": {"ru": "Абзац один.\\n\\nАбзац два.", "en": "Paragraph one.\\n\\nParagraph two."},
          "history": [{"year": "1410", "text": {"ru": "Крепость", "en": "A fortress"}}],
          "taste": {"ru": ["Уха"], "en": ["Fish soup"]},
          "tips": ["Wear good shoes"]
        }
      },
      "routes": [{
        "id": "plyos-day", "title": {"ru": "Плёс", "en": "Plyos"}, "summary": {"ru": "Прогулка", "en": "A walk"},
        "intro": {"ru": "Начните с горы", "en": "Start on the hill"},
        "days": [{"stops": [
          {
            "id": "plyos-hill", "title": {"ru": "Соборная гора", "en": "Cathedral Hill"},
            "coordinate": [57.4583, 41.5156], "category": "viewpoint",
            "details": {"ru": "Вид на Волгу", "en": "A view of the Volga"},
            "guide": {
              "story": {"ru": "Здесь стояла крепость.", "en": "A fortress stood here."},
              "lookFor": {"ru": ["Беседку", "Пристань"], "en": ["The gazebo", "The pier"]},
              "facts": {"ru": ["Факт"]},
              "quiz": {
                "question": {"ru": "Что здесь стояло?"},
                "options": {"ru": ["Крепость", "Мельница"], "en": ["A fortress", "A mill"]},
                "answer": 0,
                "explanation": {"ru": "Деревянная крепость", "en": "A wooden fortress"}
              },
              "approach": {"ru": "Поднимитесь по лестнице", "en": "Climb the stairs"}
            }
          },
          {
            "id": "plyos-levitan", "title": {"ru": "Дом Левитана", "en": "Levitan House"},
            "coordinate": [57.4581, 41.5065], "category": "museum",
            "details": {"ru": "Музей", "en": "A museum"}
          }
        ]}]
      }]
    }
    """

    private func catalog(_ language: String) throws -> (City, [Route], Catalog) {
        let (city, routes) = try Catalog.decodeCityFile(Data(sample.utf8), language: language)
        return (city, routes, Catalog(language: language, cities: [city], routes: routes))
    }

    func testCatalogGuidesResolveLanguages() throws {
        let (cityRU, routesRU, _) = try catalog("ru")
        let (cityEN, routesEN, _) = try catalog("en")

        XCTAssertEqual(cityRU.guide?.paragraphs, ["Абзац один.", "Абзац два."])
        XCTAssertEqual(cityEN.guide?.history.first?.year, "1410")
        XCTAssertEqual(cityEN.guide?.history.first?.text, "A fortress")
        XCTAssertEqual(cityEN.guide?.taste, ["Fish soup"])
        XCTAssertEqual(cityRU.guide?.tips, ["Wear good shoes"])
        XCTAssertEqual(routesEN[0].intro, "Start on the hill")

        let hillRU = routesRU[0].days[0].stops[0]
        let hillEN = routesEN[0].days[0].stops[0]
        XCTAssertEqual(hillRU.ref, "plyos-hill")
        XCTAssertEqual(hillEN.guide?.lookFor, ["The gazebo", "The pier"])
        XCTAssertEqual(hillEN.guide?.facts, ["Факт"], "a missing language falls back to Russian")
        XCTAssertEqual(hillEN.guide?.approach, "Climb the stairs")
        // The quiz exists only in Russian, so its options are Russian too.
        XCTAssertEqual(hillEN.guide?.quiz?.question, "Что здесь стояло?")
        XCTAssertEqual(hillEN.guide?.quiz?.options, ["Крепость", "Мельница"])
        XCTAssertEqual(hillEN.guide?.quiz?.explanation, "Деревянная крепость")
        XCTAssertEqual(hillEN.fullStory, "A fortress stood here.")

        let levitan = routesRU[0].days[0].stops[1]
        XCTAssertNil(levitan.guide)
        XCTAssertEqual(levitan.fullStory, "Музей")
    }

    func testEnrichBringsGuidesBack() throws {
        let (_, routes, catalog) = try catalog("ru")
        var received = routes[0]
        received.intro = nil
        received.originID = routes[0].id
        received.days[0].stops = received.days[0].stops.map { stop in
            var stop = stop
            stop.guide = nil
            stop.id = UUID().uuidString
            return stop
        }
        // An old copy without catalog ids: found by name and place.
        received.days[0].stops[0].ref = nil

        let enriched = catalog.enrich(received)
        XCTAssertEqual(enriched.intro, "Начните с горы")
        XCTAssertEqual(enriched.days[0].stops[0].guide?.lookFor.count, 2)
        XCTAssertEqual(enriched.days[0].stops[0].ref, "plyos-hill")
        XCTAssertNil(enriched.days[0].stops[1].guide)
    }

    func testUserCopyKeepsCatalogReference() throws {
        let (_, routes, _) = try catalog("ru")
        let copy = routes[0].userCopy()
        XCTAssertEqual(copy.days[0].stops[0].ref, "plyos-hill")
        XCTAssertEqual(copy.days[0].stops[0].guideKey, "plyos-hill")
        XCTAssertNotNil(copy.days[0].stops[0].guide)
    }

    func testLinksCarryReferencesAndOwnStories() throws {
        let (_, routes, catalog) = try catalog("ru")
        var route = routes[0].userCopy()
        route.days[0].stops.append(Stop(
            title: "Моя скамейка",
            coordinate: Coordinate(57.459, 41.51),
            details: "Тихое место",
            guide: StopGuide(story: "Здесь я читала Чехова.", lookFor: ["Чайку на фонаре"])
        ))

        let decoded = try ShareCodec.route(fromPayload: ShareCodec.payload(for: route))
        let stops = decoded.days[0].stops
        XCTAssertEqual(stops[0].ref, "plyos-hill")
        XCTAssertNil(stops[0].guide, "catalog guides stay out of links")
        XCTAssertEqual(stops[2].guide?.story, "Здесь я читала Чехова.")
        XCTAssertEqual(stops[2].guide?.lookFor, ["Чайку на фонаре"])
        XCTAssertNotNil(catalog.enrich(decoded).days[0].stops[0].guide)

        let minimal = try ShareCodec.route(fromPayload: ShareCodec.payload(for: route, detail: .minimal))
        XCTAssertNil(minimal.days[0].stops[2].guide)
        XCTAssertEqual(minimal.days[0].stops[0].ref, "plyos-hill")
    }

    func testProgressTogglesFindsAndKeepsTheFirstAnswer() {
        var progress = GuideProgress()
        progress.toggle("a", item: 1)
        progress.toggle("a", item: 0)
        XCTAssertTrue(progress.isFound("a", item: 1))
        XCTAssertEqual(progress.foundCount, 2)
        progress.toggle("a", item: 1)
        XCTAssertFalse(progress.isFound("a", item: 1))

        progress.answer("a", option: 2)
        progress.answer("a", option: 0)
        XCTAssertEqual(progress.answers["a"], 2)

        let data = try? JSONEncoder().encode(progress)
        XCTAssertEqual(data.flatMap { try? JSONDecoder().decode(GuideProgress.self, from: $0) }, progress)
    }

    func testOldStoredStopsStillDecode() throws {
        let json = #"{"title": "Кремль", "coordinate": [56.4, 40.4], "category": "castle"}"#
        let stop = try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
        XCTAssertNil(stop.guide)
        XCTAssertNil(stop.ref)
        XCTAssertEqual(stop.visitMinutes, PlaceCategory.castle.defaultVisitMinutes)
    }
}
