import AppKit

/// 选区定下来后浮在画布上方的一层：显示 8 个缩放手柄和边框，
/// 只拦截手柄 / 边框（或移动模式下的整个选区）的鼠标事件，
/// 内部区域仍然交给下面的标注画布。
@MainActor
final class SelectionChromeView: NSView {
    var rect: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    var moveMode = false {
        didSet { needsDisplay = true }
    }
    var sizeText: String = "" {
        didSet { needsDisplay = true }
    }

    var onPreview: ((CGRect) -> Void)?
    var onCommit: ((CGRect) -> Void)?

    private enum Drag {
        case none
        case move(CGPoint)
        case resize(Int, CGPoint)
    }

    private var drag: Drag = .none
    private var startRect: CGRect = .zero
    private let handleSize: CGFloat = 9
    private let borderHit: CGFloat = 7

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, rect.width > 1, rect.height > 1 else { return nil }
        let local = convert(point, from: superview)
        if resizeHandleIndex(at: local) != nil { return self }
        if moveMode && rect.contains(local) { return self }
        return nil
    }

    // MARK: - Handles

    private var handlePoints: [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
    }

    private func resizeHandleIndex(at point: CGPoint) -> Int? {
        for (index, handle) in handlePoints.enumerated() {
            if abs(point.x - handle.x) <= handleSize
                && abs(point.y - handle.y) <= handleSize {
                return index
            }
        }

        let nearLeft = abs(point.x - rect.minX) <= borderHit
        let nearRight = abs(point.x - rect.maxX) <= borderHit
        let nearBottom = abs(point.y - rect.minY) <= borderHit
        let nearTop = abs(point.y - rect.maxY) <= borderHit
        let insideX = point.x >= rect.minX - borderHit && point.x <= rect.maxX + borderHit
        let insideY = point.y >= rect.minY - borderHit && point.y <= rect.maxY + borderHit

        if nearLeft, insideY { return nearBottom ? 6 : nearTop ? 0 : 7 }
        if nearRight, insideY { return nearBottom ? 4 : nearTop ? 2 : 3 }
        if nearBottom, insideX { return nearLeft ? 6 : nearRight ? 4 : 5 }
        if nearTop, insideX { return nearLeft ? 0 : nearRight ? 2 : 1 }
        return nil
    }

    // MARK: - Mouse

    private func localPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = localPoint(event)
        startRect = rect
        if let index = resizeHandleIndex(at: point) {
            drag = .resize(index, point)
        } else if moveMode, rect.contains(point) {
            drag = .move(point)
        } else {
            drag = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = localPoint(event)
        switch drag {
        case .none:
            return
        case .move(let start):
            var moved = startRect.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = min(max(moved.origin.x, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.origin.y, 0), bounds.height - moved.height)
            rect = moved
        case .resize(let index, let start):
            rect = resized(startRect, handle: index, to: point)
        }
        onPreview?(rect)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard case .none = drag else {
            drag = .none
            onCommit?(rect)
            return
        }
    }

    private func resized(_ original: CGRect, handle: Int, to point: CGPoint) -> CGRect {
        let minSize: CGFloat = 24
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY

        switch handle {
        case 0: minX = point.x; maxY = point.y
        case 1: maxY = point.y
        case 2: maxX = point.x; maxY = point.y
        case 3: maxX = point.x
        case 4: maxX = point.x; minY = point.y
        case 5: minY = point.y
        case 6: minX = point.x; minY = point.y
        case 7: minX = point.x
        default: break
        }

        if maxX - minX < minSize {
            if handle == 0 || handle == 6 || handle == 7 {
                minX = maxX - minSize
            } else {
                maxX = minX + minSize
            }
        }
        if maxY - minY < minSize {
            if handle == 0 || handle == 1 || handle == 2 {
                maxY = minY + minSize
            } else {
                minY = maxY - minSize
            }
        }

        minX = max(minX, 0)
        minY = max(minY, 0)
        maxX = min(maxX, bounds.width)
        maxY = min(maxY, bounds.height)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard rect.width > 1, rect.height > 1 else { return }

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        for point in handlePoints {
            let handle = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: handle)
            outline.lineWidth = 1
            outline.stroke()
        }

        guard !sizeText.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (sizeText as NSString).size(withAttributes: attributes)
        let pill = CGRect(
            x: min(max(rect.minX + 8, 8), bounds.width - size.width - 20),
            y: min(max(rect.maxY - size.height - 12, 8), bounds.height - size.height - 8),
            width: size.width + 12,
            height: size.height + 6
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        (sizeText as NSString).draw(
            at: CGPoint(x: pill.minX + 6, y: pill.minY + 3),
            withAttributes: attributes
        )
    }
}
