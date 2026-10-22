import Foundation

/// A question about the place, answered on the spot.
struct Quiz: Hashable, Codable, Sendable {
    var question: String
    var options: [String]
    /// Index of the right option in `options`.
    var answer: Int
    /// Shown after the traveller answers.
    var explanation: String

    var isValid: Bool {
        !question.isEmpty && options.count >= 2 && options.indices.contains(answer)
    }
}

/// Everything a human guide would tell at a stop.
struct StopGuide: Hashable, Sendable {
    /// The full story; paragraphs are separated by blank lines.
    var story: String
    /// Details to find with your own eyes, ticked off on the spot.
    var lookFor: [String]
    /// Short "did you know" facts.
    var facts: [String]
    var legend: String?
    var quiz: Quiz?
    /// What to notice on the way here from the previous stop.
    var approach: String?

    init(
        story: String = "",
        lookFor: [String] = [],
        facts: [String] = [],
        legend: String? = nil,
        quiz: Quiz? = nil,
        approach: String? = nil
    ) {
        self.story = story
        self.lookFor = lookFor
        self.facts = facts
        self.legend = legend
        self.quiz = quiz
        self.approach = approach
    }

    var paragraphs: [String] {
        story.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        story.nilIfEmpty == nil && lookFor.isEmpty && facts.isEmpty && legend?.nilIfEmpty == nil
            && quiz == nil && approach?.nilIfEmpty == nil
    }
}

extension StopGuide: Codable {
    private enum CodingKeys: String, CodingKey {
        case story, lookFor, facts, legend, quiz, approach
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            story: try container.decodeIfPresent(String.self, forKey: .story) ?? "",
            lookFor: try container.decodeIfPresent([String].self, forKey: .lookFor) ?? [],
            facts: try container.decodeIfPresent([String].self, forKey: .facts) ?? [],
            legend: try container.decodeIfPresent(String.self, forKey: .legend),
            quiz: try? container.decodeIfPresent(Quiz.self, forKey: .quiz),
            approach: try container.decodeIfPresent(String.self, forKey: .approach)
        )
    }
}

/// A town's own guidebook page: its story, history, food and practical advice.
struct CityGuide: Hashable, Codable, Sendable {
    struct Moment: Hashable, Codable, Sendable {
        /// "1152", "XIV век", "1990s" — as it should be shown.
        var year: String
        var text: String
    }

    /// A longer introduction; paragraphs are separated by blank lines.
    var story: String = ""
    var history: [Moment] = []
    /// Local food worth trying.
    var taste: [String] = []
    var souvenirs: [String] = []
    var tips: [String] = []

    var paragraphs: [String] {
        story.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        story.nilIfEmpty == nil && history.isEmpty && taste.isEmpty && souvenirs.isEmpty && tips.isEmpty
    }
}

/// Lists in several languages: `{"ru": ["…"], "en": ["…"]}` or a plain array.
struct LocalizedList: Hashable, Sendable {
    var values: [String: [String]]

    init(_ values: [String: [String]]) {
        self.values = values
    }

    /// The list in `language`, falling back to Russian, English, then anything.
    func items(_ language: String) -> [String] {
        for key in [language, "ru", "en", "*"] {
            let items = (values[key] ?? []).compactMap(\.nilIfEmpty)
            if !items.isEmpty { return items }
        }
        if let key = values.keys.sorted().first {
            return (values[key] ?? []).compactMap(\.nilIfEmpty)
        }
        return []
    }
}

extension LocalizedList: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let items = try? container.decode([String].self) {
            values = ["*": items]
        } else {
            values = try container.decode([String: [String]].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1, let items = values["*"] {
            try container.encode(items)
        } else {
            try container.encode(values)
        }
    }
}

/// What the traveller has found and answered, per stop. Kept on the phone.
struct GuideProgress: Hashable, Codable, Sendable {
    /// Stop id → indices of the `lookFor` items ticked off.
    var found: [String: [Int]] = [:]
    /// Stop id → the option chosen in the quiz.
    var answers: [String: Int] = [:]

    func isFound(_ stopID: String, item: Int) -> Bool {
        found[stopID]?.contains(item) ?? false
    }

    mutating func toggle(_ stopID: String, item: Int) {
        var items = Set(found[stopID] ?? [])
        if items.contains(item) {
            items.remove(item)
        } else {
            items.insert(item)
        }
        found[stopID] = items.isEmpty ? nil : items.sorted()
    }

    mutating func answer(_ stopID: String, option: Int) {
        if answers[stopID] == nil { answers[stopID] = option }
    }

    var foundCount: Int { found.values.reduce(0) { $0 + $1.count } }
}
