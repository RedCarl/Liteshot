import AppKit

/// 选区上方的样式条：尺寸、圆角、阴影。每次截图单独调整，不写进设置。
@MainActor
final class CaptureStyleBarView: NSView {
    var onRadiusChanged: ((CGFloat) -> Void)?
    var onShadowChanged: ((Bool) -> Void)?

    private let sizeLabel = NSTextField(labelWithString: "")
    private let radiusTitle = NSTextField(labelWithString: L10n.t("圆角", "Corner"))
    private let radiusValue = NSTextField(labelWithString: "0")
    private let radiusSlider = NSSlider(value: 0, minValue: 0, maxValue: 40, target: nil, action: nil)
    private let shadowTitle = NSTextField(labelWithString: L10n.t("阴影", "Shadow"))
    private let shadowToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 0.94).cgColor
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        configureLabel(sizeLabel, font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        configureLabel(radiusTitle, font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.72))
        configureLabel(radiusValue, font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        configureLabel(shadowTitle, font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.72))

        radiusSlider.isContinuous = true
        radiusSlider.controlSize = .small
        radiusSlider.target = self
        radiusSlider.action = #selector(radiusChanged)
        radiusSlider.toolTip = L10n.t("圆角大小（0–40 px）", "Corner radius (0–40 px)")

        shadowToggle.setButtonType(.switch)
        shadowToggle.title = ""
        shadowToggle.contentTintColor = .white
        shadowToggle.target = self
        shadowToggle.action = #selector(shadowChanged)
        shadowToggle.toolTip = L10n.t("给输出加阴影", "Add a shadow to the output")

        addSubview(sizeLabel)
        addSubview(radiusTitle)
        addSubview(radiusSlider)
        addSubview(radiusValue)
        addSubview(shadowTitle)
        addSubview(shadowToggle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        let h: CGFloat = 34
        sizeLabel.frame = CGRect(x: 10, y: (h - 16) / 2, width: 96, height: 16)
        radiusTitle.frame = CGRect(x: 116, y: (h - 16) / 2, width: 28, height: 16)
        radiusSlider.frame = CGRect(x: 148, y: (h - 20) / 2, width: 124, height: 20)
        radiusValue.frame = CGRect(x: 276, y: (h - 16) / 2, width: 30, height: 16)
        shadowTitle.frame = CGRect(x: 314, y: (h - 16) / 2, width: 30, height: 16)
        shadowToggle.frame = CGRect(x: 346, y: (h - 18) / 2, width: 22, height: 18)
    }

    func update(size: String, radius: CGFloat, shadow: Bool) {
        sizeLabel.stringValue = size
        radiusSlider.doubleValue = Double(radius)
        radiusValue.stringValue = "\(Int(radius))"
        shadowToggle.state = shadow ? .on : .off
    }

    @objc private func radiusChanged() {
        let radius = CGFloat(radiusSlider.doubleValue.rounded())
        radiusValue.stringValue = "\(Int(radius))"
        onRadiusChanged?(radius)
    }

    @objc private func shadowChanged() {
        onShadowChanged?(shadowToggle.state == .on)
    }

    private func configureLabel(_ label: NSTextField, font: NSFont, color: NSColor = .white) {
        label.font = font
        label.textColor = color
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
    }
}
