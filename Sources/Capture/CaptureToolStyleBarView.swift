import AppKit

/// 工具条下方的第二行：粗细/字号 + 颜色。
@MainActor
final class CaptureToolStyleBarView: NSView {
    var onWidthChanged: ((CGFloat) -> Void)?
    var onColorTapped: ((NSButton) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 4, minValue: 1, maxValue: 24, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "4")
    private let colorButton = ColorMenuButton(frame: .zero)
    private var isTextTool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 0.94).cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.isBordered = false
        valueLabel.isEditable = false
        valueLabel.drawsBackground = false

        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged)

        colorButton.target = self
        colorButton.action = #selector(colorTapped)

        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)
        addSubview(colorButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        titleLabel.frame = CGRect(x: 10, y: (34 - 16) / 2, width: 30, height: 16)
        slider.frame = CGRect(x: 44, y: (34 - 20) / 2, width: 120, height: 20)
        valueLabel.frame = CGRect(x: 168, y: (34 - 16) / 2, width: 26, height: 16)
        colorButton.frame = CGRect(x: 200, y: (34 - 22) / 2, width: 40, height: 22)
    }

    func update(tool: AnnotationTool, style: ToolStyle) {
        isTextTool = tool == .text
        titleLabel.stringValue = isTextTool ? L10n.t("字号", "Size") : L10n.t("粗细", "Width")
        slider.minValue = isTextTool ? 12 : 1
        slider.maxValue = isTextTool ? 72 : 24
        let value = isTextTool ? style.fontSize : style.lineWidth
        slider.doubleValue = value
        valueLabel.stringValue = "\(Int(value))"
        colorButton.swatchColor = style.color
        slider.toolTip = isTextTool
            ? L10n.t("文字字号", "Text size")
            : L10n.t("线条 / 边框粗细", "Line width")
        colorButton.toolTip = L10n.t("颜色", "Color")
    }

    @objc private func sliderChanged() {
        let value = CGFloat(slider.doubleValue.rounded())
        valueLabel.stringValue = "\(Int(value))"
        onWidthChanged?(value)
    }

    @objc private func colorTapped() {
        onColorTapped?(colorButton)
    }
}

/// 颜色方块 + 下拉箭头；点击由截图层弹出颜色菜单。
@MainActor
final class ColorMenuButton: NSButton {
    var swatchColor: NSColor = .systemRed {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let square = NSRect(x: 4, y: (bounds.height - 18) / 2, width: 18, height: 18)
        let path = NSBezierPath(roundedRect: square, xRadius: 4, yRadius: 4)
        swatchColor.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()

        let chevron = NSBezierPath()
        chevron.move(to: CGPoint(x: 28, y: bounds.midY + 2))
        chevron.line(to: CGPoint(x: 31.5, y: bounds.midY - 2))
        chevron.line(to: CGPoint(x: 35, y: bounds.midY + 2))
        NSColor.white.withAlphaComponent(0.9).setStroke()
        chevron.lineWidth = 1.6
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()
    }
}

/// 自定义 hover 提示；不拦截鼠标事件。
@MainActor
final class HoverTipView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(
            x: 0,
            y: 0,
            width: min(bounds.width, size.width + 16),
            height: min(bounds.height, size.height + 8)
        )
        NSColor(calibratedWhite: 0.16, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(
            at: CGPoint(x: 8, y: 4),
            withAttributes: attributes
        )
    }

    func preferredSize(for text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ])
        return NSSize(width: ceil(size.width) + 16, height: ceil(size.height) + 8)
    }
}
