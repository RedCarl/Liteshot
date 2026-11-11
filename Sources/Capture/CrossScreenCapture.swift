import AppKit

@MainActor
final class CrossScreenSelectionState {
    var startGlobal: CGPoint?
    var currentGlobal: CGPoint?

    var selection: CGRect {
        guard let start = startGlobal, let current = currentGlobal else { return .zero }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var onChange: (() -> Void)?
}

@MainActor
final class CrossScreenOverlayView: NSView {
    private let screen: NSScreen
    private let image: CGImage
    private let displayImage: NSImage
    private let state: CrossScreenSelectionState
    private let isInteractive: Bool

    var onFinishSelection: (() -> Void)?
    var onCancelSelection: (() -> Void)?
    private var dragTimer: Timer?
    private var isDragging = false

    init(screen: NSScreen, image: CGImage, state: CrossScreenSelectionState, isInteractive: Bool) {
        self.screen = screen
        self.image = image
        self.state = state
        self.isInteractive = isInteractive
        self.displayImage = NSImage(cgImage: image, size: screen.frame.size)
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        displayImage.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        let selection = state.selection
        guard selection.width > 0, selection.height > 0 else {
            if isInteractive { drawHint() }
            return
        }

        let local = localRect(fromGlobal: selection)
        let visible = local.intersection(bounds)
        guard visible.width > 0, visible.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: visible).addClip()
        displayImage.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        if isInteractive {
            drawSizeLabel(for: selection)
        }
    }

    private func localRect(fromGlobal global: CGRect) -> CGRect {
        CGRect(
            x: global.minX - screen.frame.minX,
            y: global.minY - screen.frame.minY,
            width: global.width,
            height: global.height
        )
    }

    private func drawHint() {
        let text = L10n.t("跨屏拖拽选择区域 · Esc 取消", "Drag across displays to select · Esc cancels")
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

    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height)) pt"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let local = localRect(fromGlobal: selection)
        var origin = CGPoint(x: local.minX, y: local.minY - size.height - 10)
        if origin.y < 6 { origin.y = local.maxY + 10 }
        let background = NSRect(x: origin.x, y: origin.y - 4, width: size.width + 12, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 6, y: origin.y), withAttributes: attributes)
    }

    // MARK: - Interaction

    private func globalPoint(for event: NSEvent) -> CGPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }

    private func stopDragging() {
        isDragging = false
        dragTimer?.invalidate()
        dragTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive, let point = globalPoint(for: event) else { return }
        isDragging = true
        state.startGlobal = point
        state.currentGlobal = point
        state.onChange?()
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60,
            target: self,
            selector: #selector(pollDrag),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func pollDrag() {
        guard isDragging else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            finishDrag()
        } else {
            state.currentGlobal = NSEvent.mouseLocation
            state.onChange?()
        }
    }

    private func finishDrag() {
        guard isDragging else { return }
        isDragging = false
        dragTimer?.invalidate()
        dragTimer = nil
        state.currentGlobal = NSEvent.mouseLocation
        state.onChange?()
        onFinishSelection?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractive, let point = globalPoint(for: event) else { return }
        state.currentGlobal = point
        state.onChange?()
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive else { return }
        finishDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        stopDragging()
        onCancelSelection?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            stopDragging()
            onCancelSelection?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class CrossScreenCaptureController {
    private let screens: [NSScreen]
    private let images: [CGDirectDisplayID: CGImage]
    private let interactiveScreen: NSScreen
    private let state = CrossScreenSelectionState()
    private var windows: [NSWindow] = []

    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screens: [NSScreen], images: [CGDirectDisplayID: CGImage], interactiveScreen: NSScreen) {
        self.screens = screens
        self.images = images
        self.interactiveScreen = interactiveScreen
    }

    func start() {
        state.onChange = { [weak self] in
            self?.windows.forEach { $0.contentView?.needsDisplay = true }
        }

        for screen in screens {
            guard let image = images[screen.displayID] else { continue }
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let isInteractive = screen.displayID == interactiveScreen.displayID
            window.ignoresMouseEvents = !isInteractive
            let view = CrossScreenOverlayView(
                screen: screen,
                image: image,
                state: state,
                isInteractive: isInteractive
            )
            view.onFinishSelection = { [weak self] in
                self?.finishSelection()
            }
            view.onCancelSelection = { [weak self] in
                self?.cancelSelection()
            }
            window.contentView = view
            window.orderFrontRegardless()
            if isInteractive {
                window.acceptsMouseMovedEvents = true
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            }
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        if let keyWindow = windows.first(where: { $0.isKeyWindow }) {
            keyWindow.makeKey()
        }
    }

    func cancel() {
        closeAllWindows()
        onCancel?()
    }

    private func finishSelection() {
        let selection = state.selection
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.closeAllWindows()
            guard selection.width >= 2, selection.height >= 2 else {
                self.onCancel?()
                return
            }
            self.onComplete?(selection)
        }
    }

    private func cancelSelection() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.closeAllWindows()
            self.onCancel?()
        }
    }

    private func closeAllWindows() {
        windows.forEach { window in
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }
}
