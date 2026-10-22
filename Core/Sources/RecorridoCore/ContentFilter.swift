import Foundation

/// Keeps obscene words out of the community feed. The App Store asks apps
/// with user content to filter it; reports and blocking handle the rest.
///
/// Words are compared after folding case and diacritics, so "Ё" and "е"
/// match. Most stems must start a word: short Russian roots appear inside
/// innocent words ("небанальный", "застрахуемся").
enum ContentFilter {
    /// A word starting with any of these is rejected.
    static let stems: [String] = [
        // Russian
        "хуй", "хуя", "хуе", "хуи", "пизд", "ебат", "ебан", "ебал", "ебло", "еблан", "ебуч", "ебну",
        "заеб", "уеба", "уебк", "уебищ", "выеб", "наеб", "проеб", "отъеб", "съеб", "долбоеб", "распизд",
        "бляд", "блят", "мудак", "мудил", "мудоз", "гандон", "пидор", "пидар", "пидр", "шлюх",
        // English
        "fuck", "motherfuck", "shit", "cunt", "nigger", "nigga", "faggot", "whore", "slut", "asshole",
        "bitch", "bastard",
    ]

    /// Rejected only as whole words.
    static let words: Set<String> = ["бля", "сука", "суки", "сучка", "хер", "манда", "fag", "dick"]

    // Folded like the text: "й" becomes "и", "ё" becomes "е".
    private static let foldedStems = stems.map(PlaceClassifier.normalize)
    private static let foldedWords = Set(words.map(PlaceClassifier.normalize))

    static func isClean(_ text: String) -> Bool {
        let folded = PlaceClassifier.normalize(text)
        for word in folded.split(whereSeparator: { !$0.isLetter }) {
            let word = String(word)
            if foldedWords.contains(word) || foldedStems.contains(where: { word.hasPrefix($0) }) {
                return false
            }
        }
        return true
    }

    /// Everything a published route shows to others.
    static func isClean(_ route: Route) -> Bool {
        var texts = [route.title, route.summary, route.city, route.author ?? ""]
        for stop in route.allStops {
            texts += [stop.title, stop.details, stop.tip ?? "", stop.arrival?.note ?? ""]
            if let guide = stop.guide {
                texts += [guide.story, guide.legend ?? "", guide.approach ?? ""] + guide.lookFor + guide.facts
            }
        }
        return texts.allSatisfy { isClean($0) }
    }
}
