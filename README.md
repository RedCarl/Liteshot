# Liteshot

[![Build](https://github.com/RedCarl/Liteshot/actions/workflows/build.yml/badge.svg)](https://github.com/RedCarl/Liteshot/actions/workflows/build.yml)
[![Release](https://github.com/RedCarl/Liteshot/actions/workflows/release.yml/badge.svg)](https://github.com/RedCarl/Liteshot/actions/workflows/release.yml)

轻量原生的 macOS 截图与标注工具：菜单栏常驻，专注区域 / 窗口 / 全屏截图、滚动截图与标注。
原生 Swift + AppKit/SwiftUI，MIT 开源，本地构建自用，不依赖 App Store。

> **状态**：截图域功能已完成（M1–M5）；交互已按参考产品对齐（自适应截图、选区工具条、滚动统一入口、窗口多选、OCR 队列等，详见 [交互对照](docs/交互对照.md)）。开源发布，不要求上架、Developer ID 签名或公证。
> 本地构建可直接使用；「检查更新」查询 GitHub Releases 并打开下载页，不包含自动安装。

## 功能

- **自适应截图**：一个入口完成区域 / 窗口 / 全屏——悬停高亮窗口，点击截窗口，拖拽截区域，点空白或按 F 截全屏；支持放大镜、取色、边界吸附、Shift 正方形、方向键微调
- **滚动截图**：竖向、横向、全景（横竖同时）；HUD 完成/取消
- **标注编辑器**：矩形、椭圆、箭头、线条、画笔、高亮、区域高亮、马赛克（水晶/高斯/六边形）、文字、序号、水印、插入图片；撤销重做、图层、持久化样式、像素级导出
- **输出**：PNG/JPEG、自动保存、文件名模板、剪贴板、圆角/阴影/透明背景、Retina 缩小
- **效率**：OCR 与二维码（Vision 本地识别）、钉图、截图历史（最多 50 张）、全局快捷键自定义
- **其他**：中英双语、菜单栏常驻、GitHub Releases 更新检查

## 环境

- macOS 14 或更新
- Xcode 16 或更新（本项目在 Xcode 27.2 上验证）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

## 构建与运行

```bash
git clone git@github.com:RedCarl/Liteshot.git
cd Liteshot

# 生成工程并构建（不签名，适合本地自用）
./scripts/build.sh

# 构建并启动
./scripts/run.sh
```

或者手动：

```bash
xcodegen generate
xcodebuild -project Liteshot.xcodeproj -scheme Liteshot \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

在 Xcode 里打开时，若想直接 Run，把 Signing 设为 **Sign to Run Locally** 即可。

构建产物在 `DerivedData` 下，`scripts/build.sh` 会打印完整 `Liteshot.app` 路径。

## 发布新版本（GitHub Actions）

推送 `v*` 标签会触发 Release 工作流：在 macOS runner 上构建 **Universal（arm64 + x86_64）** 未签名 Release，打包 zip + SHA256，并自动创建 GitHub Release。

```bash
git tag v0.2.0
git push origin v0.2.0
```

- 版本号取自标签（`v0.2.0` → `0.2.0`），构建号用 Actions 的 run number。
- 工作流：`.github/workflows/release.yml`；日常构建检查：`.github/workflows/build.yml`。
- 产物为 ad-hoc 签名、未公证；首次打开需右键 → 打开，或 `xattr -dr com.apple.quarantine /Applications/Liteshot.app`。
- 更新方式是下载新的 Release 包并手动替换 App，不做自动安装。

## 首次使用

1. 启动后只有菜单栏图标（`LSUIElement`，不占 Dock）。
2. 没有屏幕录制权限时，Liteshot 会先显示自己的**权限窗口**（中间显示所需权限和当前授权状态），**不会一启动就弹系统授权框**。点窗口里的「打开设置」才会触发系统授权提示并打开系统设置的对应页面；在 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制** 勾选 Liteshot。授权后窗口状态会自动变成「已授权」；如果仍然截不了，退出并重新打开 Liteshot。
3. 权限状态异常时可重置：

```bash
tccutil reset ScreenCapture com.redcarl.Liteshot
```

### 屏幕录制权限排查

- 授权对象必须是 **当前运行的 Liteshot.app 本身**，不是 Terminal、iTerm、IDE 或 DSH。
- 打开 系统设置 → 隐私与安全性 → 屏幕与系统音频录制，先移除旧的 Liteshot 条目，再用「+」添加当前 App（例如 `/Applications/Liteshot.app`）。
- 授权后必须完全退出并重启 App；权限弹窗里的「退出并重启」按钮会代劳。
- 从 v0.1.2 起构建产物会做 ad-hoc 签名，签名标识是 `com.redcarl.Liteshot`；更早的未签名构建可能无法把授权持久化，建议升级。
- 诊断当前 App 的权限状态：

```bash
/Applications/Liteshot.app/Contents/MacOS/Liteshot --permission
```

## 使用

| 操作 | 方式 |
|---|---|
| 开始截图 | 菜单栏图标「开始截图」或 ⌃⌘A：拖拽截区域，点击窗口直接截取，`C` 复制色值，Shift 正方形，方向键微调 |
| 顶部悬浮模式条 | 覆盖层顶部常驻：全屏截图、滚动截图、跨屏区域、延迟截图、上一次区域、OCR、二维码、截图历史；全部在悬浮条里，不占菜单 |
| 选区工具条 | 框选后直接在选区旁出现：矩形、椭圆、箭头、画笔、高亮、马赛克、序号、文字、6 色色板、撤销，以及复制、保存、钉图、滚动、OCR、关闭；不弹二级窗口 |
| 标注 | 选中工具后直接在选区上画，所见即所得；Enter / 双击 / ⌘C 复制并退出，⌘S 保存并退出，Esc 退出；拖动选区外可重新框选 |
| 滚动截图 | 顶部悬浮条「滚动截图」→ 覆盖层选竖向/横向/全景 → 拖区域或点窗口 → 滚动 → HUD（实时缩略图、开始滚动前可改方向、完成/取消） |
| 全屏截图 | 顶部悬浮条「全屏截图」→ 整屏选区 + 工具条；工具条贴在 Dock 上方，避开 MacBook 刘海 |
| 跨屏区域截图 | 顶部悬浮条「跨屏区域」→ 在任意屏幕拖拽（可跨屏）→ 合成一张图 |
| 延迟截图 | 顶部悬浮条「延迟截图」→ 按设置里的延迟秒数倒计时后截取 |
| 上一次区域 | 顶部悬浮条「上一次区域」→ 按上次区域直接截取；没有记录时退回框选 |
| 截图 OCR / 二维码 | 顶部悬浮条对应按钮 → 框选区域 → 结果窗口（结果窗口可上一个/下一个） |
| 钉图 | 菜单「贴图（从剪贴板）」或编辑器图钉按钮 |
| 截图历史 | 顶部悬浮条或菜单「截图历史」，可复制/打开/在 Finder 显示/清空 |
| 设置 / 语言 / 关于 | 菜单「设置…」「关于 Liteshot」 |

菜单栏现在只保留 App 级入口：开始截图、截图历史、贴图、隐藏/显示贴图、设置、屏幕录制权限、检查更新、关于、退出；截图模式全部在悬浮条里。

截图主流程不再打开独立编辑器窗口：框选、标注、复制/保存都在同一个覆盖层里完成，完成后直接回到原来的 App。

内联标注快捷键：

- `⌘C` 复制并退出、`⌘S` 保存并退出、`Esc` 取消
- `⌘Z` / `⇧⌘Z` 撤销 / 重做
- `Delete` 删除选中元素、方向键 1px 微调（Shift 10px）
- 文字：回车确认，`⇧回车` 换行，Esc 取消文字输入
- 双击选区 = 复制并退出

从「截图历史」或「上一张/下一张截图」打开的独立编辑器仍保留完整工具：`⌘C` 复制、`⌘S` 保存、`⌘O` 用其它 App 打开、`⌘W` 关闭、`⌘[` / `⌘]` 调整图层。

快捷键可在 设置 → 快捷键 里点击录制框重新绑定，立即生效并持久化。

## 自检

需要屏幕录制权限（采集类测试）：

```bash
./scripts/selftest.sh
```

包含 11 项：采集与剪贴板、命名保存、编辑器渲染、撤销/重做/图层、竖向滚动、横向滚动、全景、OCR/二维码、历史、取色、快捷键。

## 项目结构

```
Sources/
  App/          应用入口、菜单栏、关于页、自检
  Capture/      区域/窗口/全屏/滚动/跨屏采集与权限
  Scrolling/    竖向、横向、全景拼接器
  Editor/       标注模型、画布、渲染、编辑器窗口
  Output/       编码、命名模板、保存
  Vision/       OCR 与二维码
  Pin/          钉图
  History/      截图历史
  Settings/     设置窗口与快捷键录制
  Shared/       设置、L10n、取色、编码
Resources/      图标资源（Info.plist 由 XcodeGen 生成）
docs/           选型、规划、发布说明
scripts/        构建、运行、自检、（可选）发布
```

## 已知限制

- 滚动截图需要手动滚动；滚动过快会提示可能漏内容。
- 跨屏选区依赖所有目标屏处于活动状态；本机只在单活动屏上验证过退化路径。
- 更新检查只提供下载入口，不自动安装；更换版本后可能需要重新授权屏幕录制。
- 不包含录屏、屏幕测量、订阅功能（截图域之外）。

## 更新记录

见 [CHANGELOG.md](CHANGELOG.md)。

## 文档

- [功能规划](docs/功能规划.md)
- [技术选型](docs/技术选型.md)
- [环境准备](docs/环境准备.md)
- [发布](docs/发布.md)
- [交互对照](docs/交互对照.md) — 与参考产品的菜单/覆盖层/偏好差异清单
- [Tauri vs 原生](docs/Tauri-vs-原生.md)

## 许可证

[MIT](LICENSE) © 2026 RedCarl
