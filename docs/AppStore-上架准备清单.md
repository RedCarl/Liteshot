# App Store 上架准备清单

备案已提交，这一份是按「离上架还差什么」排的顺序。每项标了谁来做。

## 一、已完成（无需再动）

| 项 | 状态 |
|---|---|
| Bundle ID `cn.carljoy.liteshot` | ✅ 已在 Apple 后台注册（随 provision profile 一起生成） |
| App Sandbox + 三项文件权限 | ✅ 已写进 entitlements，导出的 pkg 里验证通过 |
| 隐私清单 `PrivacyInfo.xcprivacy` | ✅ 已随包打包 |
| 图标（10 个尺寸，不透明满幅） | ✅ 已替换，符合 ITMS-90717 与 macOS 26 规范 |
| 移除自更新、应用完全不联网 | ✅ Release 二进制里无 http 字符串 |
| 编译产物签名 | ✅ `codesign --verify --deep --strict` 通过 |
| 归档 + 导出 App Store 包 | ✅ 已产出 `Liteshot.pkg`（0.4.0） |
| 备案材料 | ✅ 采集表已交 |

## 二、必须你来做（需要 Apple 账号 / 网页后台）

1. **App Store Connect 新建 App**
   - 平台：macOS；名称 `Liteshot`（若被占用，见下方备选）
   - 主要语言：简体中文；Bundle ID 选 `cn.carljoy.liteshot`
   - SKU：随意唯一值，如 `LITESHOT-MAC-001`
   - 类别：主要「效率」，次要「开发者工具」

2. **上传构建**：用 Transporter.app 或 Xcode Organizer 上传 `Liteshot.pkg`。上传会触发 App Store 端校验（图标 alpha、隐私清单、不可执行外部代码等），这是唯一能真正确认是否合规的环节。

3. **填商品信息**：把 `docs/AppStore-商品文案.md` 里的中文/英文文案贴进去。

4. **隐私标签**：全部选「未收集数据」（应用零网络请求、无 SDK、无追踪）。

5. **出口合规**：选「不使用加密算法」（没有网络、没有 CryptoKit）。

6. **审核备注**：用 `docs/AppStore-合规清单.md` 里那段英文说明。

7. **价格与区域**：定价（免费/付费）、上架区域（是否能在大陆区上架取决于备案结果）。

## 三、我可以继续做的

| 项 | 状态 |
|---|---|
| 截图套图 3 张 | ✅ 本机 `~/Documents/Liteshot-design-assets/docs/appstore/screenshots/`，2880×1800（PNG + JPEG 各一组），不入库 |
| 隐私政策 & 支持页 | ✅ `site/privacy.html`、`site/support.html`，链接已改成相对路径，任意域名可用 |
| 商品文案（中英） | ✅ `docs/AppStore-商品文案.md` |
| 站点发布 | ⬜ 需要把 `site/` 推到 GitHub Pages，隐私/支持链接才生效 |

### 截图清单

**上传用：营销版（左标题 / 右真机截图，同类应用的常见做法）**

| 文件 | 标题 | 内容 |
|---|---|---|
| `preview-01-capability-2880x1800` | 一站式 Mac 截图工具 | 框选 + 工具条 + 圆角/阴影样式条 |
| `preview-02-annotate-2880x1800` | 工具条就在选区旁边 | 选区角落 + 完整标注工具条特写 |
| `preview-03-output-2880x1800` | 输出随你定 | 设置窗口：保存目录 / 命名模板 / 导出 |

**备用：纯截图版**：`01-capture`、`02-toolbar-detail`、`03-settings`。

文案要改就直接改 `docs/appstore/compose_preview.py` 里的标题和条目，重跑一次即可：

```bash
cd docs/appstore && python3 compose_preview.py
```

上传时优先用 JPEG（都小于 1 MB），PNG 原图留档。

## 四、卡点提醒

- **上传必须在第二步之后**：没有 App 记录，Transporter 无处可传。
- **备案结果影响大陆区上架**：审核通过前建议先只在其他区域上线，或等备案号下来再一并提交。
- **名称占用风险**：`Liteshot` 若已被占用，备选 `Liteshot 截图`、`Liteshot · 截图标注`。

## 五、命名与 URL

| 字段 | 值 |
|---|---|
| 支持 URL | `https://redcarl.github.io/Liteshot/support.html` |
| 隐私政策 URL | `https://redcarl.github.io/Liteshot/privacy.html` |
| 营销 URL | `https://redcarl.github.io/Liteshot/` |
| 版权 | `© 2026 孙磊` |
