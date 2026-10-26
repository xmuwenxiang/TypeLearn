import Foundation

/// 对焦点元素文本做 diff，检测输入活动，按停顿或终止符触发翻译。
/// 触发时优先提取「光标所在句」作为翻译内容（保留中英混排原文），拿不到光标时回退到增量聚合。
final class DiffEngine {
    var onTrigger: ((String) -> Void)?
    var isEnabled = true

    private var lastText = ""
    /// 最近读到的光标位置（UTF-16 偏移），用于提取光标所在句
    private var lastCaretLocation: Int?
    /// 输入法组字（marked text）中：候选缓冲随时会被替换，不算正式输入
    private var isComposing = false
    /// 增量聚合：无法定位光标时的回退翻译内容
    private var pending = ""
    /// 上次触发后是否又有新输入，防止无输入场景（如选中文字）反复触发
    private var typedSinceFlush = false
    private var pauseTimer: Timer?
    /// 停顿触发时长（秒），可在设置中调整
    private var pauseInterval: TimeInterval { SettingsStore.shared.pauseInterval }
    /// 停顿触发的最小汉字数：低于该值视为半句话，保留等待继续输入
    private var minChineseCharsForPause: Int { SettingsStore.shared.minChineseChars }
    private let terminators: Set<Character> = ["。", "？", "！", ".", "?", "!", "\n", "；", ";"]

    /// 焦点切换或浮窗展示后重置基线，丢弃未决片段
    func reset(text: String) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pending = ""
        typedSinceFlush = false
        isComposing = false
        lastCaretLocation = nil
        lastText = text
    }

    /// 焦点元素 value 变化时调用；isComposing 表示输入法组字中，caretLocation 为光标 UTF-16 偏移
    func feed(newValue: String, isComposing: Bool, caretLocation: Int?) {
        guard isEnabled else { return }
        let addition = diff(old: lastText, new: newValue)
        lastText = newValue
        self.isComposing = isComposing
        lastCaretLocation = caretLocation
        // 组字中：拼音候选缓冲不算正式输入，只顺延停顿计时，绝不触发翻译
        if isComposing {
            schedulePauseTimer()
            return
        }
        // 无变化时不重置停顿计时器（轮询驱动下否则计时器永远无法到期）
        guard !addition.isEmpty else { return }
        pending += addition
        typedSinceFlush = true
        if addition.contains(where: { terminators.contains($0) }) {
            flush(force: true)
        } else {
            schedulePauseTimer()
        }
    }

    /// 回车等强制触发
    func forceFlush() {
        guard isEnabled, typedSinceFlush, !isComposing else { return }
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
        // 上次触发后没有新输入，不重复触发
        guard typedSinceFlush else { return }
        // 停顿触发时若仍在组字，说明还在打字，等组字结束后再判
        if !force, isComposing { return }
        let text = sentenceAtCaret() ?? pending.trimmingCharacters(in: .whitespacesAndNewlines)
        // 停顿触发：半句话（字数不足）不翻译，保留现场等继续输入
        if !force, text.chineseCharacterCount < minChineseCharsForPause { return }
        guard !text.isEmpty, text.containsChinese else { return }
        pending = ""
        typedSinceFlush = false
        onTrigger?(text)
    }

    /// 光标所在句：字段全文中，光标之前最近一个句子边界之后的内容
    private func sentenceAtCaret() -> String? {
        guard let caret = lastCaretLocation, caret > 0, !lastText.isEmpty else { return nil }
        let utf16 = lastText.utf16
        guard caret <= utf16.count else { return nil }
        let before = String(decoding: utf16.prefix(caret), as: UTF16.self)
        var start = before.startIndex
        for i in before.indices.reversed() {
            if terminators.contains(before[i]) {
                start = before.index(after: i)
                break
            }
        }
        var sentence = String(before[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉句首遗留的逗号/顿号等连接标点
        while let first = sentence.first, "，、：,.:;；".contains(first) {
            sentence.removeFirst()
        }
        sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
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
