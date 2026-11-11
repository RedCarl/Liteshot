import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            Form {
                Section(header: Text(tr("语言 / Language", "Language"))) {
                    Picker(selection: $settings.language) {
                        Text(tr("跟随系统", "System")).tag(AppLanguage.system)
                        Text("中文").tag(AppLanguage.chinese)
                        Text("English").tag(AppLanguage.english)
                    } label: {
                        Text(tr("界面语言", "Interface Language"))
                    }
                    .onChange(of: settings.language) { _, _ in
                        (NSApp.delegate as? AppDelegate)?.refreshLocalization()
                    }
                }

                Section(header: Text(tr("保存", "Saving"))) {
                    HStack(spacing: 8) {
                        Text(settings.saveDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(tr("选择…", "Choose…")) {
                            settings.chooseSaveDirectory()
                        }
                    }

                    Toggle(tr("自动保存", "Auto Save"), isOn: $settings.autoSave)
                    Toggle(tr("同时复制到剪贴板", "Also Copy to Clipboard"), isOn: $settings.copyToClipboard)
                    Toggle(tr("保存后在 Finder 中显示", "Reveal in Finder after Saving"), isOn: $settings.revealInFinder)

                    Picker(selection: $settings.format) {
                        ForEach(ImageFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    } label: {
                        Text(tr("格式", "Format"))
                    }
                    .pickerStyle(.segmented)

                    if settings.format == .jpeg {
                        HStack(spacing: 10) {
                            Text(tr("JPEG 质量", "JPEG Quality"))
                            Slider(value: $settings.jpegQuality, in: 0.1...1.0)
                            Text("\(Int(settings.jpegQuality * 100))%")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }

                Section(header: Text(tr("文件名", "File Name"))) {
                    TextField(tr("模板", "Template"), text: $settings.filenameTemplate)
                    Text(tr(
                        "可用：{yyyy} {yy} {MM} {dd} {HH} {mm} {ss} {SSS} {EEE} {EEEE} {a} {rand} {seq}",
                        "Tokens: {yyyy} {yy} {MM} {dd} {HH} {mm} {ss} {SSS} {EEE} {EEEE} {a} {rand} {seq}"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(header: Text(tr("导出", "Export"))) {
                    Toggle(tr("Retina 缩小到 1x", "Downscale Retina to 1x"), isOn: $settings.exportScale1x)
                    HStack(spacing: 10) {
                        Text(tr("圆角", "Corner Radius"))
                        Slider(
                            value: Binding(
                                get: { Double(settings.exportCornerRadius) },
                                set: { settings.exportCornerRadius = Int($0) }
                            ),
                            in: 0...40,
                            step: 2
                        )
                        Text("\(settings.exportCornerRadius) px")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    Toggle(tr("阴影", "Shadow"), isOn: $settings.exportShadow)
                    Toggle(tr("透明背景", "Transparent Background"), isOn: $settings.exportTransparent)
                    Text(tr(
                        "应用到编辑器和直接保存/复制的截图。",
                        "Applied to editor exports and direct save/copy."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(header: Text(tr("选区外观", "Selection Appearance"))) {
                    HStack(spacing: 10) {
                        Text(tr("遮罩透明度", "Mask Opacity"))
                        Slider(value: $settings.maskOpacity, in: 0.1...0.8)
                        Text("\(Int(settings.maskOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    ColorPicker(tr("高亮颜色", "Highlight Color"), selection: Binding(
                        get: {
                            Color(nsColor: NSColor(hex: settings.highlightColorHex) ?? .controlAccentColor)
                        },
                        set: { newValue in
                            settings.highlightColorHex = NSColor(newValue).hexString
                        }
                    ))
                }

                Section(header: Text(tr("快捷键", "Shortcuts"))) {
                    shortcutRow(tr("截图", "Capture"), shortcut: $settings.regionShortcut)
                    Text(tr(
                        "点击后按下新的组合键，至少包含一个修饰键；Esc 取消录制。",
                        "Click, then press a new shortcut with at least one modifier. Esc cancels."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(header: Text(tr("截图", "Capture"))) {
                    Toggle(tr("截图后进入标注编辑器", "Open Annotation Editor after Capture"), isOn: $settings.openEditorAfterCapture)
                    Text(tr(
                        "开启后自动保存不会立即执行，可在编辑器里复制或保存。",
                        "When enabled, auto save is deferred; copy or save from the editor."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Picker(selection: $settings.delaySeconds) {
                        Text(tr("不延迟", "No Delay")).tag(0)
                        Text(tr("3 秒", "3 seconds")).tag(3)
                        Text(tr("5 秒", "5 seconds")).tag(5)
                        Text(tr("10 秒", "10 seconds")).tag(10)
                    } label: {
                        Text(tr("延迟", "Delay"))
                    }

                    Toggle(tr("包含鼠标指针", "Include Mouse Cursor"), isOn: $settings.includeCursor)
                    Toggle(tr("显示放大镜与取色（C）", "Show Magnifier and Color Picker (C)"), isOn: $settings.showMagnifier)
                    Toggle(tr("边界吸附", "Snap to Window and Screen Edges"), isOn: $settings.snapToEdges)
                    Toggle(tr("OCR 保留文字换行", "Preserve OCR Line Breaks"), isOn: $settings.ocrPreserveNewlines)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .frame(width: 500)
        }
        .frame(width: 500, height: 720)
        .onChange(of: settings.regionShortcut) { _, _ in refreshHotKeys() }
    }

    private func tr(_ chinese: String, _ english: String) -> String {
        L10n.t(chinese, english)
    }

    private func shortcutRow(_ title: String, shortcut: Binding<HotkeyShortcut>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(shortcut: shortcut)
                .frame(width: 140, height: 24)
        }
    }

    private func refreshHotKeys() {
        (NSApp.delegate as? AppDelegate)?.refreshHotKeys()
    }
}
