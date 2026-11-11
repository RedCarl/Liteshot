import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorViewController: NSViewController {
    private let image: CGImage
    private let document = EditorDocument()
    private let canvas: EditorCanvasView

    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider(value: 4, minValue: 1, maxValue: 30, target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "4")
    private let fontSizeField = NSTextField(string: "28")
    private let mosaicPopup = NSPopUpButton()
    private let alignmentPopup = NSPopUpButton()
    private let watermarkToggle = NSButton()
    private let undoButton = NSButton(title: "", target: nil, action: nil)
    private let redoButton = NSButton(title: "", target: nil, action: nil)

    private var currentTool: AnnotationTool = .select

    init(image: CGImage) {
        self.image = image
        self.canvas = EditorCanvasView(image: image, document: document)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        let toolbar = makeToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(canvas)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        document.onChange = { [weak self] in
            self?.canvas.needsDisplay = true
            self?.updateUndoButtons()
        }
        canvas.onChange = { [weak self] in
            self?.updateUndoButtons()
        }
        updateUndoButtons()
        setTool(.select)
        updateWindowTitle()
    }

    // MARK: - Toolbar

    private func makeToolbar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        for tool in AnnotationTool.allCases where tool != .image && tool != .watermark {
            let button = NSButton()
            button.image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)
            button.bezelStyle = .texturedRounded
            button.setButtonType(.toggle)
            button.target = self
            button.action = #selector(toolClicked(_:))
            button.tag = AnnotationTool.allCases.firstIndex(of: tool) ?? 0
            button.toolTip = tool.title
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }

        mosaicPopup.addItems(withTitles: [
            L10n.t("水晶马赛克", "Crystal Mosaic"),
            L10n.t("高斯模糊", "Gaussian Blur"),
            L10n.t("六边形马赛克", "Hexagon Mosaic"),
        ])
        mosaicPopup.target = self
        mosaicPopup.action = #selector(mosaicAlgorithmChanged)
        mosaicPopup.isHidden = true
        mosaicPopup.translatesAutoresizingMaskIntoConstraints = false
        mosaicPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(mosaicPopup)

        stack.addArrangedSubview(makeSeparator())

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        stack.addArrangedSubview(colorWell)

        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.widthAnchor.constraint(equalToConstant: 84).isActive = true
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        stack.addArrangedSubview(widthSlider)

        widthLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        widthLabel.textColor = .secondaryLabelColor
        widthLabel.translatesAutoresizingMaskIntoConstraints = false
        widthLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true
        stack.addArrangedSubview(widthLabel)

        let fontLabel = NSTextField(labelWithString: L10n.t("字号", "Size"))
        fontLabel.font = .systemFont(ofSize: 11)
        fontLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(fontLabel)

        fontSizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 38).isActive = true
        fontSizeField.target = self
        fontSizeField.action = #selector(fontSizeChanged)
        stack.addArrangedSubview(fontSizeField)

        alignmentPopup.addItems(withTitles: [L10n.t("左", "Left"), L10n.t("中", "Center"), L10n.t("右", "Right")])
        alignmentPopup.target = self
        alignmentPopup.action = #selector(alignmentChanged)
        alignmentPopup.isHidden = true
        alignmentPopup.translatesAutoresizingMaskIntoConstraints = false
        alignmentPopup.widthAnchor.constraint(equalToConstant: 58).isActive = true
        stack.addArrangedSubview(alignmentPopup)

        watermarkToggle.title = L10n.t("水印", "Watermark")
        watermarkToggle.setButtonType(.toggle)
        watermarkToggle.bezelStyle = .texturedRounded
        watermarkToggle.target = self
        watermarkToggle.action = #selector(watermarkToggled)
        watermarkToggle.toolTip = L10n.t("把文字平铺成整图水印", "Tile the text as a watermark")
        watermarkToggle.isHidden = true
        watermarkToggle.translatesAutoresizingMaskIntoConstraints = false
        watermarkToggle.widthAnchor.constraint(equalToConstant: 50).isActive = true
        watermarkToggle.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(watermarkToggle)

        stack.addArrangedSubview(makeSeparator())

        configure(button: undoButton, symbol: "arrow.uturn.backward", tooltip: L10n.t("撤销 ⌘Z", "Undo ⌘Z"), action: #selector(undo))
        undoButton.keyEquivalent = "z"
        undoButton.keyEquivalentModifierMask = [.command]
        stack.addArrangedSubview(undoButton)

        configure(button: redoButton, symbol: "arrow.uturn.forward", tooltip: L10n.t("重做 ⇧⌘Z", "Redo ⇧⌘Z"), action: #selector(redo))
        redoButton.keyEquivalent = "z"
        redoButton.keyEquivalentModifierMask = [.command, .shift]
        stack.addArrangedSubview(redoButton)

        let backwardButton = NSButton()
        configure(button: backwardButton, symbol: "square.2.layers.3d.bottom.filled", tooltip: L10n.t("下移一层 ⌘[", "Send Backward ⌘["), action: #selector(sendBackward))
        backwardButton.keyEquivalent = "["
        backwardButton.keyEquivalentModifierMask = [.command]
        stack.addArrangedSubview(backwardButton)

        let forwardButton = NSButton()
        configure(button: forwardButton, symbol: "square.2.layers.3d.top.filled", tooltip: L10n.t("上移一层 ⌘]", "Bring Forward ⌘]"), action: #selector(bringForward))
        forwardButton.keyEquivalent = "]"
        forwardButton.keyEquivalentModifierMask = [.command]
        stack.addArrangedSubview(forwardButton)

        let photoButton = NSButton()
        configure(button: photoButton, symbol: "photo.badge.plus", tooltip: L10n.t("插入图片", "Insert Image"), action: #selector(insertImage))
        stack.addArrangedSubview(photoButton)

        let ocrButton = NSButton()
        configure(button: ocrButton, symbol: "text.viewfinder", tooltip: L10n.t("OCR 识别", "OCR"), action: #selector(runOCR))
        stack.addArrangedSubview(ocrButton)

        let qrButton = NSButton()
        configure(button: qrButton, symbol: "qrcode", tooltip: L10n.t("二维码 / 条形码", "QR / Barcode"), action: #selector(runBarcode))
        stack.addArrangedSubview(qrButton)

        let pinButton = NSButton()
        configure(button: pinButton, symbol: "pin", tooltip: L10n.t("钉图（浮动贴图）", "Pin as Floating Image"), action: #selector(pinImage))
        stack.addArrangedSubview(pinButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)

        let copyButton = NSButton(title: L10n.t("复制", "Copy"), target: self, action: #selector(copyImage))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command]
        stack.addArrangedSubview(copyButton)

        let saveButton = NSButton(title: L10n.t("保存", "Save"), target: self, action: #selector(saveImage))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        stack.addArrangedSubview(saveButton)

        let closeButton = NSButton(title: L10n.t("关闭", "Close"), target: self, action: #selector(closeEditor))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "w"
        closeButton.keyEquivalentModifierMask = [.command]
        stack.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
    }

    private func configure(button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return separator
    }

    // MARK: - Actions

    @objc private func toolClicked(_ sender: NSButton) {
        let tools = AnnotationTool.allCases
        guard tools.indices.contains(sender.tag) else { return }
        setTool(tools[sender.tag])
    }

    private func setTool(_ tool: AnnotationTool) {
        canvas.commitPendingText()
        currentTool = tool
        canvas.tool = tool
        canvas.select(id: nil)

        for (buttonTool, button) in toolButtons {
            button.state = buttonTool == tool ? .on : .off
        }

        let style = ToolStyleStore.style(for: tool)
        apply(style: style, to: tool)
        mosaicPopup.isHidden = tool != .mosaic
        alignmentPopup.isHidden = tool != .text
        watermarkToggle.isHidden = tool != .text
        widthSlider.minValue = tool == .text ? 0 : 1
    }

    private func apply(style: ToolStyle, to tool: AnnotationTool) {
        colorWell.color = style.color
        widthSlider.doubleValue = style.lineWidth
        widthLabel.stringValue = "\(Int(style.lineWidth))"
        fontSizeField.stringValue = "\(Int(style.fontSize))"
        canvas.currentStyle = style

        let enabled = tool.isDrawingTool
        colorWell.isEnabled = enabled
        widthSlider.isEnabled = enabled
        fontSizeField.isEnabled = tool == .text
        widthLabel.textColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
    }

    @objc private func colorChanged() {
        updateStyleFromControls()
    }

    @objc private func widthChanged() {
        widthLabel.stringValue = "\(Int(widthSlider.doubleValue))"
        updateStyleFromControls()
    }

    @objc private func fontSizeChanged() {
        updateStyleFromControls()
    }

    private func updateStyleFromControls() {
        guard currentTool.isDrawingTool else { return }

        var style = ToolStyleStore.style(for: currentTool)
        style.colorHex = colorWell.color.hexString
        style.lineWidth = widthSlider.doubleValue
        if let size = Double(fontSizeField.stringValue) {
            style.fontSize = max(8, min(120, size))
        }
        ToolStyleStore.save(style, for: currentTool)
        canvas.currentStyle = style

        if let selectedID = canvas.selectedID,
           var annotation = document.annotations.first(where: { $0.id == selectedID }) {
            annotation.style = style
            document.replace(annotation)
            canvas.refresh()
        }
    }

    @objc private func watermarkToggled() {
        canvas.textAsWatermark = watermarkToggle.state == .on
    }

    @objc private func alignmentChanged() {
        let values = ["left", "center", "right"]
        let index = max(0, min(alignmentPopup.indexOfSelectedItem, values.count - 1))
        canvas.textAlignment = values[index]

        if let selectedID = canvas.selectedID,
           var annotation = document.annotations.first(where: { $0.id == selectedID }),
           annotation.tool == .text {
            annotation.textAlignment = values[index]
            document.replace(annotation)
            canvas.refresh()
        }
    }

    @objc private func pinImage() {
        guard let rendered = EditorRenderer.render(
            image: image,
            annotations: document.annotations,
            options: exportOptions
        ) else { return }
        PinManager.shared.pin(rendered)
    }

    @objc private func runOCR() {
        do {
            let text = try OCRService.recognizeText(in: image)
            OCRResultWindowController.shared.show(title: L10n.t("OCR 结果", "OCR Result"), text: text)
        } catch {
            showRecognitionError(error)
        }
    }

    @objc private func runBarcode() {
        do {
            let payloads = try OCRService.recognizeBarcodes(in: image)
            OCRResultWindowController.shared.show(
                title: L10n.t("二维码 / 条形码", "QR / Barcode"),
                text: payloads.joined(separator: "\n")
            )
        } catch {
            showRecognitionError(error)
        }
    }

    private func showRecognitionError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.t("识别失败", "Recognition Failed")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.t("好", "OK"))
        alert.runModal()
    }

    @objc private func mosaicAlgorithmChanged() {
        let values = ["crystal", "gaussian", "hex"]
        let index = max(0, min(mosaicPopup.indexOfSelectedItem, values.count - 1))
        canvas.mosaicAlgorithm = values[index]
    }

    @objc private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let data = try? Data(contentsOf: url),
              let nsImage = NSImage(data: data),
              nsImage.size.width > 0, nsImage.size.height > 0 else {
            return
        }

        let maxWidth = CGFloat(image.width) * 0.4
        let scale = min(1, maxWidth / nsImage.size.width)
        let size = CGSize(width: nsImage.size.width * scale, height: nsImage.size.height * scale)
        let center = CGPoint(x: CGFloat(image.width) / 2, y: CGFloat(image.height) / 2)
        var annotation = Annotation(
            tool: .image,
            start: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            end: CGPoint(x: center.x + size.width / 2, y: center.y + size.height / 2),
            style: canvas.currentStyle
        )
        annotation.imageData = data
        document.add(annotation)
        canvas.select(id: annotation.id)
    }

    @objc private func bringForward() {
        guard let id = canvas.selectedID else { return }
        document.bringForward(id: id)
        canvas.refresh()
    }

    @objc private func sendBackward() {
        guard let id = canvas.selectedID else { return }
        document.sendBackward(id: id)
        canvas.refresh()
    }

    @objc private func undo() {
        document.undo()
        canvas.select(id: nil)
    }

    @objc private func redo() {
        document.redo()
        canvas.select(id: nil)
    }

    @objc private func copyImage() {
        guard let rendered = EditorRenderer.render(
            image: image,
            annotations: document.annotations,
            options: exportOptions
        ) else {
            return
        }
        ClipboardService.copy(image: rendered)
        NSSound(named: "Glass")?.play()
        flashTitle(L10n.t("已复制到剪贴板", "Copied to clipboard"))
    }

    @objc private func saveImage() {
        guard let rendered = EditorRenderer.render(
            image: image,
            annotations: document.annotations,
            options: exportOptions
        ) else {
            return
        }
        let settings = AppSettings.shared
        do {
            let url = try SaveService.save(
                image: rendered,
                to: settings.saveDirectory,
                format: settings.format,
                quality: settings.jpegQuality,
                template: settings.filenameTemplate
            )
            if settings.revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            flashTitle(L10n.t("已保存", "Saved") + " \(url.lastPathComponent)")
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = L10n.t("保存失败", "Save Failed")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.t("好", "OK"))
            alert.runModal()
        }
    }

    @objc private func closeEditor() {
        view.window?.performClose(nil)
    }

    private var exportOptions: ExportOptions {
        let settings = AppSettings.shared
        return ExportOptions(
            scale: settings.exportScale1x ? 0.5 : 1,
            cornerRadius: CGFloat(settings.exportCornerRadius),
            shadow: settings.exportShadow,
            shadowBlur: CGFloat(settings.exportShadowBlur),
            shadowOpacity: settings.exportShadowOpacity,
            transparent: settings.exportTransparent
        )
    }

    // MARK: - State

    private func updateUndoButtons() {
        undoButton.isEnabled = document.canUndo
        redoButton.isEnabled = document.canRedo
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        view.window?.title = L10n.t("Liteshot 编辑器", "Liteshot Editor") + " · \(image.width)×\(image.height)"
    }

    private func flashTitle(_ message: String) {
        let original = L10n.t("Liteshot 编辑器", "Liteshot Editor") + " · \(image.width)×\(image.height)"
        view.window?.title = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if view.window?.title == message {
                view.window?.title = original
            }
        }
    }
}
