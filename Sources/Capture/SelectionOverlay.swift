import AppKit

/// 覆盖全屏的截图选区窗口：置顶到屏幕保护程序层级，盖住普通窗口与全屏 App。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SelectionOverlayView: NSView {
    private let image: CGImage
    private let displayImage: NSImage
    private var dragStart: CGPoint?
    private var selection: CGRect = .zero
    private var cursorPoint: CGPoint?
    private var currentColor: NSColor?
    private var statusMessage: String?
    private var statusToken = UUID()
    private lazy var sampler = PixelSampler(image: image)
    private var snapGuidesX: [CGFloat] = []
    private var snapGuidesY: [CGFloat] = []
    private var activeSnapX: CGFloat?
    private var activeSnapY: CGFloat?
    private let snapThreshold: CGFloat = 8

    private struct WindowHit {
        let window: CapturableWindow
        let rect: CGRect
    }

    private let allowsWindowPicking: Bool
    private var windowHits: [WindowHit] = []
    private var hoveredWindowIndex: Int?
    private var didDrag = false

    var onComplete: ((CGImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onPickWindow: ((CapturableWindow) -> Void)?

    init(
        frame: NSRect,
        image: CGImage,
        displayID: CGDirectDisplayID,
        allowsWindowPicking: Bool = false
    ) {
        self.image = image
        self.displayImage = NSImage(cgImage: image, size: frame.size)
        self.allowsWindowPicking = allowsWindowPicking
        super.init(frame: frame)
        wantsLayer = true
        loadSnapGuides(displayID: displayID)
        if allowsWindowPicking {
            loadWindowHits(displayID: displayID)
        }
    }

    private func loadSnapGuides(displayID: CGDirectDisplayID) {
        snapGuidesX = [0, bounds.width]
        snapGuidesY = [0, bounds.height]

        let screenBounds = CGDisplayBounds(displayID)
        for window in WindowCaptureService.windows(on: displayID) {
            let localX = window.frame.minX - screenBounds.minX
            let localTop = window.frame.minY - screenBounds.minY
            let localBottom = bounds.height - (localTop + window.frame.height)
            let localTopY = bounds.height - localTop

            for value in [localX, localX + window.frame.width]
            where value >= 0 && value <= bounds.width {
                snapGuidesX.append(value)
            }
            for value in [localBottom, localTopY]
            where value >= 0 && value <= bounds.height {
                snapGuidesY.append(value)
            }
        }
    }

    private func loadWindowHits(displayID: CGDirectDisplayID) {
        let screenBounds = CGDisplayBounds(displayID)
        for window in WindowCaptureService.windows(on: displayID) {
            let localX = window.frame.minX - screenBounds.minX
            let localY = bounds.height - (window.frame.minY - screenBounds.minY) - window.frame.height
            let rect = CGRect(
                x: localX,
                y: localY,
                width: window.frame.width,
                height: window.frame.height
            )
            guard rect.intersects(bounds), rect.width >= 16, rect.height >= 16 else { continue }
            windowHits.append(WindowHit(window: window, rect: rect))
        }
    }

    private func topmostWindowIndex(at point: CGPoint) -> Int? {
        // 窗口列表不保证可见层级；优先取包含光标的最小窗口，避免全屏底层窗口吞掉小窗口。
        windowHits.indices
            .filter { windowHits[$0].rect.contains(point) }
            .min { lhs, rhs in
                let left = windowHits[lhs].rect.width * windowHits[lhs].rect.height
                let right = windowHits[rhs].rect.width * windowHits[rhs].rect.height
                return left < right
            }
    }

    private func snapped(_ value: CGFloat, guides: [CGFloat]) -> (value: CGFloat, guide: CGFloat?) {
        guard AppSettings.shared.snapToEdges else { return (value, nil) }
        var bestValue = value
        var bestGuide: CGFloat?
        var bestDistance = snapThreshold + 1
        for guide in guides {
            let distance = abs(guide - value)
            if distance <= snapThreshold, distance < bestDistance {
                bestDistance = distance
                bestValue = guide
                bestGuide = guide
            }
        }
        return (bestValue, bestGuide)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)

        if let location = window?.mouseLocationOutsideOfEventStream {
            let point = convert(location, from: nil)
            cursorPoint = point
            let pixel = imagePoint(point)
            currentColor = sampler?.color(atX: Int(pixel.x), y: Int(pixel.y))
            if allowsWindowPicking {
                hoveredWindowIndex = topmostWindowIndex(at: point)
            }
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        displayImage.draw(in: bounds)

        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        if selection.width == 0,
           allowsWindowPicking,
           let index = hoveredWindowIndex,
           windowHits.indices.contains(index) {
            let hit = windowHits[index]

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: hit.rect).addClip()
            displayImage.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: hit.rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()

            drawWindowTitle(for: hit)
        }

        if selection.width > 0, selection.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            displayImage.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()

            drawSizeLabel()
        } else {
            drawHint()
        }

        drawSnapGuides()
        drawMagnifier()
        drawStatus()
    }

    private func drawWindowTitle(for hit: WindowHit) {
        let text = hit.window.displayTitle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = CGPoint(x: hit.rect.minX, y: hit.rect.maxY + 8)
        if origin.y + size.height + 10 > bounds.height - 4 {
            origin.y = hit.rect.minY - size.height - 14
        }
        origin.x = min(max(origin.x, 4), bounds.width - size.width - 20)

        let background = NSRect(x: origin.x, y: origin.y - 4, width: size.width + 12, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 6, y: origin.y), withAttributes: attributes)
    }

    private func drawSnapGuides() {
        guard AppSettings.shared.snapToEdges else { return }
        NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
        if let x = activeSnapX {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.height))
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        }
        if let y = activeSnapY {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: bounds.width, y: y))
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        }
    }

    private func drawHint() {
        let text: String
        if allowsWindowPicking {
            text = L10n.t(
                "移动高亮窗口 · 点击截窗口 · 拖拽截区域 · 点空白截全屏 · F 全屏 · Esc 取消",
                "Hover to highlight a window · Click to capture it · Drag to select · Click desktop for full screen · F for full screen · Esc cancels"
            )
        } else {
            text = L10n.t("拖拽选择区域 · C 复制色值 · Esc / 右键取消", "Drag to select · C copies color · Esc / right-click cancels")
        }
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

    private func drawSizeLabel() {
        let pixels = pixelRect(for: selection)
        let text = "\(Int(pixels.width)) × \(Int(pixels.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)

        var origin = CGPoint(x: selection.minX, y: selection.minY - size.height - 10)
        if origin.y < 6 {
            origin.y = selection.maxY + 10
        }

        let background = NSRect(x: origin.x, y: origin.y - 4, width: size.width + 12, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 6, y: origin.y), withAttributes: attributes)
    }

    // MARK: - Mouse & keyboard

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorPoint = point
        let pixel = imagePoint(point)
        currentColor = sampler?.color(atX: Int(pixel.x), y: Int(pixel.y))

        if allowsWindowPicking, dragStart == nil, selection.width == 0 {
            hoveredWindowIndex = topmostWindowIndex(at: point)
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        cursorPoint = nil
        currentColor = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let x = snapped(raw.x, guides: snapGuidesX)
        let y = snapped(raw.y, guides: snapGuidesY)
        activeSnapX = x.guide
        activeSnapY = y.guide
        dragStart = CGPoint(x: x.value, y: y.value)
        selection = .zero
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let raw = convert(event.locationInWindow, from: nil)
        let snappedX = snapped(raw.x, guides: snapGuidesX)
        let snappedY = snapped(raw.y, guides: snapGuidesY)
        activeSnapX = snappedX.guide
        activeSnapY = snappedY.guide
        let current = CGPoint(x: snappedX.value, y: snappedY.value)
        if abs(current.x - start.x) > 3 || abs(current.y - start.y) > 3 {
            didDrag = true
            hoveredWindowIndex = nil
        }
        var width = abs(current.x - start.x)
        var height = abs(current.y - start.y)
        if event.modifierFlags.contains(.shift) {
            let side = max(width, height)
            width = side
            height = side
        }
        let x = current.x >= start.x ? start.x : start.x - width
        let y = current.y >= start.y ? start.y : start.y - height
        selection = CGRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil

        if allowsWindowPicking, !didDrag {
            if let index = hoveredWindowIndex, windowHits.indices.contains(index) {
                onPickWindow?(windowHits[index].window)
            } else {
                let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                onComplete?(image, full)
            }
            return
        }

        guard selection.width >= 2, selection.height >= 2 else {
            onCancel?()
            return
        }

        let pixels = pixelRect(for: selection)
        guard pixels.width >= 1, pixels.height >= 1, let cropped = image.cropping(to: pixels) else {
            onCancel?()
            return
        }
        onComplete?(cropped, pixels)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1

        switch event.keyCode {
        case 8: // C：复制色值
            if let color = currentColor {
                let hex = color.hexString
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(hex, forType: .string)
                flashStatus(L10n.t("已复制", "Copied") + " \(hex)")
            }
        case 123, 124, 125, 126:
            guard selection.width > 0, selection.height > 0 else { return }
            switch event.keyCode {
            case 123: selection = selection.offsetBy(dx: -step, dy: 0)
            case 124: selection = selection.offsetBy(dx: step, dy: 0)
            case 125: selection = selection.offsetBy(dx: 0, dy: step)
            default: selection = selection.offsetBy(dx: 0, dy: -step)
            }
            needsDisplay = true
        case 3: // F：全屏
            if allowsWindowPicking {
                let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                onComplete?(image, full)
            }
        case 13: // W：当前高亮窗口
            if allowsWindowPicking,
               let index = hoveredWindowIndex,
               windowHits.indices.contains(index) {
                onPickWindow?(windowHits[index].window)
            }
        case 53: // Esc
            onCancel?()
        case 36, 76: // Return / Enter
            if selection.width >= 2, selection.height >= 2 {
                let pixels = pixelRect(for: selection)
                if let cropped = image.cropping(to: pixels) {
                    onComplete?(cropped, pixels)
                }
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Magnifier

    private func drawMagnifier() {
        guard AppSettings.shared.showMagnifier,
              let cursor = cursorPoint,
              bounds.contains(cursor),
              let color = currentColor else { return }

        let radius: CGFloat = 62
        let margin: CGFloat = 14
        var center = CGPoint(x: cursor.x + 120, y: cursor.y + 120)
        if center.x + radius > bounds.width - margin { center.x = cursor.x - 120 }
        if center.y + radius > bounds.height - margin { center.y = cursor.y - 120 }
        center.x = min(max(center.x, radius + margin), bounds.width - radius - margin)
        center.y = min(max(center.y, radius + margin), bounds.height - radius - margin)

        let lens = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let baseScale = bounds.width / CGFloat(image.width)
        let zoomScale = baseScale * 5
        let pixel = imagePoint(cursor)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: lens).addClip()
        NSColor.black.setFill()
        lens.fill()

        let visiblePixels = (radius * 2) / zoomScale
        let cropRect = CGRect(
            x: pixel.x - visiblePixels / 2,
            y: pixel.y - visiblePixels / 2,
            width: visiblePixels,
            height: visiblePixels
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = cropRect.intersection(imageBounds)
        if clamped.width >= 1, clamped.height >= 1, let crop = image.cropping(to: clamped) {
            NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
                .draw(in: lens)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.85).setStroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: center.x - 10, y: center.y))
        cross.line(to: CGPoint(x: center.x + 10, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - 10))
        cross.line(to: CGPoint(x: center.x, y: center.y + 10))
        cross.lineWidth = 1
        cross.stroke()

        NSColor.black.withAlphaComponent(0.6).setStroke()
        let outer = NSBezierPath(ovalIn: lens.insetBy(dx: -2, dy: -2))
        outer.lineWidth = 4
        outer.stroke()

        NSColor.white.setStroke()
        let inner = NSBezierPath(ovalIn: lens)
        inner.lineWidth = 1.5
        inner.stroke()

        let hex = color.hexString
        let rgb = "RGB(\(Int(color.redComponent * 255)), \(Int(color.greenComponent * 255)), \(Int(color.blueComponent * 255)))"
        let text = "\(hex)  \(rgb)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let labelWidth = textSize.width + 44
        var labelY = lens.minY - 38
        if labelY < margin {
            labelY = lens.maxY + 10
        }
        let labelRect = CGRect(
            x: min(max(center.x - labelWidth / 2, margin), bounds.width - labelWidth - margin),
            y: labelY,
            width: labelWidth,
            height: 30
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()

        let swatch = CGRect(x: labelRect.minX + 8, y: labelRect.midY - 7, width: 14, height: 14)
        color.setFill()
        swatch.fill()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let swatchBorder = NSBezierPath(rect: swatch)
        swatchBorder.lineWidth = 1
        swatchBorder.stroke()

        (text as NSString).draw(
            at: CGPoint(x: labelRect.minX + 30, y: labelRect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawStatus() {
        guard let message = statusMessage else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (message as NSString).size(withAttributes: attributes)
        let rect = CGRect(
            x: (bounds.width - size.width - 24) / 2,
            y: bounds.height - 86,
            width: size.width + 24,
            height: 30
        )
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        (message as NSString).draw(
            at: CGPoint(x: rect.minX + 12, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func flashStatus(_ message: String) {
        statusMessage = message
        let token = UUID()
        statusToken = token
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.statusToken == token else { return }
            self.statusMessage = nil
            self.needsDisplay = true
        }
    }

    private func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: viewPoint.x * CGFloat(image.width) / bounds.width,
            y: (bounds.height - viewPoint.y) * CGFloat(image.height) / bounds.height
        )
    }

    // MARK: - Geometry

    /// 视图坐标（左下原点、point）→ 图片坐标（左上原点、pixel）。
    private func pixelRect(for rect: CGRect) -> CGRect {
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let raw = CGRect(
            x: rect.minX * scaleX,
            y: (bounds.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        let boundsInPixels = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return raw.integral.intersection(boundsInPixels)
    }
}
