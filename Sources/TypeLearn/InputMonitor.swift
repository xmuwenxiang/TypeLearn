import AppKit
import ApplicationServices

/// 通过 AX API 监听焦点输入框文本变化；CGEventTap 辅助检测回车/Esc
final class InputMonitor {
    static let shared = InputMonitor()

    private let diffEngine = DiffEngine()
    private let systemWide = AXUIElementCreateSystemWide()
    private var observer: AXObserver?
    private var observerPid: pid_t = 0
    private var eventTap: CFMachPort?
    private var pollTimer: Timer?
    private var focusedElement: AXUIElement?
    private var accessibilityEnabledPids: Set<pid_t> = []
    /// 强制开启辅助功能后，首次读到 value 时只建基线不当作新增输入（避免已有文本误触发翻译）
    private var awaitingFirstValue = false
    private(set) var isPaused = false

    private init() {
        diffEngine.onTrigger = { text in
            TranslationService.shared.translate(text)
        }
    }

    func start() {
        watchFocusedElement()
        installEventTap()
        startPolling()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            diffEngine.reset(text: "")
            FloatingPanel.shared.close()
        }
    }

    // MARK: - 浮窗定位

    /// 焦点元素中光标的屏幕坐标（左下原点），拿不到则回退到焦点元素 frame
    func cursorBounds() -> CGRect? {
        guard let element = focusedElement else { return nil }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                                                         kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeValue,
                                                         &boundsRef) == .success,
              let boundsValue = boundsRef else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    // MARK: - AX

    /// 每次按键时调用：若焦点元素发生迁移，重新订阅 valueChanged（systemWide 焦点通知不可用时的兜底）
    private func ensureFocusedWatch() {
        var newElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &newElement) == .success,
              let ref = newElement else { return }
        let element = ref as! AXUIElement
        if let current = focusedElement, CFEqual(current, element) { return }
        watchFocusedElement()
    }

    fileprivate func handleAXNotification(element: AXUIElement, notification: String) {
        guard !isPaused else { return }
        switch notification {
        case kAXFocusedUIElementChangedNotification:
            watchFocusedElement()
        case kAXValueChangedNotification:
            feedCurrentValue(of: element)
        default:
            break
        }
    }

    private func watchFocusedElement() {
        // 移除旧元素的订阅
        if let old = focusedElement, let observer = observer {
            AXObserverRemoveNotification(observer, old, kAXValueChangedNotification as CFString)
        }
        var newElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &newElement) == .success,
              let ref = newElement else {
            focusedElement = nil
            diffEngine.reset(text: "")
            return
        }
        let element = ref as! AXUIElement
        focusedElement = element

        // AXObserver 绑定被观察应用的 pid，焦点跨应用时重建
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        enableAccessibilityIfNeeded(pid: pid)
        if pid != observerPid {
            if let old = observer {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
            }
            var created: AXObserver?
            let result = AXObserverCreate(pid, axCallback, &created)
            guard result == .success, let created else {
                observer = nil
                observerPid = 0
                diffEngine.reset(text: currentValue(of: element) ?? "")
                return
            }
            observer = created
            observerPid = pid
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        }

        if let observer = observer {
            AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        diffEngine.reset(text: currentValue(of: element) ?? "")
    }

    private func currentValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else { return nil }
        return valueRef as? String
    }

    /// Chrome/Electron 应用（飞书、Slack、VS Code 等）默认不构建辅助功能树，焦点元素 value 读不到；
    /// 设置 AXManualAccessibility / AXEnhancedUserInterface 强制开启（Chrome 收到后会异步建树，轮询会读到）
    private func enableAccessibilityIfNeeded(pid: pid_t) {
        guard pid > 0, !accessibilityEnabledPids.contains(pid) else { return }
        accessibilityEnabledPids.insert(pid)
        awaitingFirstValue = true
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// 读取焦点元素当前值并驱动 diff；辅助功能刚开启后的首读只建立基线
    private func feedCurrentValue(of element: AXUIElement) {
        guard let value = currentValue(of: element) else { return }
        if awaitingFirstValue {
            awaitingFirstValue = false
            diffEngine.reset(text: value)
        } else {
            diffEngine.feed(newValue: value)
        }
    }

    // MARK: - 下钻查找文本域

    /// Chromium 系应用（ChatGPT/Claude/DeepSeek 等）焦点元素常报告为 AXGroup/AXWindow 而非文本域；
    /// 缓存下钻找到的文本域，避免每 0.5s 重复遍历大树
    private var cachedTextElement: AXUIElement?
    private var cachedTextPid: pid_t = 0

    private func pollFeed() {
        // 正常路径：焦点元素本身是文本域且有 value
        if let element = focusedElement, Self.isTextRole(element), currentValue(of: element) != nil {
            feedCurrentValue(of: element)
            return
        }
        // 下钻路径：从焦点元素或应用主窗口查找可读文本域
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        if let cached = cachedTextElement, cachedTextPid == pid, currentValue(of: cached) != nil {
            feedCurrentValue(of: cached)
            return
        }
        var root: AXUIElement?
        if let el = focusedElement { root = el }
        if root == nil {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                             kAXMainWindowAttribute as CFString,
                                             &winRef) == .success, let ref = winRef {
                root = (ref as! AXUIElement)
            }
        }
        guard let rootNode = root, let found = Self.findTextElement(from: rootNode) else { return }
        cachedTextElement = found
        cachedTextPid = pid
        feedCurrentValue(of: found)
    }

    private static func isTextRole(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return false }
        return role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox"
    }

    /// BFS 查找第一个可读 value 的文本域；kAXFocused 为 true 的子树优先
    private static func findTextElement(from root: AXUIElement, maxDepth: Int = 8, maxNodes: Int = 3000) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var fallback: AXUIElement?
        while !queue.isEmpty && visited < maxNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String else { continue }
            if role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" {
                var valRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef) == .success,
                   valRef is String {
                    return element
                }
                if fallback == nil { fallback = element }
            }
            guard depth < maxDepth else { continue }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else { continue }
            for child in children {
                var focusedRef: CFTypeRef?
                let isFocused = AXUIElementCopyAttributeValue(child, kAXFocusedAttribute as CFString, &focusedRef) == .success
                    && (focusedRef as? Bool) == true
                if isFocused {
                    queue.insert((child, depth + 1), at: 0)
                } else {
                    queue.append((child, depth + 1))
                }
            }
        }
        return fallback
    }

    // MARK: - 轮询

    /// AXObserver 跨进程通知不可靠，改用低频轮询主动读值驱动 diff（同时覆盖粘贴、语音输入等无按键场景）
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            // Chromium 系应用（ChatGPT/Claude/VS Code 等）默认不建辅助功能树，此时连焦点元素都拿不到；
            // 必须对活跃应用直接设置 AXManualAccessibility，不能依赖"先拿到焦点元素"（否则死锁）
            if let app = NSWorkspace.shared.frontmostApplication {
                self.enableAccessibilityIfNeeded(pid: app.processIdentifier)
            }
            self.ensureFocusedWatch()
            self.pollFeed()
        }
    }

    // MARK: - CGEventTap

    private func installEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: eventTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return
        }
        eventTap = tap
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .defaultMode)
    }

    fileprivate func handleKeyDown(keyCode: Int64) {
        guard !isPaused else { return }
        ensureFocusedWatch()
        switch keyCode {
        case 36: // return
            diffEngine.forceFlush()
        case 53: // esc
            FloatingPanel.shared.close()
        default:
            break
        }
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleAXNotification(element: element, notification: notification as String)
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard type == .keyDown, let refcon else { return nil }
    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleKeyDown(keyCode: event.getIntegerValueField(.keyboardEventKeycode))
    return nil
}
