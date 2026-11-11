import AppKit

/// 延迟截图时的倒计时面板。窗口鼠标穿透，不抢焦点，用户可以趁这几秒整理画面。
@MainActor
final class CountdownView: NSView {
    var remaining: Int {
        didSet { needsDisplay = true }
    }

    private let total: Int

    init(frame: NSRect, total: Int) {
        self.total = total
        self.remaining = total
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let panelSize = NSSize(width: 190, height: 130)
        let panel = NSRect(
            x: (bounds.width - panelSize.width) / 2,
            y: (bounds.height - panelSize.height) / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 18, yRadius: 18).fill()

        let number = "\(remaining)"
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 56, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let numberSize = (number as NSString).size(withAttributes: numberAttributes)
        (number as NSString).draw(
            at: CGPoint(x: panel.midX - numberSize.width / 2, y: panel.midY - numberSize.height / 2 + 8),
            withAttributes: numberAttributes
        )

        let subtitle = L10n.t("秒后截图", "s to capture")
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ]
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
        (subtitle as NSString).draw(
            at: CGPoint(x: panel.midX - subtitleSize.width / 2, y: panel.minY + 14),
            withAttributes: subtitleAttributes
        )
    }
}
