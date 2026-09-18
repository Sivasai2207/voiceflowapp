import Foundation
import Combine

@available(macOS 14.0, *)
@MainActor
final class DictationHistoryStore: ObservableObject {
    static let shared = DictationHistoryStore()

    @Published private(set) var entries: [DictationHistoryEntry]

    private let storageKey = "VoiceFlowApp.dictationHistory"
    private let maximumEntryCount = 200

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let savedEntries = try? JSONDecoder().decode([DictationHistoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = savedEntries.sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ transcript: String) {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return }

        entries.insert(DictationHistoryEntry(transcript: cleanedTranscript), at: 0)
        entries = Array(entries.prefix(maximumEntryCount))
        save()
    }

    func delete(_ entry: DictationHistoryEntry) {
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

struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let transcript: String
    let createdAt: Date

    init(id: UUID = UUID(), transcript: String, createdAt: Date = .now) {
        self.id = id
        self.transcript = transcript
        self.createdAt = createdAt
    }
}
