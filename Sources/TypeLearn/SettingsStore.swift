import Foundation
import Security
import ServiceManagement

// MARK: - Keychain 存取

enum KeychainHelper {
    private static let service = "TypeLearn"
    private static let account = "apiKey"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func set(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let data = value.data(using: .utf8), !data.isEmpty else { return }
        var add = baseQuery
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 设置

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let baseURLKey = "baseURL"
    private static let modelKey = "model"
    private static let pauseIntervalKey = "pauseInterval"
    private static let minChineseCharsKey = "minChineseChars"
    private static let launchAtLoginKey = "launchAtLogin"

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLKey) }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }

    /// 仅用于设置界面显示与编辑，实际持久化在 Keychain
    @Published var apiKey: String {
        didSet { KeychainHelper.set(apiKey) }
    }

    /// 停顿触发翻译的等待时长（秒），范围 1.5-5
    @Published var pauseInterval: Double {
        didSet { UserDefaults.standard.set(pauseInterval, forKey: Self.pauseIntervalKey) }
    }

    /// 停顿触发的最小汉字数，范围 2-12
    @Published var minChineseChars: Int {
        didSet { UserDefaults.standard.set(minChineseChars, forKey: Self.minChineseCharsKey) }
    }

    /// 开机自启（SMAppService LoginItem）
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)
            Self.applyLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    private init() {
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLKey)
            ?? "https://api.openai.com/v1"
        model = UserDefaults.standard.string(forKey: Self.modelKey)
            ?? "gpt-4o-mini"
        apiKey = KeychainHelper.get()
        pauseInterval = UserDefaults.standard.object(forKey: Self.pauseIntervalKey) as? Double ?? 3.0
        minChineseChars = UserDefaults.standard.object(forKey: Self.minChineseCharsKey) as? Int ?? 6
        launchAtLogin = UserDefaults.standard.bool(forKey: Self.launchAtLoginKey)
    }

    var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    private static func applyLaunchAtLogin(enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    /// 启动时兜底同步：上次注册可能因需要用户在系统设置确认而未生效
    static func syncLaunchAtLogin() {
        guard UserDefaults.standard.bool(forKey: launchAtLoginKey) else { return }
        try? SMAppService.mainApp.register()
    }
}
