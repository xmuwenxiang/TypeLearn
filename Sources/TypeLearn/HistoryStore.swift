import Foundation

// MARK: - 历史记录

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    let source: String
    let translations: [String]
    let timestamp: Date

    // id 仅用于 SwiftUI 标识，不参与编解码
    enum CodingKeys: String, CodingKey {
        case source, translations, timestamp
    }
}

// MARK: - 翻译历史

/// 翻译历史：JSON 文件持久化，最新在前，上限 200 条
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let limit = 200

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeLearn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = loaded
        }
    }

    func add(source: String, translations: [String]) {
        entries.insert(HistoryEntry(source: source, translations: translations, timestamp: Date()), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
