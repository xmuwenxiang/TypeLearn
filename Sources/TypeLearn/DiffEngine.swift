import Foundation

/// 对焦点元素文本做 diff，聚合新增中文片段，按停顿或终止符触发翻译
final class DiffEngine {
    var onTrigger: ((String) -> Void)?
    var isEnabled = true

    private var lastText = ""
    private var pending = ""
    private var pauseTimer: Timer?
    /// 停顿触发时长（秒），可在设置中调整
    private var pauseInterval: TimeInterval { SettingsStore.shared.pauseInterval }
    /// 停顿触发的最小汉字数：低于该值视为半句话，保留等待继续输入
    private var minChineseCharsForPause: Int { SettingsStore.shared.minChineseChars }
    private let terminators: Set<Character> = ["。", "？", "！", ".", "?", "!"]

    /// 焦点切换或浮窗展示后重置基线，丢弃未决片段
    func reset(text: String) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pending = ""
        lastText = text
    }

    /// 焦点元素 value 变化时调用
    func feed(newValue: String) {
        guard isEnabled else { return }
        let addition = diff(old: lastText, new: newValue)
        lastText = newValue
        // 无变化时不重置停顿计时器（轮询驱动下否则计时器永远无法到期）
        guard !addition.isEmpty else { return }
        if addition.containsChinese {
            pending += addition
        }
        if addition.contains(where: { terminators.contains($0) }) {
            flush(force: true)
        } else {
            schedulePauseTimer()
        }
    }

    /// 回车等强制触发
    func forceFlush() {
        guard isEnabled else { return }
        flush(force: true)
    }

    // MARK: - 内部

    private func schedulePauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseInterval, repeats: false) { [weak self] _ in
            self?.flush(force: false)
        }
    }

    /// force=true：终止符/回车，无条件触发；force=false：停顿到期，需达到最小字数
    private func flush(force: Bool) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        guard isEnabled else {
            pending = ""
            return
        }
        // 停顿触发：半句话（字数不足）不翻译，保留 pending 等继续输入
        if !force, pending.chineseCharacterCount < minChineseCharsForPause { return }
        flushPending()
    }

    private func flushPending() {
        let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        guard !text.isEmpty, text.containsChinese else { return }
        onTrigger?(text)
    }

    /// 公共前后缀对齐，取新串的变化区作为新增内容
    private func diff(old: String, new: String) -> String {
        let o = Array(old), n = Array(new)
        var prefix = 0
        while prefix < o.count && prefix < n.count && o[prefix] == n[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < o.count - prefix && suffix < n.count - prefix
                && o[o.count - 1 - suffix] == n[n.count - 1 - suffix] { suffix += 1 }
        let end = n.count - suffix
        guard prefix < end else { return "" }
        return String(n[prefix..<end])
    }
}
