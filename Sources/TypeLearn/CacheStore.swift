import Foundation

/// 翻译结果本地缓存：JSON 文件，key 为规范化后的中文原文
final class CacheStore {
    static let shared = CacheStore()

    private let fileURL: URL
    private var dict: [String: [String]] = [:]
    private let limit = 1000

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeLearn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("cache.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            dict = loaded
        }
    }

    func lookup(_ text: String) -> [String]? {
        dict[normalize(text)]
    }

    func store(_ text: String, _ translations: [String]) {
        dict[normalize(text)] = translations
        if dict.count > limit {
            // 超限时简单截断（无 LRU 语义）
            let overflow = dict.count - limit
            for key in dict.keys.prefix(overflow) {
                dict.removeValue(forKey: key)
            }
        }
        save()
    }

    func clear() {
        dict = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
