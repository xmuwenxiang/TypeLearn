import AppKit
import AVFoundation
import SwiftUI

/// 非激活浮窗：中英对照卡片，跟随光标，8 秒自动淡出
final class FloatingPanel {
    static let shared = FloatingPanel()

    private var panel: NSPanel?
    private var hideTimer: Timer?
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
                                       onClose: { [weak self] in self?.close() })
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

    private func scheduleHide() {
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

private struct FloatingContentView: View {
    let source: String
    let translations: [String]
    let loading: Bool
    let failed: Bool
    let onClose: () -> Void

    @State private var index = 0
    @State private var copied = false
    @State private var isSpeaking = false

    private var current: String? {
        guard !translations.isEmpty else { return nil }
        return translations[min(index, translations.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 中文原文
            HStack(alignment: .firstTextBaseline) {
                Text(source)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.6)

            // 英文表达
            if loading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("翻译中…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if failed {
                Label("翻译失败，请检查 API 配置或网络", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            } else if let current {
                Text(current)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .id(index)
                    .transition(.opacity)

                HStack(spacing: 10) {
                    if translations.count > 1 {
                        // 多条表达切换
                        HStack(spacing: 2) {
                            Button {
                                guard index > 0 else { return }
                                withAnimation(.easeInOut(duration: 0.15)) { index -= 1 }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)

                            Text("\(min(index, translations.count - 1) + 1)/\(translations.count)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)

                            Button {
                                guard index < translations.count - 1 else { return }
                                withAnimation(.easeInOut(duration: 0.15)) { index += 1 }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .disabled(index >= translations.count - 1)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // 朗读
                    Button {
                        if isSpeaking {
                            SpeechController.shared.stop()
                            isSpeaking = false
                        } else {
                            SpeechController.shared.speak(current)
                            isSpeaking = true
                        }
                    } label: {
                        Image(systemName: isSpeaking ? "speaker.wave.slash" : "speaker.wave.2")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                    .onAppear {
                        SpeechController.shared.onStateChange = { speaking in
                            DispatchQueue.main.async {
                                self.isSpeaking = speaking
                            }
                        }
                    }

                    // 复制
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(current, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label(copied ? "已复制" : "复制",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copied ? .green : .secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
        )
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
