import Foundation

// MARK: - 翻译结果

struct TranslationResult: Codable {
    let translations: [String]
}

// MARK: - 中文检测

extension String {
    /// 是否包含汉字（基本区 + 扩展A）
    var containsChinese: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    /// 汉字个数
    var chineseCharacterCount: Int {
        unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
        }.count
    }
}

// MARK: - LLM 系统提示词

enum Prompts {
    static let workplaceEnglish = """
    你是职场英语学习助手。用户提供一段中文（来自日常工作输入，可能是聊天消息、邮件或文档片段），请给出地道的职场英文表达。
    要求：
    1. 提供 1-2 个自然的英文表达，第一个为最常用说法；
    2. 语气专业、贴合职场场景，兼顾即时消息与邮件风格；
    3. 只输出 JSON，格式：{"translations": ["英文表达1", "英文表达2"]}，不要输出任何其他文字、解释或 markdown 代码块。
    """
}
