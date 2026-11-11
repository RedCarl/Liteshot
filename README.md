# Liteshot

[![Build](https://github.com/RedCarl/Liteshot/actions/workflows/build.yml/badge.svg)](https://github.com/RedCarl/Liteshot/actions/workflows/build.yml)
[![Release](https://github.com/RedCarl/Liteshot/actions/workflows/release.yml/badge.svg)](https://github.com/RedCarl/Liteshot/actions/workflows/release.yml)

轻量原生的 macOS 截图与标注工具：菜单栏常驻，专注区域 / 窗口 / 全屏截图、滚动截图与标注。
原生 Swift + AppKit/SwiftUI，MIT 开源，本地构建自用，不依赖 App Store。

> **状态**：截图域功能已完成（M1–M5）。开源发布，不要求上架、Developer ID 签名或公证。
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
2. 按任意截图快捷键，按提示到 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制** 勾选 Liteshot；授权后可能需要重启应用。
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
| 截图（自适应） | 菜单「截图」或 ⌃⌘A：悬停高亮窗口，点击截窗口，拖拽截区域，点空白/按 F 截全屏；`C` 复制色值，Shift 正方形，方向键微调 |
| 滚动截图 | 菜单「滚动截图」子菜单：竖向 / 横向 / 全景 → 框选区域 → 滚动 → HUD「完成」 |
| 更多截图 | 子菜单：全屏、活动窗口、上次区域、延迟、跨屏区域 |
| 跨屏区域截图 | 菜单「跨屏区域截图」→ 在任意屏幕拖拽（可跨屏）→ 合成一张图 |
| 截图 OCR / 二维码 | 菜单对应项 → 框选区域 → 结果窗口 |
| 钉图 | 菜单「贴图（从剪贴板）」或编辑器图钉按钮 |
| 截图历史 | 菜单「截图历史」，可复制/打开/在 Finder 显示/清空 |
| 设置 / 语言 / 关于 | 菜单「设置…」「关于 Liteshot」 |

截图后默认打开标注编辑器（可在设置里关闭）。编辑器快捷键：

- `⌘C` 复制、`⌘S` 保存、`⌘W` 关闭
- `⌘Z` / `⇧⌘Z` 撤销 / 重做
- `Delete` 删除选中、方向键 1px 微调（Shift 10px）
- `⌘[` / `⌘]` 下移 / 上移图层
- 文字：回车确认，`⇧回车` 换行，Esc 取消

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

## 许可证

[MIT](LICENSE) © 2026 RedCarl
