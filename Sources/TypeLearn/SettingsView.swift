import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("LLM API（OpenAI 兼容）") {
                TextField("Base URL", text: $store.baseURL)
                SecureField("API Key", text: $store.apiKey)
                TextField("Model", text: $store.model)
            }
            Section("触发") {
                LabeledContent("停顿触发时长") {
                    Text(String(format: "%.1f 秒", store.pauseInterval))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $store.pauseInterval, in: 1.5...5, step: 0.5)
                LabeledContent("停顿触发最少汉字数") {
                    Text("\(store.minChineseChars) 字")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(store.minChineseChars) },
                    set: { store.minChineseChars = Int($0) }
                ), in: 2...12, step: 1)
            }
            Section("通用") {
                Toggle("开机自启", isOn: $store.launchAtLogin)
            }
            Section("数据") {
                Button("清空翻译缓存") {
                    CacheStore.shared.clear()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }
}
