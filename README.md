# Liteshot

轻量原生的 macOS 截图与标注工具：菜单栏常驻，专注区域 / 窗口 / 全屏截图、滚动截图与标注。
原生 Swift + AppKit/SwiftUI，MIT 开源，本地构建自用，不依赖 App Store。

> **状态**：截图域功能已完成（M1–M5）。开源发布，不要求上架、Developer ID 签名或公证。
> 未签名的本地构建可以直接使用；Sparkle 已接入但 `SUFeedURL` 是占位值，「检查更新」报错属预期。

## 功能

- **捕获**：区域（放大镜、取色、边界吸附、Shift 正方形、方向键微调）、窗口（Shift 多选合成）、全屏、活动窗口、上次区域、延迟、跨屏区域
- **滚动截图**：竖向、横向、全景（横竖同时）；HUD 完成/取消
- **标注编辑器**：矩形、椭圆、箭头、线条、画笔、高亮、区域高亮、马赛克（水晶/高斯/六边形）、文字、序号、水印、插入图片；撤销重做、图层、持久化样式、像素级导出
- **输出**：PNG/JPEG、自动保存、文件名模板、剪贴板、圆角/阴影/透明背景、Retina 缩小
- **效率**：OCR 与二维码（Vision 本地识别）、钉图、截图历史（最多 50 张）、全局快捷键自定义
- **其他**：中英双语、菜单栏常驻、Sparkle 更新框架

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

## 首次使用

1. 启动后只有菜单栏图标（`LSUIElement`，不占 Dock）。
2. 按任意截图快捷键，按提示到 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制** 勾选 Liteshot；授权后可能需要重启应用。
3. 权限状态异常时可重置：

```bash
tccutil reset ScreenCapture com.redcarl.Liteshot
```

## 使用

| 操作 | 方式 |
|---|---|
| 区域截图 | ⌃⌘A（放大镜跟随光标，`C` 复制色值，Shift 锁定正方形，方向键微调，选区吸附窗口/屏幕边缘） |
| 窗口选择 | ⌃⌘W（悬停高亮，点击捕获；Shift 多选后 Enter 合成，Esc/右键取消） |
| 全屏截图 | ⌃⌘S |
| 活动窗口 / 上次区域 / 延迟截图 | 菜单栏相机图标；延迟倒计时后自动截上次区域，没有则全屏 |
| 滚动截图（竖向） | 菜单「滚动截图」→ 框选区域 → 滚动页面 → HUD「完成」 |
| 滚动截图（横向） | 菜单「滚动截图（横向）」→ 框选区域 → 左右滚动 → HUD「完成」 |
| 全景滚动截图 | 菜单「全景滚动截图」→ 框选区域 → 任意方向滚动 → HUD「完成」 |
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
- 未签名构建无法通过 Sparkle 自更新；`SUFeedURL`/`SUPublicEDKey` 为占位值。
- 不包含录屏、屏幕测量、订阅功能（截图域之外）。

## 许可证

[MIT](LICENSE) © 2026 RedCarl
