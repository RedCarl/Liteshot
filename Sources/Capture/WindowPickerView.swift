import AppKit

@MainActor
final class WindowPickerView: NSView {
    struct Item {
        let window: CapturableWindow
        let rect: CGRect   // 视图坐标（左下原点）
    }

    private let image: CGImage
    private let displayImage: NSImage
    private let items: [Item]
    private var hoveredIndex: Int?
    private var selectedOrder: [CGWindowID] = []

    var onPick: (([CapturableWindow]) -> Void)?
    var onCancel: (() -> Void)?

    init(frame: NSRect, image: CGImage, items: [Item]) {
        self.image = image
        self.displayImage = NSImage(cgImage: image, size: frame.size)
        self.items = items
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
        if let location = window?.mouseLocationOutsideOfEventStream {
            let point = convert(location, from: nil)
            hoveredIndex = items.firstIndex(where: { $0.rect.contains(point) })
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        displayImage.draw(in: bounds)

        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        if let index = hoveredIndex, items.indices.contains(index) {
            let item = items[index]

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: item.rect).addClip()
            displayImage.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: item.rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()

            drawTitle(for: item)
        }

        for (order, id) in selectedOrder.enumerated() {
            guard let item = items.first(where: { $0.window.id == id }) else { continue }
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: item.rect.insetBy(dx: 2, dy: 2))
            border.lineWidth = 3
            border.stroke()
            drawBadge(number: order + 1, at: item.rect.origin)
        }

        drawHint()
    }

    private func drawBadge(number: Int, at point: CGPoint) {
        let radius: CGFloat = 11
        let center = CGPoint(
            x: min(max(point.x + radius + 4, radius + 4), bounds.width - radius - 4),
            y: min(max(point.y - radius - 4, radius + 4), bounds.height - radius - 4)
        )
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.setStroke()
        let outline = NSBezierPath(ovalIn: circle)
        outline.lineWidth = 1.5
        outline.stroke()

        let text = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawTitle(for item: Item) {
        let text = item.window.displayTitle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let maxWidth = bounds.width - 16
        let width = min(size.width, maxWidth)
        let rectHeight = size.height + 10

        var origin = CGPoint(x: item.rect.minX, y: item.rect.maxY + 8)
        if origin.y + rectHeight > bounds.height - 4 {
            origin.y = item.rect.minY - rectHeight - 8
        }
        origin.x = min(max(origin.x, 4), bounds.width - width - 12)

        let background = NSRect(x: origin.x, y: origin.y, width: width + 12, height: rectHeight)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()

        let textRect = NSRect(x: origin.x + 6, y: origin.y + 5, width: width, height: size.height)
        (text as NSString).draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

    private func drawHint() {
        let text = L10n.t("点击窗口 · Shift 多选 · Enter 捕获 · Esc 取消", "Click a window · Shift multi-select · Enter captures · Esc cancels")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: (bounds.width - size.width - 24) / 2, y: bounds.height - size.height - 40)
        let background = NSRect(x: origin.x, y: origin.y - 8, width: size.width + 24, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: background, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 12, y: origin.y), withAttributes: attributes)
    }

    // MARK: - Interaction

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = items.firstIndex(where: { $0.rect.contains(point) })
        if index != hoveredIndex {
            hoveredIndex = index
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = items.firstIndex(where: { $0.rect.contains(point) }) else { return }
        let window = items[index].window

        if event.modifierFlags.contains(.shift) {
            if let position = selectedOrder.firstIndex(of: window.id) {
                selectedOrder.remove(at: position)
            } else {
                selectedOrder.append(window.id)
            }
            needsDisplay = true
            return
        }

        onPick?([window])
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 36, 76:
            let selected = items
                .filter { selectedOrder.contains($0.window.id) }
                .map(\.window)
            if !selected.isEmpty {
                onPick?(selected)
            } else if let hoveredIndex, items.indices.contains(hoveredIndex) {
                onPick?([items[hoveredIndex].window])
            }
        default:
            super.keyDown(with: event)
        }
    }
}
