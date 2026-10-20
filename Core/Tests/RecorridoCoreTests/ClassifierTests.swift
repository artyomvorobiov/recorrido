import XCTest
@testable import RecorridoCore

/// Examples taken from real geosearch results around Paris, Moscow and Suzdal.
final class ClassifierTests: XCTestCase {
    private func category(_ title: String, _ description: String? = nil, type: String? = nil, city: String? = nil) -> PlaceCategory? {
        PlaceClassifier.classify(title: title, description: description, geoType: type, cityName: city)
    }

    func testRecognizesSights() {
        XCTAssertEqual(category("Notre-Dame de Paris", "Cathedral in Paris, France, built 1163–1345"), .church)
        XCTAssertEqual(category("Eiffel Tower", "Tower in Paris, France"), .viewpoint)
        XCTAssertEqual(category("Centre Pompidou", "Art museum in Paris, France"), .museum)
        XCTAssertEqual(category("Pont Neuf", "Bridge across the Seine in Paris, France"), .bridge)
        XCTAssertEqual(category("Champ de Mars", "Public park in Paris, France"), .park)
        XCTAssertEqual(category("Красная площадь", "главная площадь Москвы"), .square)
        XCTAssertEqual(category("Храм Василия Блаженного", "православный храм в Москве"), .church)
        XCTAssertEqual(category("Московский Кремль", "Каменная крепость XIV века"), .castle)
        XCTAssertEqual(category("Большой Кремлёвский дворец", "бывшая резиденция императоров"), .palace)
        XCTAssertEqual(category("Спасская башня", "Проездная башня Московского Кремля"), .viewpoint)
        XCTAssertEqual(category("Царь-пушка", "бомбарда, отлитая из бронзы в 1586 году"), .monument)
        XCTAssertEqual(category("Покровский монастырь (Суздаль)", "женский монастырь в Суздале"), .church)
        XCTAssertEqual(category("Суздальский кремль"), .castle)
        XCTAssertEqual(category("Музей деревянного зодчества"), .museum)
        XCTAssertEqual(category("Пожарная каланча (Суздаль)"), .viewpoint)
        XCTAssertEqual(category("Архиерейские палаты"), .palace)
        XCTAssertEqual(category("Церковь Бориса и Глеба (Кидекша)", "Православный храм в селе Кидекша"), .church)
        XCTAssertEqual(category("Богородице-Рождественский собор (Суздаль)", "православный храм в Суздале, Владимирская область, Россия"), .church)
        XCTAssertEqual(category("Музей-фабрика пастилы", "музей в Коломне"), .museum)
        XCTAssertEqual(category("Синий камень", "валун на берегу Плещеева озера"), .nature)
        XCTAssertEqual(category("Tsar Bell", nil, type: "landmark"), .landmark)
    }

    func testSkipsThingsThatAreNotStops() {
        XCTAssertNil(category("Notre-Dame fire", "2019 church fire in Paris, France"))
        XCTAssertNil(category("Death of Diana, Princess of Wales", "1997 fatal car crash in Paris, France"))
        XCTAssertNil(category("Louis Vuitton", "French international fashion house"))
        XCTAssertNil(category("Timeline of Paris"))
        XCTAssertNil(category("Paris", "Capital and largest city of France", type: "city", city: "Paris"))
        XCTAssertNil(category("Second French Empire", "France under Napoleon III (1852–1870)"))
        XCTAssertNil(category("La Motte-Picquet–Grenelle station", "Metro station in Paris, France"))
        XCTAssertNil(category("Musée d'Ethnographie du Trocadéro", "Defunct museum in Paris, France"))
        XCTAssertNil(category("Суздальский район", "муниципальный район в Владимирской области России", type: "adm2nd"))
        XCTAssertNil(category("Суздаль", "город в Суздальском районе Владимирской области России", city: "Суздаль"))
        XCTAssertNil(category("Суздаль (главный туристический комплекс)", nil, city: "Суздаль"))
        XCTAssertNil(category("Кидекша", "село в Суздальском районе Владимирской области России"))
        XCTAssertNil(category("Битва под Суздалем (1445)"))
        XCTAssertNil(category("Государственная дума", "нижняя палата российского парламента"))
        XCTAssertNil(category("Метрополь (гостиница, Москва)", "гостиница в центре Москвы класса «5 звёзд»"))
        XCTAssertNil(category("Площадь Революции (станция метро, Москва)", "станция Московского метрополитена"))
        XCTAssertNil(category("Парад Победы", "парад на Красной площади 24 июня 1945 года"))
        XCTAssertNil(category("Убийство Бориса Немцова", "убийство одного из лидеров российской оппозиции"))
        XCTAssertNil(category("Казаковский корпус МГУ"))
        XCTAssertNil(category("АФК «Система»", "российская финансово-промышленная группа"))
    }

    func testWordMatching() {
        XCTAssertTrue(PlaceClassifier.matches("летний сад", "сад$"))
        XCTAssertFalse(PlaceClassifier.matches("садовая улица", "сад$"))
        XCTAssertTrue(PlaceClassifier.matches("монастыря", "монастыр"))
        XCTAssertFalse(PlaceClassifier.matches("parking garage", "park$"))
        XCTAssertFalse(PlaceClassifier.matches("brandenburg gate", "brand$"))
        XCTAssertTrue(PlaceClassifier.matches("царь-колокол", "колокол$"))
    }

    func testWikiTextCleanup() {
        let raw = "Москва́ (МФА: [mɐˈs̪kvä] ) — столица России.  Город ( ) большой."
        XCTAssertEqual(WikiText.clean(raw), "Москва — столица России. Город большой.")
        let english = "The Centre Pompidou (French pronunciation: [sɑ̃tʁ pɔ̃pidu]), also known as Beaubourg, is a building."
        XCTAssertEqual(WikiText.clean(english), "The Centre Pompidou, also known as Beaubourg, is a building.")
    }
}
