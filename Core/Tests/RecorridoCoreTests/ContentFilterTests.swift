import XCTest
@testable import RecorridoCore

final class ContentFilterTests: XCTestCase {
    func testOrdinaryTravelTextsPass() {
        for text in [
            "Небанальный маршрут по Суздалю",
            "Застрахуемся от дождя зонтиком",
            "Хлеб, небо и шлюз на Волге",
            "Мандарины на рынке и мандат депутата",
            "Shiitake soup and a bitter coffee in Paris",
            "Ёлки у Спасо-Евфимиева монастыря",
        ] {
            XCTAssertTrue(ContentFilter.isClean(text), text)
        }
    }

    func testObsceneWordsAreCaught() {
        for text in ["Ну и хуйня", "Пиздец как красиво", "Это ёбаный стыд", "бля, красиво", "Fuck this place", "Какая СУКА"] {
            XCTAssertFalse(ContentFilter.isClean(text), text)
        }
    }

    func testTheWholeRouteIsChecked() {
        var route = Route(title: "Прогулка", city: "Плёс", days: [RouteDay(stops: [
            Stop(title: "Набережная", coordinate: Coordinate(57.46, 41.51), details: "Тихо и красиво"),
        ])])
        XCTAssertTrue(ContentFilter.isClean(route))
        route.days[0].stops[0].guide = StopGuide(story: "Тут такой пиздец")
        XCTAssertFalse(ContentFilter.isClean(route))
    }
}
