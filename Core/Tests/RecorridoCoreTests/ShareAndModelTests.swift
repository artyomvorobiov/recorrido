import XCTest
@testable import RecorridoCore

final class ShareCodecTests: XCTestCase {
    private func sampleRoute() -> Route {
        Route(
            id: "suzdal-day",
            title: "Суздаль за день",
            summary: "Кремль, монастыри и деревянное зодчество.",
            city: "Суздаль",
            country: "Россия",
            emoji: "⛪",
            source: .curated,
            language: "ru",
            days: [
                RouteDay(title: "Пешком по центру", stops: [
                    Stop(title: "Суздальский кремль", coordinate: Coordinate(56.415_06, 40.440_51),
                         details: "Сердце города с Рождественским собором XIII века.",
                         tip: "Приходите к открытию.", category: .castle, visitMinutes: 60,
                         wikiTitle: "Суздальский кремль", wikiLanguage: "ru"),
                    Stop(title: "Торговые ряды", coordinate: Coordinate(56.419_6, 40.449_1),
                         details: "Галерея купеческих лавок начала XIX века.", category: .market),
                    Stop(title: "Кидекша", coordinate: Coordinate(56.4296, 40.5296),
                         details: "Белокаменная церковь 1152 года.", category: .church,
                         arrival: Arrival(mode: .car, note: "15 минут на такси")),
                ]),
            ]
        )
    }

    func testRoundTripKeepsEverything() throws {
        let route = sampleRoute()
        let payload = try ShareCodec.payload(for: route)
        let decoded = try ShareCodec.route(fromPayload: payload)

        XCTAssertEqual(decoded.title, route.title)
        XCTAssertEqual(decoded.summary, route.summary)
        XCTAssertEqual(decoded.city, route.city)
        XCTAssertEqual(decoded.source, .imported)
        XCTAssertEqual(decoded.originID, "suzdal-day")
        XCTAssertEqual(decoded.days.count, 1)
        XCTAssertEqual(decoded.days[0].title, "Пешком по центру")
        let stops = decoded.days[0].stops
        XCTAssertEqual(stops.map(\.title), route.days[0].stops.map(\.title))
        XCTAssertEqual(stops[0].tip, "Приходите к открытию.")
        XCTAssertEqual(stops[0].visitMinutes, 60)
        XCTAssertEqual(stops[0].category, .castle)
        XCTAssertEqual(stops[2].arrival?.mode, .car)
        XCTAssertEqual(stops[2].arrival?.note, "15 минут на такси")
        XCTAssertEqual(stops[1].coordinate.latitude, 56.4196, accuracy: 0.00001)
        XCTAssertNotEqual(stops[0].id, route.days[0].stops[0].id, "imported stops get fresh ids")
    }

    /// Made with Python's zlib (raw DEFLATE, wbits = -15) as docs/SHARE_FORMAT.md
    /// describes: links built on other platforms must open in the app.
    func testReadsPayloadsMadeElsewhere() throws {
        let payload = "AU1PwU6DUBD8lZc9YwOxoOFXjAeiHJqW2tjSapomFK5Go_FmDOrJI7WtVgv4C_P-xE9wANOYd3g7s7M7s1MZi2sZMhJXkOoIJZY6wRZfyBS-USqk2OpbPdeJGDKsZC9YE8aEJ_VU069gjZ9Qsj3HRt-Q80n9pNevLHssz0MWp-IeTRvLR2RYcF-ENd5RIKuHBrWgXwmemWjBjVHTVFjWIKPqUlz7oNV2TMeQC3HbVsu29g3pcmzc8SeDs05_1LgJ7rDBSlU7FOuSB_JMmRl_Lvek8j3kPP2DST4VHvi98YaYAYv_dvahtbMzHbvxC8KhHwYUBWyQ8_jLxOt1SXmVg2Uq5MxQ6ETHiptXVQh9tUuDjcyO-X4B"
        let route = try ShareCodec.route(fromPayload: payload)
        XCTAssertEqual(route.title, "Прогулка по Плёсу")
        XCTAssertEqual(route.city, "Плёс")
        XCTAssertEqual(route.emoji, "🎨")
        XCTAssertEqual(route.days.count, 1)
        XCTAssertEqual(route.days[0].title, "Набережная")
        let stops = route.days[0].stops
        XCTAssertEqual(stops.map(\.title), ["Соборная гора", "Дом-музей Левитана"])
        XCTAssertEqual(stops[0].category, .viewpoint)
        XCTAssertEqual(stops[1].visitMinutes, 45)
        XCTAssertEqual(stops[1].arrival?.mode, .walk)
        XCTAssertEqual(stops[1].arrival?.note, "10 минут вдоль Волги")
    }

    /// The body has to be raw DEFLATE, without a zlib header: that is what
    /// browsers (`DecompressionStream("deflate-raw")`) and Android expect.
    func testCompressedBodyIsRawDeflate() throws {
        let bytes = try XCTUnwrap(Base64URL.decode(try ShareCodec.payload(for: sampleRoute())))
        XCTAssertEqual(bytes.first, 1)
        let body = Array(bytes.dropFirst())
        let zlibHeader = body.count > 1 && body[0] & 0x0F == 8 && (Int(body[0]) * 256 + Int(body[1])) % 31 == 0
        XCTAssertFalse(zlibHeader)
    }

    func testPayloadIsURLSafe() throws {
        let payload = try ShareCodec.payload(for: sampleRoute())
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(payload.unicodeScalars.allSatisfy(allowed.contains))
    }

    func testShorterDetailLevelsProduceShorterPayloads() throws {
        var route = sampleRoute()
        route.days[0].stops[0].details = String(repeating: "Очень длинная история места. ", count: 40)
        let full = try ShareCodec.payload(for: route, detail: .full)
        let compact = try ShareCodec.payload(for: route, detail: .compact)
        let minimal = try ShareCodec.payload(for: route, detail: .minimal)
        XCTAssertLessThan(compact.count, full.count)
        XCTAssertLessThanOrEqual(minimal.count, compact.count)
        let decoded = try ShareCodec.route(fromPayload: minimal)
        XCTAssertEqual(decoded.stopCount, 3)
        XCTAssertEqual(decoded.days[0].stops[0].details, "")
    }

    func testLinksAndPayloadExtraction() throws {
        let route = sampleRoute()
        let web = try ShareCodec.link(for: route, base: URL(string: "https://example.github.io/recorrido/"))
        XCTAssertEqual(web.host, "example.github.io")
        let app = try ShareCodec.link(for: route, base: nil)
        XCTAssertEqual(app.scheme, "recorrido")

        for url in [web, app] {
            let payload = try XCTUnwrap(ShareCodec.payload(in: url))
            XCTAssertEqual(try ShareCodec.route(fromPayload: payload).title, route.title)
        }
        let query = URL(string: "https://example.com/?r=abc")!
        XCTAssertEqual(ShareCodec.payload(in: query), "abc")
        XCTAssertNil(ShareCodec.payload(in: URL(string: "recorrido://trip")!))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ShareCodec.route(fromPayload: "!!!"))
        XCTAssertThrowsError(try ShareCodec.route(fromPayload: Base64URL.encode(Data([9, 1, 2, 3]))))
    }

    func testBase64URLRoundTrip() {
        for length in 0..<20 {
            let data = Data((0..<length).map { UInt8(($0 * 37 + 250) % 256) })
            XCTAssertEqual(Base64URL.decode(Base64URL.encode(data)), data)
        }
    }
}

final class ModelTests: XCTestCase {
    func testUnknownValuesFallBack() throws {
        let json = #"""
        {"title": "X", "coordinate": [56, 40], "category": "spaceport", "arrival": {"mode": "teleport"}}
        """#
        let stop = try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
        XCTAssertEqual(stop.category, .other)
        XCTAssertEqual(stop.arrival?.mode, .walk)
        XCTAssertEqual(stop.visitMinutes, PlaceCategory.other.defaultVisitMinutes)
        XCTAssertFalse(stop.id.isEmpty)
    }

    func testRouteRoundTripThroughStorageCoders() throws {
        let route = Route(title: "Мой маршрут", city: "Коломна", days: [
            RouteDay(stops: [Stop(title: "Кремль", coordinate: Coordinate(55.1033, 38.7547), category: .castle)]),
        ])
        let data = try JSONCoders.encoder.encode(route)
        let decoded = try JSONCoders.decoder.decode(Route.self, from: data)
        XCTAssertEqual(decoded.id, route.id)
        XCTAssertEqual(decoded.allStops.first?.title, "Кремль")
        XCTAssertEqual(decoded.modes, [.walk])
    }

    func testUserCopyGetsNewIdentity() {
        let route = Route(id: "kolomna-day", title: "Коломна", city: "Коломна", source: .curated, days: [
            RouteDay(stops: [Stop(id: "a", title: "A", coordinate: Coordinate(55.1, 38.7))]),
        ])
        let copy = route.userCopy()
        XCTAssertNotEqual(copy.id, route.id)
        XCTAssertEqual(copy.source, .user)
        XCTAssertEqual(copy.originID, "kolomna-day")
        XCTAssertNotEqual(copy.days[0].stops[0].id, "a")
    }

    func testModesListWalkingFirst() {
        let route = Route(title: "T", city: "C", days: [
            RouteDay(stops: [
                Stop(title: "1", coordinate: Coordinate(55, 38)),
                Stop(title: "2", coordinate: Coordinate(55.01, 38), arrival: Arrival(mode: .tram)),
                Stop(title: "3", coordinate: Coordinate(55.02, 38)),
            ]),
        ])
        XCTAssertEqual(route.modes, [.walk, .tram])
    }
}

final class TripTests: XCTestCase {
    private func route() -> Route {
        Route(id: "r", title: "Маршрут", city: "Плёс", emoji: "🌊", days: [
            RouteDay(stops: [
                Stop(id: "s1", title: "Соборная гора", coordinate: Coordinate(57.4605, 41.5133)),
                Stop(id: "s2", title: "Набережная", coordinate: Coordinate(57.4593, 41.5110)),
                Stop(id: "s3", title: "Дом-музей Левитана", coordinate: Coordinate(57.4589, 41.5076)),
            ]),
        ])
    }

    func testCheckInSkipAndStepBack() {
        var trip = ActiveTrip(route: route(), dayIndex: 0)
        XCTAssertEqual(trip.nextStop?.id, "s1")
        XCTAssertEqual(trip.checkIn()?.id, "s1")
        trip.skip()
        XCTAssertEqual(trip.nextStop?.id, "s3")
        trip.stepBack()
        XCTAssertEqual(trip.nextStop?.id, "s2")
        trip.checkIn()
        trip.checkIn()
        XCTAssertTrue(trip.isFinished)
        XCTAssertEqual(trip.visitedIDs, ["s1", "s2", "s3"])
        XCTAssertEqual(trip.progress, 1)
    }

    func testTripLogRecordsVisits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = StorageLayout(directory: directory)
        try layout.trip.write(ActiveTrip(route: route(), dayIndex: 0))

        TripLog.checkIn(in: layout)
        let trip = try XCTUnwrap(TripLog.checkIn(in: layout))
        XCTAssertEqual(trip.currentIndex, 2)
        let visits = try XCTUnwrap(layout.visits.read())
        XCTAssertEqual(visits.map(\.stopID), ["s1", "s2"])
        XCTAssertEqual(visits[0].walked, 0)
        XCTAssertGreaterThan(visits[1].walked, 100)
    }

    func testCorruptFileIsSetAside() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = StorageLayout(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: layout.library.url)
        XCTAssertNil(layout.library.readSafely())
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.library.url.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.contains("broken") })
    }
}
