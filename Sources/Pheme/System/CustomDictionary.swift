import Foundation

enum CustomDictionary {
    private static let key = "customDictionary"

    static var words: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var promptFragment: String {
        let w = words.filter { !$0.isEmpty }
        guard !w.isEmpty else { return "" }
        return "Custom vocabulary: \(w.joined(separator: ", ")). "
    }

    static func add(_ word: String) {
        var w = words
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !w.contains(trimmed) else { return }
        w.append(trimmed)
        words = w
    }

    static func remove(at index: Int) {
        var w = words
        guard index < w.count else { return }
        w.remove(at: index)
        words = w
    }
}
