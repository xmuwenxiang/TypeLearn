import AppKit
import ApplicationServices

@main
struct TypeLearnApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication.delegate 是弱引用，release 优化会提前释放局部 delegate，
        // 用 withExtendedLifetime 保证其存活至 app.run() 结束
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.syncLaunchAtLogin()
        menuBarController = MenuBarController()
        if AXIsProcessTrusted() {
            InputMonitor.shared.start()
        } else {
            // 触发系统授权提示，并轮询等待授权完成
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.permissionTimer = nil
                    // AX 服务端在进程启动时记录授权状态，授权后必须重启进程才能让 AXUIElement 调用生效
                    Self.restartToApplyPermission()
                }
            }
        }
    }

    /// 用 open -n 启动新实例后退出自身，使 AX 服务端重新识别授权
    private static func restartToApplyPermission() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}
