import AppKit
import AVFoundation
import SwiftUI

/// 非激活浮窗：中英对照卡片，跟随光标；悬停或朗读期间保持，其余情况 8 秒自动淡出
final class FloatingPanel {
    static let shared = FloatingPanel()

    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var hovering = false
    private var speaking = false
    private let autoHideInterval: TimeInterval = 8

    func show(source: String, translations: [String], loading: Bool) {
        showInternal(source: source, translations: translations, loading: loading, failed: false)
    }

    func showFailure(source: String) {
        showInternal(source: source, translations: [], loading: false, failed: true)
    }

    func close() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let panel else { return }
        panel.orderOut(nil)
    }

    // MARK: - 内部

    private func showInternal(source: String, translations: [String], loading: Bool, failed: Bool) {
        SpeechController.shared.stop()
        let panel = ensurePanel()
        let view = FloatingContentView(source: source,
                                       translations: translations,
                                       loading: loading,
                                       failed: failed,
                                       onClose: { [weak self] in self?.close() },
                                       onHoverChange: { [weak self] in self?.setHovering($0) },
                                       onSpeakingChange: { [weak self] in self?.setSpeaking($0) })
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setFrame(Self.frame(origin: origin(for: size), size: size), display: true)
        // 渐入
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        scheduleHide()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true // 系统阴影跟随内容不透明形状（圆角卡片）
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    /// 光标下方偏移；拿不到光标时回退到主屏右上角
    private func origin(for size: CGSize) -> CGPoint {
        let margin: CGFloat = 14
        var origin: CGPoint
        if let cursor = InputMonitor.shared.cursorBounds() {
            origin = CGPoint(x: cursor.minX, y: cursor.maxY + margin)
        } else if let visible = NSScreen.main?.visibleFrame {
            origin = CGPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 48)
        } else {
            origin = CGPoint(x: 100, y: 100)
        }
        if let visible = NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        return origin
    }

    private static func frame(origin: CGPoint, size: CGSize) -> NSRect {
        NSRect(origin: origin, size: size)
    }

    /// 鼠标悬停在浮窗上：暂停自动隐藏，移开后重新计时
    private func setHovering(_ hovering: Bool) {
        self.hovering = hovering
        if hovering {
            hideTimer?.invalidate()
            hideTimer = nil
        } else {
            scheduleHide()
        }
    }

    /// 朗读期间保持浮窗，读完后重新计时（悬停中则以悬停为准）
    private func setSpeaking(_ speaking: Bool) {
        self.speaking = speaking
        if speaking {
            hideTimer?.invalidate()
            hideTimer = nil
        } else if !hovering {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        guard !hovering, !speaking else { return }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: autoHideInterval, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }
}

// MARK: - 浮窗内容

/// 原生极简风：英文表达为主角、中文原文为辅、底部图标操作条（hover 高亮）
private struct FloatingContentView: View {
    let source: String
    let translations: [String]
    let loading: Bool
    let failed: Bool
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
    let onSpeakingChange: (Bool) -> Void

    @State private var index = 0
    @State private var copied = false
    @State private var isSpeaking = false
    @State private var hoverID: String?

    private var current: String? {
        guard !translations.isEmpty else { return nil }
        return translations[min(index, translations.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loading {
                statusRow(systemImage: nil, title: "翻译中…", tint: .secondary, showSpinner: true)
            } else if failed {
                statusRow(systemImage: "exclamationmark.triangle",
                          title: "翻译失败，请检查 API 配置或网络",
                          tint: .orange,
                          showSpinner: false)
            } else if let current {
                resultContent(current)
            }
        }
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
        )
        .onHover { onHoverChange($0) }
    }

    // MARK: 结果态

    private func resultContent(_ current: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(current)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .id(index)
                .transition(.opacity)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            Text(source)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 4)

            Divider().opacity(0.5)
                .padding(.top, 10)

            actionBar(current)
        }
    }

    // MARK: 加载 / 失败态

    private func statusRow(systemImage: String?, title: String, tint: Color, showSpinner: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                if showSpinner {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                iconButton("close", "xmark") { onClose() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
    }

    // MARK: 操作条

    private func actionBar(_ current: String) -> some View {
        HStack(spacing: 2) {
            if translations.count > 1 {
                iconButton("prev", "chevron.left", size: 9) {
                    guard index > 0 else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { index -= 1 }
                }
                .disabled(index == 0)

                Text("\(min(index, translations.count - 1) + 1)/\(translations.count)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)

                iconButton("next", "chevron.right", size: 9) {
                    guard index < translations.count - 1 else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { index += 1 }
                }
                .disabled(index >= translations.count - 1)
            }

            Spacer()

            iconButton("speak", isSpeaking ? "speaker.wave.slash" : "speaker.wave.2") {
                if isSpeaking {
                    SpeechController.shared.stop()
                    isSpeaking = false
                    onSpeakingChange(false)
                } else {
                    SpeechController.shared.speak(current)
                    isSpeaking = true
                    onSpeakingChange(true)
                }
            }
            .onAppear {
                SpeechController.shared.onStateChange = { speaking in
                    DispatchQueue.main.async {
                        self.isSpeaking = speaking
                        self.onSpeakingChange(speaking)
                    }
                }
            }

            iconButton("copy", copied ? "checkmark" : "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(current, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            }
            .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))

            iconButton("close", "xmark") { onClose() }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    /// 极简图标按钮：tertiary 常显，hover 时淡底高亮
    private func iconButton(_ id: String, _ systemName: String,
                            size: CGFloat = 11,
                            action: @escaping () -> Void) -> some View {
        let hovering = hoverID == id
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { entering in
            if entering {
                hoverID = id
            } else if hoverID == id {
                hoverID = nil
            }
        }
    }
}

// MARK: - 英文朗读

private final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechController()

    var onStateChange: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStateChange?(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onStateChange?(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onStateChange?(false)
    }
}
