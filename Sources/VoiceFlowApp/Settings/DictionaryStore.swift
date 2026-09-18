import Foundation
import Combine

struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let word: String

    init(id: UUID = UUID(), word: String) {
        self.id = id
        self.word = word
    }
}

@MainActor
final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()

    @Published private(set) var entries: [DictionaryEntry]

    private let storageKey = "VoiceFlowApp.customDictionary"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let savedEntries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = savedEntries.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    func add(word: String) {
        let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedWord.isEmpty else { return }

        entries.removeAll { $0.word.compare(cleanedWord, options: .caseInsensitive) == .orderedSame }
        entries.append(DictionaryEntry(word: cleanedWord))
        entries.sort { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func deleteAll() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
