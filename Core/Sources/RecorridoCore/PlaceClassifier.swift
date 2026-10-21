import Foundation

/// Decides whether a Wikipedia article is a place worth walking to, and what
/// kind of place it is. Works with English and Russian titles and
/// descriptions; other languages fall back to the coordinate type.
///
/// Keywords match at the start of a word, so the stem "монастыр" finds
/// "монастырь" and "монастыря". A keyword ending with "$" must be a whole word.
enum PlaceClassifier {
    struct Rule {
        let category: PlaceCategory
        let keywords: [String]
    }

    /// Checked in order; the first matching rule wins.
    static let rules: [Rule] = [
        Rule(category: .square, keywords: [
            "square", "plaza", "piazza", "place de", "platz", "площадь", "майдан",
        ]),
        Rule(category: .street, keywords: [
            "street", "avenue", "boulevard", "promenade", "embankment", "quay", "rambla",
            "улица", "проспект", "бульвар", "набережная", "аллея", "спуск", "взвоз",
        ]),
        Rule(category: .bridge, keywords: [
            "bridge", "viaduct", "aqueduct", "мост$", "моста$", "мосты$", "виадук", "акведук",
        ]),
        Rule(category: .museum, keywords: [
            "museum", "gallery", "musee", "museo", "planetarium", "aquarium", "zoo$",
            "музей", "галере", "кунсткамера", "экспозиц", "планетари", "океанариум", "зоопарк",
        ]),
        Rule(category: .church, keywords: [
            "cathedral", "church", "chapel", "basilica", "abbey", "monastery", "convent", "priory",
            "mosque", "synagogue", "temple", "shrine", "pagoda", "minaret", "belfry",
            "собор", "церковь", "церкви", "храм", "часовня", "монастыр", "лавра", "мечеть",
            "синагог", "костел", "кирха", "капелла", "базилик", "аббатств", "пагода", "минарет",
            "скит$", "подворье", "звонниц",
        ]),
        Rule(category: .castle, keywords: [
            "castle", "fortress", "citadel", "kremlin", "bastion", "fort$", "fortification",
            "крепост", "замок", "замка$", "кремль", "кремля$", "цитадел", "бастион", "форт$",
            "детинец", "городище", "острог", "стена$", "city wall",
        ]),
        Rule(category: .palace, keywords: [
            "palace", "palais", "palazzo", "manor", "chateau", "estate",
            "дворец", "дворца$", "палаццо", "усадьб", "палаты$", "резиденци",
        ]),
        Rule(category: .theater, keywords: [
            "theatre", "theater", "opera", "concert hall", "philharmoni", "circus", "cabaret", "music hall",
            "театр", "оперы$", "оперн", "филармони", "концертный зал", "консерватори", "цирк$", "кабаре",
        ]),
        Rule(category: .market, keywords: [
            "market", "bazaar", "bazar", "souk", "arcade",
            "рынок", "рынка$", "базар", "пассаж", "гостиный двор", "торговые ряды", "гум$",
        ]),
        Rule(category: .park, keywords: [
            "park", "garden", "jardin", "giardino", "botanic", "arboretum",
            "парк", "сад$", "сада$", "сады$", "сквер", "ботаническ", "дендрари", "оранжере",
        ]),
        Rule(category: .viewpoint, keywords: [
            "viewpoint", "lookout", "observation", "belvedere", "tower", "skyscraper", "hill$", "mount$",
            "смотров", "башня", "башни$", "небоскреб", "холм", "гора$", "горы$", "бельведер",
            "колокольн", "обзорн", "каланча",
        ]),
        Rule(category: .landmark, keywords: [
            "памятник архитектуры", "памятник истории", "объект культурного наследия",
        ]),
        Rule(category: .monument, keywords: [
            "monument", "memorial", "statue", "sculpture", "obelisk", "column", "triumphal", "arc de",
            "fountain", "mausoleum", "tomb", "cenotaph", "cannon", "ossuary", "catacomb",
            "памятник", "монумент", "мемориал", "статуя", "скульптур", "обелиск", "колонна", "колонны$",
            "триумфальн", "фонтан", "мавзолей", "гробниц", "усыпальниц", "пушка", "колокол$", "стела",
            "катакомб",
        ]),
        Rule(category: .nature, keywords: [
            "lake", "beach", "waterfall", "island", "forest", "nature reserve", "national park", "cave",
            "lagoon", "cliff", "dune", "canyon", "gorge", "spring$", "boulder",
            "озеро", "пляж", "водопад", "остров", "лес$", "заповедник", "пещер", "лагун", "залив",
            "утес", "скала", "дюна", "коса$", "каньон", "ущелье", "родник", "источник", "ключ$",
            "валун",
        ]),
        Rule(category: .district, keywords: [
            "district", "quarter", "neighbourhood", "neighborhood", "old town", "historic centre",
            "historic center", "район", "квартал", "слобода", "старый город", "исторический центр", "посад$",
        ]),
        Rule(category: .food, keywords: [
            "restaurant", "cafe", "bakery", "patisserie", "brewery", "tavern",
            "ресторан", "кафе$", "пекарн", "кондитерск", "пивоварн", "трактир", "кофейн", "чайхан",
        ]),
        Rule(category: .landmark, keywords: [
            "building", "town hall", "city hall", "landmark", "gate", "lighthouse", "pavilion", "ensemble",
            "mansion", "cemetery", "exhibition centre", "exhibition center",
            "здание", "ратуша", "ворота", "маяк", "дом$", "павильон", "ансамбль", "архитектурн",
            "достопримечательн", "особняк", "кладбище", "некрополь", "выставочный комплекс",
            "выставка достижений",
        ]),
    ]

    /// Description phrases that mark events: these rule an article out even
    /// when its title names a place ("Notre-Dame fire").
    static let eventDescriptions: [String] = [
        "battle", "siege", "massacre", "attack", "bombing", "shooting", "riot", "accident", "crash",
        "disaster", "fire$", "fires$", "flood", "earthquake", "murder", "assassination", "death of",
        "festival", "world's fair", "exposition universelle", "olympic", "championship", "tournament",
        "treaty", "conference", "ceremony", "defunct", "demolished", "parade",
        "битва", "сражение", "осада", "резня", "теракт", "взрыв", "катастрофа", "крушение", "авария",
        "пожар$", "наводнение", "землетрясение", "убийство", "восстание", "мятеж", "фестиваль",
        "чемпионат", "турнир", "олимпиад", "договор", "конференци", "церемони", "утрачен", "снесен",
        "несохранивш", "парад$", "парада$",
    ]

    /// Description phrases of articles that are not a place to visit:
    /// transport, institutions, businesses, settlements. Only checked when the
    /// title itself does not name a kind of place.
    static let excludedDescriptions: [String] = [
        "railway station", "train station", "metro station", "subway station", "underground station",
        "tram stop", "bus station", "bus stop", "airport", "interchange", "parking", "car park",
        "motorway", "highway", "railway line", "metro line",
        "станция", "вокзал", "остановочный пункт", "железнодорожная платформа", "аэропорт",
        "метрополитен", "линия метро", "развязка", "шоссе", "переулок", "проезд$", "тупик$", "парковк",
        "school", "gymnasium", "lyceum", "college", "hospital", "clinic", "embassy", "consulate",
        "company", "corporation", "conglomerate", "bank$", "insurance", "hotel", "hostel", "office",
        "headquarters", "business cent", "shopping cent", "shopping mall", "ministry", "courthouse",
        "court of", "prison", "factory", "power station", "residential", "apartment", "housing",
        "fashion house", "brand$", "retailer", "department store", "organisation", "organization",
        "agency", "association", "institute", "research", "laboratory", "newspaper", "publisher",
        "radio station", "television channel", "tv channel", "broadcaster", "police", "fire station",
        "post office", "military unit", "military base", "barracks", "political party", "parliament",
        "government", "council", "nonprofit", "non-profit", "trade union", "stock exchange", "velodrome",
        "sports club", "football club", "university", "revolution", "history of", "list of", "timeline",
        "школа", "гимназия", "лицей", "колледж", "техникум", "училище", "больница", "поликлиника",
        "госпиталь", "посольство", "консульство", "компания", "корпорация", "холдинг", "концерн",
        "группа компаний", "финансово", "банк$", "страхов", "гостиница", "отель", "хостел", "офис",
        "штаб-квартир", "бизнес-центр", "бизнес центр", "торговый центр", "торгово-развлекательный",
        "министерств", "суд$", "тюрьма", "изолятор", "завод", "фабрика", "комбинат", "электростанц",
        "жилой дом", "жилой комплекс", "многоквартирн", "организаци", "агентство", "ассоциаци",
        "фонд$", "институт", "научно-исследовательск", "лаборатор", "газета", "издательств",
        "радиостанц", "телеканал", "телекомпани", "полици", "пожарная часть", "пожарное депо",
        "почтовое отделение", "воинская часть", "казармы", "партия", "парламент", "правительств",
        "администраци", "ведомств", "профсоюз", "биржа", "быстрого питания", "сеть ",
        "спортивный клуб", "футбольный клуб", "университет", "предприяти", "революци", "история ",
        "список",
        "city in", "town in", "village in", "hamlet", "capital of", "capital city", "largest city",
        "commune in", "human settlement", "settlement in", "suburb", "metropolitan area",
        "administrative", "electoral", "constituency", "river in", "tributary",
        "город в", "город на", "город федерального", "городское поселение", "сельское поселение",
        "поселок", "деревня", "село$", "хутор", "столица", "административн", "населенный пункт",
        "муниципальный район", "муниципальное образование", "муниципальный округ", "городской округ",
        "микрорайон", "избирательн", "река$", "приток",
    ]

    /// Title phrases that rule an article out whatever its description says.
    static let excludedTitles: [String] = [
        "станция", "вокзал", "аэропорт", "airport", "railway station", "list of", "список",
        "history of", "timeline of", "история ", "битва", "battle of", "siege of", "осада",
        "школа", "гимназия", "лицей", "больница", "посольство", "embassy of", "консульство",
        "бизнес-центр", "торговый центр", "жилой дом", "жилой комплекс", "метрополитен", "линия метро",
        "olympics", "ceremony", "церемония", "корпус$", "район$", "уезд", "волость",
        "заказник", "болото$", "болота$", "урочище", "железнодорожный мост", "railway bridge",
    ]

    /// Places with long articles (mostly lists of the people buried there)
    /// that rarely make a first visit. They stay, with a lower score.
    static let minorTitles: [String] = [
        "cemetery", "graveyard", "кладбищ", "некропол",
    ]

    /// Coordinate types (from the {{coord}} template) that are never single stops.
    static let excludedGeoTypes: Set<String> = [
        "country", "state", "adm1st", "adm2nd", "adm3rd", "city", "airport", "railwaystation",
        "edu", "event", "camera", "river", "satellite",
    ]

    /// Coordinate types that mark a place even when no keyword matches.
    static let placeGeoTypes: [String: PlaceCategory] = [
        "landmark": .landmark, "church": .church, "mountain": .viewpoint, "isle": .nature,
        "waterbody": .nature, "forest": .nature, "glacier": .nature,
    ]

    /// Category of a place, or `nil` when the article does not look like a
    /// place to visit.
    static func classify(title rawTitle: String, description rawDescription: String?, geoType: String?, cityName: String? = nil) -> PlaceCategory? {
        let title = normalize(rawTitle)
        let description = normalize(rawDescription ?? "")
        let type = geoType.map(normalizeType)

        if let type, excludedGeoTypes.contains(type) { return nil }
        if let cityName, isCityItself(title: title, city: normalize(cityName)) { return nil }
        if compiled.excludedTitles.contains(where: { matches(title, $0) }) { return nil }
        if compiled.events.contains(where: { matches(description, $0) }) { return nil }

        if let category = category(in: title) { return category }
        if compiled.excludedDescriptions.contains(where: { matches(description, $0) }) { return nil }
        if let category = category(in: description) { return category }
        if let type, let category = placeGeoTypes[type] { return category }
        return nil
    }

    /// How much visitors usually care about this particular place, judging
    /// by its title: 1 for most places, less for cemeteries.
    static func interest(title: String) -> Double {
        let text = normalize(title)
        return compiled.minorTitles.contains { matches(text, $0) } ? 0.6 : 1
    }

    /// How much a category is usually worth a detour, relative to a landmark.
    static func weight(of category: PlaceCategory) -> Double {
        switch category {
        case .landmark, .museum, .palace, .castle, .viewpoint: 1
        case .church, .square: 0.95
        case .park, .nature: 0.9
        case .bridge, .monument, .market, .theater: 0.85
        case .street: 0.75
        case .food, .other: 0.7
        case .district: 0.55
        }
    }

    // MARK: - Matching

    /// A keyword prepared for matching.
    struct Keyword: Sendable {
        let text: String
        let wholeWord: Bool

        init(_ raw: String) {
            wholeWord = raw.hasSuffix("$")
            text = PlaceClassifier.normalize(wholeWord ? String(raw.dropLast()) : raw)
        }
    }

    private struct Compiled: Sendable {
        let rules: [(category: PlaceCategory, keywords: [Keyword])]
        let events: [Keyword]
        let excludedDescriptions: [Keyword]
        let excludedTitles: [Keyword]
        let minorTitles: [Keyword]
    }

    /// Keywords are normalized once, on first use.
    private static let compiled = Compiled(
        rules: rules.map { (category: $0.category, keywords: $0.keywords.map(Keyword.init)) },
        events: eventDescriptions.map(Keyword.init),
        excludedDescriptions: excludedDescriptions.map(Keyword.init),
        excludedTitles: excludedTitles.map(Keyword.init),
        minorTitles: minorTitles.map(Keyword.init)
    )

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func category(in text: String) -> PlaceCategory? {
        guard !text.isEmpty else { return nil }
        return compiled.rules.first { rule in rule.keywords.contains { matches(text, $0) } }?.category
    }

    private static func normalizeType(_ type: String) -> String {
        let lowered = type.lowercased()
        if let bracket = lowered.firstIndex(of: "(") {
            return String(lowered[..<bracket])
        }
        return lowered
    }

    private static func isCityItself(title: String, city: String) -> Bool {
        guard !city.isEmpty else { return false }
        return title == city || title.hasPrefix(city + " (") || title.hasPrefix(city + ",")
    }

    /// True when the keyword starts a word in the already normalized `text`.
    static func matches(_ text: String, _ rawKeyword: String) -> Bool {
        matches(text, Keyword(rawKeyword))
    }

    static func matches(_ text: String, _ keyword: Keyword) -> Bool {
        guard !keyword.text.isEmpty, !text.isEmpty else { return false }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: keyword.text, range: searchStart..<text.endIndex) {
            let startsWord = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            let endsWord = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if startsWord && (!keyword.wholeWord || endsWord) { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }
}
