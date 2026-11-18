# App Store 上架合规清单

按 App Store Review Guidelines 和 Mac App Store 的硬性要求过了一遍代码、配置、图标和文案。本文记录改了什么、为什么改，以及还需要你配合的地方。

## 一、代码与配置（已完成）

| 项目 | 涉及条款 / 硬性要求 | 处理 |
|---|---|---|
| 应用内自更新（查 GitHub Release、下 zip、提示替换 app） | Guideline 2.5.2「不得下载、安装可执行代码」；Mac App Store 更新必须走 App Store | 删除 `UpdateChecker.swift`、`UpdateWindowController.swift`，去掉启动检查、菜单项和调试入口 |
| App Sandbox | Mac App Store 要求启用 App Sandbox | 新增 `Resources/Liteshot.entitlements`，`project.yml` 用 `CODE_SIGN_ENTITLEMENTS` 挂上 |
| 用户自选保存目录 | 沙盒下授权不跨启动 | 保存目录改用安全作用域书签，`SaveService` 写入前 `startAccessingSecurityScopedResource` |
| 默认保存目录 | 沙盒对标准目录的放行不一致 | 启动时真实试写 `~/Pictures/Liteshot`，写不进就退到 `~/Downloads/Liteshot`（容器里的 Downloads 是指向真实下载夹的符号链接）；已存路径失效时启动自愈 |
| 隐私清单 | 使用 required-reason API 必须声明 | `Resources/PrivacyInfo.xcprivacy`，声明 UserDefaults（CA92.1）与 FileTimestamp（C617.1），不追踪、不收集 |
| 应用类别 | 上架需有类别 | `LSApplicationCategoryType = public.app-category.productivity` |
| 文件夹用途说明 | 访问受保护目录需要用途字符串 | 补 `NSDownloadsFolderUsageDescription` / Desktop / Documents |
| 版权 | 元数据准确 | `NSHumanReadableCopyright = © 2026 孙磊` |
| 应用图标 | ITMS-90717：图标不得透明、不得含 alpha；macOS 26 非满幅图标会被系统「关进灰底图标监狱」 | 10 个尺寸全部重制为**不透明满幅**（RGB，无 alpha），由 `design/logo-apple-style/build_appstore_icons.py` 从透明原图可复现 |
| 发布包里的隐藏命令 | Guideline 2.3.1 不鼓励隐藏功能 | `--selftest*`、`--permission`、`--where` 等全部收进 `#if DEBUG`；Release 二进制里 `SELFTEST` 字样为 0 |
| 自检脚手架 | 沙盒下 `/tmp` 不可写，自检会假失败 | 路径改为容器内临时目录 |
| Bundle ID / 版本号 | — | `cn.carljoy.liteshot` / `0.4.0` |

### 网络

自更新删掉后，应用**不再发起任何网络请求**：没有 URLSession、没有第三方 SDK、没有统计和广告。可按「单机工具类应用」申报，也符合 Guideline 5.1.1。

## 二、已核对、没有问题的点

- **公开 API**：Carbon 热键、ScreenCaptureKit、Vision、`CGPreflightScreenCaptureAccess`，无私有符号。
- **不执行外部代码**：无 `Process`、`osascript`、`NSAppleScript`。
- **权限申请合规**：先显示自家引导页，用户点击后才触发系统 TCC，不在启动时弹窗。
- **无 IAP、无广告、无账号体系**，不涉及 3.1.1 / 1.2。
- **LSUIElement 菜单栏应用**：允许，Mac App Store 上同类工具在架。
- **Hardened Runtime + Universal（arm64/x86_64）**。
- **沙盒内实测**：11 项自检全过，含真实截屏（1920×1080）、滚动拼接、OCR、历史读写、编辑导出。

## 三、还需要你在 App Store Connect / Xcode 里做的

1. **签名**：Xcode 里选团队，勾 Automatically manage signing。不要再手动改 `Liteshot.entitlements`。
2. **新建 App**：Bundle ID `cn.carljoy.liteshot`，名称 `Liteshot`，主语言中文简体，类别「效率」或「生产力」。这个 ID 建了就不能改。
3. **隐私标签**：选「未收集数据」。
4. **出口合规**：不使用加密，选「否」。
5. **截图**：至少一组 16:10（如 2880×1800）。
6. **用团队签名跑一次保存验证**（见第四节第 2 条）。
7. **审核备注**（可直接粘）：

> Liteshot is a screenshot and annotation tool for macOS. It runs as a menu bar app (LSUIElement), so there is no Dock icon — after launch, click the scissors icon in the menu bar.
> Screen Recording permission is required for its only core function (screen capture). The app does not request it automatically: it shows its own guidance window first, and the system prompt only appears after the user taps "Open Settings".
> The app is fully offline: it makes no network requests, contains no analytics or ad SDKs, and collects no user data. OCR runs on-device with Vision; images never leave the Mac.
> Test steps: 1) launch, 2) menu bar → Start Capture (⌃⌘A), 3) drag a region, 4) press Enter to copy.

## 四、需要你配合验证的两件事

### 1. 图标外观确认
图标已从「圆角卡片 + 透明四角」改成「满幅渐变 + 剪刀」，这是 Apple 现在要求的形态（系统自己套 squircle）。旧的透明版保存在 `design/logo-apple-style/icon-transparent-original/`，随时可以回滚。

### 2. `~/Pictures` 权限要用真实签名复验
本机没有可用签名证书，只能用 ad-hoc 验证，结果：`downloads` 可写、`pictures` 被拒。所以沙盒下默认保存到 `~/Downloads/Liteshot`（正常可见，不是容器深处）。

请用你的团队签名在 Xcode 里 Run 一次，然后：

```bash
BIN="$(xcodebuild -project Liteshot.xcodeproj -scheme Liteshot -configuration Debug -showBuildSettings \
  | awk '/ BUILT_PRODUCTS_DIR/ {print $3; exit}')/Liteshot.app/Contents/MacOS/Liteshot"
"$BIN" --where
```

`--where` 是 Debug 专属诊断，会打印默认目录、当前保存目录、是否有书签、是否可写。

- 如果 `默认目录` 是 `~/Pictures/Liteshot` → 图片夹权限正常，不需要任何改动。
- 如果仍是 `~/Downloads/Liteshot` → 说明图片夹权限在正式签名下也不放行，那就维持下载夹作为默认，或者给「设置」加一次「选择保存位置」引导（书签机制已经就绪）。

把 `--where` 的输出贴给我，我按结果收尾。

## 五、仍然存在的判断项

1. **分发渠道已收拢到 App Store**：GitHub Releases 与 `release.yml` 已全部移除，仓库只保留源码，不再产出分发包。
2. **macOS 应用是否要 App 备案**仍待确认。应用现在完全不联网，属单机工具，按工信部口径不需要 App 备案。

## 六、签名证书与备案用的公钥/MD5

Xcode 26 之后，自动签名默认使用**云端托管证书**：私钥不在本机钥匙串里，
`security find-identity -p codesigning` 只看得到 Apple Development，看不到 Apple Distribution，
这是正常现象，不是失败。

本次实际使用的分发证书（从导出的 .pkg 里签名反查得到）：

| 项 | 值 |
|---|---|
| 证书 | `Apple Distribution: lei sun (BCRZR3P4AP)` |
| 团队 | `BCRZR3P4AP`（lea sun / Developer Team，Admin） |
| 有效期 | 2026-11-16 → 2027-11-16 |
| 序列号 | `0F27054496A80C5AA4C0D61EDC0989ED` |
| 签名 MD5 | `D8:6A:3A:27:33:74:31:B6:33:C7:25:80:F6:68:17:86` |
| 签名 SHA-1 | `1F:84:10:58:55:16:5D:7B:A2:8F:71:55:80:B1:00:43:65:82:4C:4B` |
| 公钥 | 见备案表第 47 行（Base64） |

公钥与 MD5 已填入备案表第 47、48 行。证书本体与备案表不入库（含个人信息），另存在本机 `~/Documents/Liteshot-备案私有/`。

要重新取这几个值（换证、换机器后）：

```bash
./scripts/app-store-cert-info.sh "某种已签名产物/Liteshot.app"
./scripts/app-store-cert-info.sh "Apple Distribution"     # 证书在钥匙串里时
```

**注意**：云端托管证书有效期一年，2027-11 续期后公钥和指纹都会变，
届时备案信息里的这两项要跟着更新，否则与实际签名对不上。
