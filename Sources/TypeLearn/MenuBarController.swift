import AppKit
import SwiftUI

/// 菜单栏常驻：暂停/恢复、设置、退出
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var isPaused = false
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    /// AX 读不到文本的应用名，非空时在菜单顶部提示改用快捷键
    private var fallbackHintApp: String?

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "character.book.closed",
                                           accessibilityDescription: "TypeLearn")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        // 当前应用不支持实时监听时，置顶提示可用快捷键兜底
        if let fallbackHintApp {
            let hint = NSMenuItem(title: "\(fallbackHintApp) 不支持实时监听，选中文本后按 ⌃⌘T",
                                  action: nil,
                                  keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
        }
        let toggle = NSMenuItem(title: isPaused ? "恢复学习" : "暂停学习",
                                action: #selector(togglePause),
                                keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let translateSelection = NSMenuItem(title: "翻译选中文本（⌃⌘T）",
                                            action: #selector(translateSelection),
                                            keyEquivalent: "")
        translateSelection.target = self
        menu.addItem(translateSelection)

        let history = NSMenuItem(title: "翻译历史…", action: #selector(openHistory), keyEquivalent: "h")
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 TypeLearn", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func togglePause() {
        isPaused.toggle()
        InputMonitor.shared.setPaused(isPaused)
        rebuildMenu()
    }

    @objc private func translateSelection() {
        ClipboardTranslationTrigger.shared.fire()
    }

    /// 由 InputMonitor 回调：某应用 AX 读不到文本时提示快捷键兜底
    func showFallbackHint(appName: String) {
        guard fallbackHintApp != appName else { return }
        fallbackHintApp = appName
        rebuildMenu()
    }

    @objc private func openHistory() {
        if let historyWindow {
            historyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "翻译历史"
        window.contentView = NSHostingView(rootView: HistoryView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "TypeLearn 设置"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
