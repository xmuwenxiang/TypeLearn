import Foundation

/// 调用 OpenAI 兼容 API（流式），将中文片段翻译为地道职场英文表达
final class TranslationService {
    static let shared = TranslationService()

    private var currentTask: Task<Void, Never>?
    private let timeout: TimeInterval = 30

    func translate(_ text: String) {
        if let cached = CacheStore.shared.lookup(text) {
            FloatingPanel.shared.show(source: text, translations: cached, loading: false)
            return
        }
        guard SettingsStore.shared.isConfigured else {
            FloatingPanel.shared.showFailure(source: text)
            return
        }
        currentTask?.cancel()
        FloatingPanel.shared.show(source: text, translations: [], loading: true)
        let settings = SettingsStore.shared
        // @MainActor：UI 调用（FloatingPanel.show 等）必须在主线程；request 的网络 await 仍在后台执行
        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let translations = try await self.request(baseURL: settings.baseURL,
                                                          apiKey: settings.apiKey,
                                                          model: settings.model,
                                                          text: text)
                guard !Task.isCancelled, !translations.isEmpty else { return }
                CacheStore.shared.store(text, translations)
                HistoryStore.shared.add(source: text, translations: translations)
                FloatingPanel.shared.show(source: text, translations: translations, loading: false)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // 静默重试 1 次
                do {
                    let translations = try await self.request(baseURL: settings.baseURL,
                                                              apiKey: settings.apiKey,
                                                              model: settings.model,
                                                              text: text)
                    guard !Task.isCancelled, !translations.isEmpty else { return }
                    CacheStore.shared.store(text, translations)
                    HistoryStore.shared.add(source: text, translations: translations)
                    FloatingPanel.shared.show(source: text, translations: translations, loading: false)
                } catch {
                    guard !Task.isCancelled else { return }
                    FloatingPanel.shared.showFailure(source: text)
                }
            }
        }
    }

    // MARK: - 请求

    private func request(baseURL: String, apiKey: String, model: String, text: String) async throws -> [String] {
        let url = try Self.endpointURL(from: baseURL)
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": Prompts.workplaceEnglish],
                ["role": "user", "content": text]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        var content = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            if let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let piece = delta["content"] as? String {
                content += piece
            }
        }
        return try Self.parseTranslations(content)
    }

    /// baseURL 可能是 "https://host/v1" 或完整 endpoint，统一补全为 /chat/completions
    static func endpointURL(from baseURL: String) throws -> URL {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw URLError(.badURL) }
        if !trimmed.lowercased().hasSuffix("/chat/completions") {
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            trimmed += "/chat/completions"
        }
        guard let url = URL(string: trimmed) else { throw URLError(.badURL) }
        return url
    }

    /// 从 LLM 输出中提取 JSON 并解析为表达数组（容忍 markdown 代码块包裹）
    static func parseTranslations(_ content: String) throws -> [String] {
        var json = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}") {
            json = String(json[start...end])
        }
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(TranslationResult.self, from: data),
              !result.translations.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return result.translations
    }
}
