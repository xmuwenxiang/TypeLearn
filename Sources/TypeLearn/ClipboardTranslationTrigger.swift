import AppKit
import Carbon.HIToolbox

/// Carbon 热键签名 'TYLR'，注册与回调校验共用
private let typeLearnHotKeySignature: OSType = 0x54594C52

/// 全局快捷键兜底：模拟 Cmd+C 取当前选中文本后直接翻译。
/// 用于 AX API 读不到文本的应用（Sublime Text、终端等自绘控件）。
final class ClipboardTranslationTrigger {
    static let shared = ClipboardTranslationTrigger()

    private static let hotKeyID: UInt32 = 1
    /// 读回选中文本的最大长度，超出视为无效（避免误选大段内容触发翻译）
    private static let maxLength = 2000
    /// Cmd+C 后等待粘贴板更新的时长
    private static let copyLatency: TimeInterval = 0.2

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isBusy = false

    private init() {}

    func start() {
        installHandler()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_T),
                                         UInt32(cmdKey | controlKey),
                                         EventHotKeyID(signature: typeLearnHotKeySignature, id: Self.hotKeyID),
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr { hotKeyRef = ref }
    }

    /// 快捷键与菜单项共用入口
    func fire() {
        guard !isBusy, !InputMonitor.shared.isPaused else { return }
        isBusy = true

        let pasteboard = NSPasteboard.general
        let savedItems = Self.snapshot(of: pasteboard)
        let beforeCount = pasteboard.changeCount
        sendCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyLatency) { [weak self] in
            guard let self else { return }
            let changed = pasteboard.changeCount != beforeCount
            let copied = changed ? pasteboard.string(forType: .string) : nil
            // 恢复用户原有剪贴板，避免快捷键占用其内容
            if changed { Self.restore(savedItems, to: pasteboard) }
            self.isBusy = false

            guard let text = copied?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text.containsChinese, text.count <= Self.maxLength else { return }
            TranslationService.shared.translate(text)
        }
    }

    // MARK: - 内部

    private func installHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyHandlerCallback,
                            1,
                            &type,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &handlerRef)
    }

    /// 向当前前台应用发送 Cmd+C
    private func sendCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: CGKeyCode(kVK_ANSI_C),
                                      keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            var filled = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    filled = true
                }
            }
            return filled ? copy : nil
        } ?? []
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}

private let hotKeyHandlerCallback: EventHandlerUPP = { _, event, refcon in
    guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
    var hotKeyToken = EventHotKeyID()
    guard GetEventParameter(event,
                            EventParamName(kEventParamDirectObject),
                            EventParamType(typeEventHotKeyID),
                            nil,
                            MemoryLayout<EventHotKeyID>.size,
                            nil,
                            &hotKeyToken) == noErr,
          hotKeyToken.signature == typeLearnHotKeySignature else { return OSStatus(eventNotHandledErr) }
    let trigger = Unmanaged<ClipboardTranslationTrigger>.fromOpaque(refcon).takeUnretainedValue()
    trigger.fire()
    return noErr
}
