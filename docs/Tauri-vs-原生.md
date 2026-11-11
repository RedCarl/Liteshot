# Tauri vs 原生：Liteshot 该怎么选

> 结论先行：**做 macOS 截图工具，原生 Swift 的差距是“少写一层平台胶水”；Tauri 的差距是“把这一层用 Rust 重写一遍”。**
> 本文的数字，标注“实测”的来自本机（macOS 26.6.2 / macOS 26.1 SDK / 3 台显示器），其余为工程估算。

---

## 1. 先看三个实测数字

| 采集路径 | 实测结果 | 说明 |
|---|---|---|
| `screencapture` CLI | **210–240 ms/次**，3.1 MB PNG（3600×2338，三屏拼接） | 每次拉起一个进程，拿不到实时帧 |
| ScreenCaptureKit（Swift 直调） | **首帧 125 ms，热态 41 ms**（1920×1080 单显示器） | 系统一等公民 API，macOS 14+ |
| `CGWindowListCreateImage`（xcap 0.9.10 用的） | **无法用 Swift 编译**：SDK 26 中标记为 `obsoleted(15.0)` | Rust 自己声明符号能编译，但 Apple 已不保证运行时行为 |

第三条是关键：**Tauri 生态里最常用的截图 crate（xcap，285 万下载）在 macOS 15+ 上走的还是被 Apple 废弃的 API**。它今天大概率还能跑（Rust 绕过 SDK 标注），但这是“没人在维护那扇门”的状态。真要在 Tauri 里做对，得换 `screencapturekit` crate（3.4M 下载，2026-11 仍更新）——也就是直接绑 ScreenCaptureKit。

---

## 2. 逐项差距

图例：🟢 原生顺手 / 🟡 能做但要下到平台层 / 🔴 明显吃亏

| 能力 | 原生 Swift | Tauri 2 | 判断 |
|---|---|---|---|
| 全屏/区域采集 | `SCScreenshotManager` 一行 | `screencapturekit` crate 可用；`xcap` 走废弃 API | 🟡 |
| 窗口枚举/窗口截图 | `SCShareableContent` 直接给 `SCWindow` | 同上 crate，但窗口标题、层级、阴影都要自己补 | 🟡 |
| 选区覆盖层 | `NSWindow` + `level = .screenSaver` + 自绘 | 透明窗口可建，`always_on_top` 只到 floating 层级；要覆盖全屏 App 得 `ns_window()` + `msg_send` 设 level / `fullScreenAuxiliary` | 🔴 |
| 放大镜/取色 | 预抓帧内存直读，零拷贝 | 帧要么走自定义协议给 WebView，要么在 Rust 侧画完再传；取色还要处理色彩空间（P3→sRGB） | 🟡 |
| 标注编辑器 | AppKit 画布，全自己写（约 6–10 天） | Konva/Fabric 画布，2–4 天出效果，是 Tauri 最舒服的部分 | 🟢（Tauri 赢） |
| 文字标注 | `NSAttributedString`，中文排版/描边现成 | Canvas 文字排版要自己处理换行、描边、光标 | 🟡 |
| OCR | Vision 三行 | `objc2-vision` 绑 Vision，约 1–2 天跑通；或塞 Swift 小工具（多一套构建） | 🟡 |
| 二维码 | Vision 一行 | 同上 | 🟡 |
| 滚动截图 | `SCStream` + `vDSP` 拼接，全在掌控内 | Rust 侧 SCStream 回调 + 帧拷贝，或 Swift 边车；这块最容易卡死 | 🔴 |
| 全局快捷键 | `KeyboardShortcuts`（Carbon，无需辅助功能权限） | `tauri-plugin-global-shortcut`（同一个 Carbon 后端），基本等价 | 🟢 |
| 菜单栏常驻 | `NSStatusItem`，成熟 | Tauri tray + 菜单，能用；自定义弹出面板受限 | 🟡 |
| 屏幕录制权限 | `CGPreflightScreenCaptureAccess` + 引导页 | 同样能调；`tauri dev` 的临时二进制每次重建可能重置 TCC 授权，开发体验更烦 | 🟡 |
| 包体积 | 约 3–8 MB（估） | 约 10–20 MB（Rust + 前端资源，WKWebView 用系统的） | 🟢（原生略胜，不致命） |
| 冷启动 | 约 100–300 ms（估） | 多一次 WebView 进程启动，约 300–700 ms（估） | 🟡 |
| 签名/公证 | Xcode 一条龙 | `tauri build` + codesign + notarytool，脚本化也可 | 🟡 |
| Mac App Store | 可以（部分商业截图工具即如此） | 历史上因透明窗口私有 API 有风险；2.12.1 后该开关变 no-op，但仍是灰色地带 | 🔴 |
| Windows/Linux | 基本重写 | 采集换后端，UI 复用 | 🟢（Tauri 赢） |

---

## 3. 三个隐性成本（比表格更重要）

### 3.1 “覆盖层”不是画个 div 就完了

截图工具的体验分水岭在选区覆盖层：跨屏、全屏 App 之上、菜单栏之下、鼠标事件、Retina 坐标、实时放大镜。Tauri 给你的窗口抽象是“应用窗口”，而截图工具要的是“系统级遮罩”。

- Tauri 能建透明无边框窗口，`always_on_top` 映射到 `NSFloatingWindowLevel`（3）。
- 覆盖菜单栏/全屏 App 需要 `.screenSaver`（1000）+ `fullScreenAuxiliary`，Tauri 不暴露，得拿 `ns_window()` 指针手写 Objective-C 消息。
- 这段 unsafe Rust 不难（约 20 行），但它就是“原生代码”，而且散落在 Rust 里，调试靠猜。

### 3.2 一帧截图在 Tauri 里要跨三次边界

原生：`CGImage` 在内存里，放大镜、裁剪、标注、导出都是指针传递。

Tauri：Rust 采集 → 序列化/落盘 → 自定义协议 → WebView 解码 → Canvas 绘制。3600×2338 的一帧解码后约 34 MB，Rust 和 WebView 各一份。用 `asset://` 自定义协议能避免 base64 膨胀，但坐标换算、色彩空间、DPR 都要自己对齐。

### 3.3 生态碎片化风险是持续的

xcap 至今（2026-11）仍在用 macOS 15 就废弃的 API，就是一个缩影。Tauri 的 macOS 能力依赖社区 crate 和 `objc2` 绑定，Apple 一变（比如 26 的 Liquid Glass、新的权限弹窗），原生社区当天适配，Rust 绑定要等。截图工具偏偏重度依赖这些系统 API。

---

## 4. Tauri 的真实优势

别只看劣势，Tauri 在三个地方确实更快：

1. **标注编辑器**：Canvas + Konva 做形状、文字、拖拽手柄，比 AppKit 自绘快 2–3 倍；UI 审美和动效也更容易出效果。
2. **设置页/历史页**：Web 技术栈迭代速度碾压 SwiftUI 表单。
3. **跨平台**：如果 Liteshot 以后要 Windows，Tauri 至少能复用 UI 和业务逻辑；原生要重写整个界面。

如果 Liteshot 的定位是“截图后重度编辑”，且你有前端积累，Tauri 的性价比会上升；如果定位是“快、稳、系统级”，原生赢。

---

## 5. 工作量估算（单人，熟悉对应技术栈）

| 版本 | 原生 Swift | Tauri 2 |
|---|---|---|
| 最小闭环（区域截图→剪贴板） | 3–5 天 | 5–8 天（Rust/objc 采集 + 覆盖层 + 权限） |
| v0.1（+窗口/全屏/延迟/保存/六种标注） | 15–25 天 | 25–40 天 |
| v0.2（+OCR/历史/设置） | +7–10 天 | +8–12 天 |
| 滚动截图 | +7–12 天 | +15–25 天（或被迫写 Swift 边车） |

注意：这个差距**不是**“Tauri 难”，而是“截图工具 60% 的复杂度在平台层，Tauri 让这 60% 从 Swift 变成了 unsafe Rust + 额外 IPC”。如果你本来就熟 Rust 和 objc2，差距会缩小到 20–30%；如果只熟前端，差距会更大。

---

## 6. 决策规则

```
只要 macOS、且截图是核心体验？
├── 是 → 原生 Swift（推荐）
│        理由：采集/覆盖层/权限/OCR/滚动全在一条链上，维护成本最低
└── 否 → 未来 12 个月要有 Windows 版？
          ├── 是 → Tauri 2（Rust 核心 + WebView UI），采集用平台原生层
          └── 否 → 回到原生
```

补充两条：

- **要上 Mac App Store** → 原生。Tauri 的透明窗口/全屏行为历史上有私有 API 争议，过审是赌博。
- **团队只有前端**，且能接受“截图性能一般、覆盖层用浮动层级” → Tauri 可行，但别指望它“一次编写到处运行”。

---

## 7. 如果最后还是选 Tauri，架构应该这样

```
src-tauri/
  capture/    screencapturekit crate 采集 + 窗口枚举 + 权限
  overlay/    每屏一个透明窗口；ns_window() 设 level；自定义协议喂帧
  vision/     objc2-vision 跑 OCR/二维码（别上 Tesseract，中文差）
  export/     image-rs 编码；或把 CGImage 直接交给前端 Canvas 导出
src/
  overlay/    Canvas 选区 + 放大镜（<img> + transform，性能足够）
  editor/     Konva 标注画布
  settings/   常规 Web UI
```

关键取舍：**不要试图用 `screencapture` CLI 上生产**（200ms+、无实时帧、无窗口阴影控制）；也不要用 xcap 赌废弃 API。

---

## 8. 对 Liteshot 的建议

Liteshot 的定位是轻量原生截图工具：区域/窗口/全屏 + 基础标注 + 快。这个定位下：

- **核心体验**（唤起速度、选区跟手、Retina 精度、多屏、权限引导）全部由原生层决定；
- **编辑体验**只占三分之一，且 v0.1 只要六种工具；
- **跨平台**不是当前需求。

所以：**选原生 Swift**。Tauri 的优势（标注 UI、设置页）在 v0.2 之后才会显现，而它的成本（覆盖层、IPC、TCC、滚动截图）从第一天就要付。

如果你确实想要 Web 的编辑体验，折中方案是：**原生负责采集、覆盖层、权限、OCR；编辑窗口用 WebView 承载**（WKWebView + 本地 HTML，原生 ↔ JS 通过 `evaluateJavaScript` 传图片路径）。这样两头的好处都拿到，代价是两套渲染栈——但比全 Tauri 便宜得多。
