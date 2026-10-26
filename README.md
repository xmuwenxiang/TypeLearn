# TypeLearn

一款 macOS 菜单栏应用：在任意输入框打中文时，实时弹出地道的职场英文翻译，帮助你在日常工作中顺便学英语。

## 功能

- **实时翻译**：监听任意应用的输入框，输入中文后按停顿或句末标点自动触发，无需复制粘贴
- **中英对照浮窗**：跟随光标弹出卡片，支持多条表达切换、一键复制、英文朗读（美音），8 秒自动淡出
- **翻译历史**：菜单栏「翻译历史…」（⌘H）查看最近的翻译记录，时间倒序，可复制、可清空
- **触发参数可调**：设置页可调整停顿触发时长（1.5–5 秒）与最少汉字数（2–12 字），立即生效
- **本地缓存**：相同原文直接复用历史翻译，不再重复请求
- **开机自启**：设置页一键开启（系统登录项），启动时自动同步注册状态

## 系统要求

- macOS 13.0 及以上
- Xcode / Swift 工具链（仅构建时需要）

## 构建与运行

```bash
# 构建 TypeLearn.app（release 编译 + 签名，输出到 build/TypeLearn.app）
./scripts/make_app.sh

# 启动
open build/TypeLearn.app
```

首次启动需在「系统设置 → 隐私与安全性 → 辅助功能」中授权 TypeLearn，授权后应用会自动重启生效。

## 使用

1. 启动后菜单栏出现书本图标
2. 首次使用在「设置…」（⌘,）中配置 OpenAI 兼容 API：Base URL、API Key、Model
3. 在任意输入框输入中文，停顿（默认 3 秒）或以 `。？！.?!` 结尾即触发翻译
4. 浮窗内可切换多条表达、复制、点喇叭朗读；半句话（低于最少汉字数）不会误触发

菜单栏菜单支持随时「暂停学习 / 恢复学习」。

## 数据存储

所有数据保存在本地 `~/Library/Application Support/TypeLearn/`：

| 文件 | 内容 |
| --- | --- |
| `cache.json` | 翻译结果缓存（最多 1000 条） |
| `history.json` | 翻译历史（最多 200 条） |

API Key 存储在系统钥匙串（Keychain），不落明文文件。

## 项目结构

```
Sources/TypeLearn/
├── AppMain.swift            # 入口：辅助功能授权轮询与重启
├── InputMonitor.swift       # Accessibility 监听输入、定位光标
├── DiffEngine.swift         # 文本 diff、停顿/终止符触发策略
├── TranslationService.swift # OpenAI 兼容流式 API 调用
├── FloatingPanel.swift      # 浮窗卡片与英文朗读
├── HistoryStore.swift       # 翻译历史持久化
├── HistoryView.swift        # 历史列表界面
├── MenuBarController.swift  # 菜单栏图标与窗口管理
├── SettingsStore.swift      # 设置持久化（UserDefaults + Keychain）
├── SettingsView.swift       # 设置界面
├── CacheStore.swift         # 翻译缓存
└── Models.swift             # 数据模型与提示词
```

## 隐私

输入内容仅在触发翻译时发送到你自行配置的 LLM API，除此外不做任何上传；缓存与历史均保留在本机。
