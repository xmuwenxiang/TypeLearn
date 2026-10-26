# Type & Learn 设计文档

日期：2026-10-23
状态：已与用户确认

## 1. 背景与目标

职场人每天大量键盘输入（聊天、写文档、回邮件），希望在不打断工作的前提下随时学习英语。

产品形态：macOS 菜单栏常驻工具。用户在任何应用中正常打字，当输入的中文片段被识别后，屏幕上出现一个不打扰操作的浮窗，展示对应的地道职场英文表达。

核心体验：打中文 → 停顿或结束一句 → 浮窗浮现英文表达 → 继续工作。

## 2. 关键决策（已确认）

| 决策点 | 结论 |
|---|---|
| 应用形态 | macOS 桌面全局监听工具，菜单栏常驻（无 Dock 图标） |
| 学习方向 | 中文输入 → 英文表达（单向） |
| 翻译引擎 | 纯 LLM 实时翻译（用户自配 OpenAI 兼容 API） |
| 技术栈 | Swift + SwiftUI 原生，仅 macOS |
| 输入捕获 | AX（辅助功能）监听焦点元素文本变化为主；CGEventTap 仅辅助检测回车/Esc/焦点切换 |

## 3. 系统架构

单一 macOS App，内部模块划分：

| 模块 | 职责 |
|---|---|
| InputMonitor | 通过 AX API 观察系统焦点 UI 元素的 value 变化；CGEventTap 捕获回车/Esc 等辅助按键事件 |
| DiffEngine | 对焦点元素文本做 diff，提取新增片段；聚合新增片段，实现停顿检测与触发判定 |
| TranslationService | 调用 OpenAI 兼容 `/chat/completions`（流式），内置系统提示词，生成 1-2 个地道职场英文表达 |
| FloatingPanel | NSPanel（nonactivatingPanel）承载 SwiftUI 浮窗，不抢焦点，跟随光标位置 |
| MenuBarController | 菜单栏图标、暂停/恢复开关、设置窗口入口、退出 |
| SettingsStore | 保存 baseURL/model 到 UserDefaults，API key 存 Keychain |
| CacheStore | 翻译结果本地缓存（本地 JSON 文件，规范化中文文本为 key），命中则不发请求 |

依赖方向：MenuBarController → InputMonitor → DiffEngine → TranslationService → FloatingPanel；SettingsStore、CacheStore 被各模块按需引用。

## 4. 核心流程

1. 用户在任意应用（飞书、微信、浏览器、文档等）的输入框打字
2. AX 观察到焦点元素 `AXValue` 变化 → DiffEngine 提取新增文本，仅保留含中文（CJK 字符）的片段并累计
3. 满足任一触发条件后送翻译：
   - 输入停顿 ≥ 1.5 秒
   - 或输入回车 / 句号 / 问号 / 感叹号
4. 纯英文片段不触发翻译，不打扰
5. 查 CacheStore，命中直接展示；未命中则流式调用 LLM
6. FloatingPanel 在焦点元素光标附近展示：中文原句（小字灰色）→ 英文表达（大字醒目，1-2 个备选）
7. 结果写入缓存；浮窗约 8 秒后自动淡出，Esc 或点击关闭按钮立即关闭

## 5. 关键技术点

- 权限：辅助功能权限（AX 观察与 CGEventTap 共用同一权限），首次启动显示授权引导页，授权后自动继续
- LLM 请求：OpenAI 兼容接口；设置中配置 baseURL、API key、model；内置系统提示词，要求输出地道的职场口语化英文表达，JSON 结构化返回便于解析
- 隐私边界：捕获的文本仅发送到用户自己配置的 API 端点，无任何其他上报；缓存明文存本地，设置中提供一键清空
- 兼容性：主流原生 App 支持良好；部分 Electron 应用与终端的 AX 支持较弱，静默跳过不报错

## 6. MVP 范围

做：菜单栏常驻与开关、设置窗口、AX 输入监听、diff 与停顿聚合、LLM 流式翻译、本地缓存、跟随光标的浮窗、授权引导。

不做：账户系统、学习统计报告、词典管理、双向翻译、深度学习卡片、跨平台支持。

## 7. 错误处理

- 无辅助功能权限 → 启动引导授权，未授权时不启动监听
- API 失败 → 浮窗短暂提示"翻译失败"，静默重试 1 次，仍失败则放弃本轮
- 焦点元素不可读 / 不支持 AX → 静默跳过
- 网络断开 → 同 API 失败处理；恢复后自然继续
