import AppKit
import UniformTypeIdentifiers

final class PinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private let image: CGImage
    private let screen: NSScreen
    private let baseSize: CGSize
    private var zoom: CGFloat = 1

    var onClose: (() -> Void)?

    init(image: CGImage, center: CGPoint? = nil) {
        self.image = image

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center ?? mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        self.screen = screen

        let scale = screen.backingScaleFactor
        var size = CGSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )
        let maxWidth = screen.frame.width * 0.8
        let maxHeight = screen.frame.height * 0.8
        let fit = min(1, maxWidth / size.width, maxHeight / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        self.baseSize = size

        let centerPoint = center ?? CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        let frame = NSRect(
            x: centerPoint.x - size.width / 2,
            y: centerPoint.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        let window = PinWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true

        super.init(window: window)

        let view = PinImageView(image: image)
        view.onDoubleClick = { [weak self] in self?.closePin() }
        view.onClose = { [weak self] in self?.closePin() }
        view.onZoom = { [weak self] factor in self?.zoom(by: factor) }
        view.onOpacity = { [weak self] delta in self?.changeOpacity(by: delta) }
        view.onMove = { [weak self] dx, dy in self?.move(dx: dx, dy: dy) }
        view.onSave = { [weak self] in self?.saveImage() }
        view.menu = makeMenu()
        window.contentView = view
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.unhide(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func showAgain() {
        window?.orderFrontRegardless()
    }

    private func zoom(by factor: CGFloat) {
        guard let window else { return }
        let newZoom = min(4, max(0.2, zoom * factor))
        guard newZoom != zoom else { return }
        zoom = newZoom
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let size = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        window.setFrame(
            NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func changeOpacity(by delta: CGFloat) {
        guard let window else { return }
        window.alphaValue = min(1, max(0.2, window.alphaValue + delta))
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        guard let window else { return }
        window.setFrameOrigin(CGPoint(x: window.frame.minX + dx, y: window.frame.minY + dy))
    }

    private func closePin() {
        window?.orderOut(nil)
        window?.contentView = nil
    }

    private func copyImage() {
        ClipboardService.copy(image: image)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t("放大", "Zoom In"), action: #selector(menuZoomIn), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("缩小", "Zoom Out"), action: #selector(menuZoomOut), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("提高不透明度", "Increase Opacity"), action: #selector(menuOpacityUp), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("降低不透明度", "Decrease Opacity"), action: #selector(menuOpacityDown), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("复制图片", "Copy Image"), action: #selector(menuCopy), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("保存到 Downloads", "Save to Downloads"), action: #selector(menuSave), keyEquivalent: "s").target = self
        menu.addItem(withTitle: L10n.t("关闭贴图", "Close Pin"), action: #selector(menuClose), keyEquivalent: "").target = self
        return menu
    }

    @objc private func menuZoomIn() { zoom(by: 1.1) }
    @objc private func menuZoomOut() { zoom(by: 1 / 1.1) }
    @objc private func menuOpacityUp() { changeOpacity(by: 0.1) }
    @objc private func menuOpacityDown() { changeOpacity(by: -0.1) }
    @objc private func menuCopy() { copyImage() }

    @objc private func menuSave() { saveImage() }

    func presentSavePanel() { saveImage() }

    private func saveImage() {
        guard let png = ImageEncoding.pngData(from: image) else {
            NSSound.beep()
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = directory.appendingPathComponent("Liteshot-Pin-\(formatter.string(from: Date())).png")
        do {
            try png.write(to: url)
            NSSound(named: "Glass")?.play()
        } catch {
            NSSound.beep()
        }
    }
    @objc private func menuClose() { closePin() }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
private final class PinImageView: NSView {
    private let image: CGImage
    private var hovered = false

    var onDoubleClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onOpacity: ((CGFloat) -> Void)?
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onSave: (() -> Void)?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)

        if hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let step: CGFloat = shift ? 10 : 1

        if command, let characters = event.charactersIgnoringModifiers {
            if characters == "=" {
                onOpacity?(0.1)
                return
            }
            if characters == "-" {
                onOpacity?(-0.1)
                return
            }
            if characters == "s" {
                onSave?()
                return
            }
        }

        switch event.keyCode {
        case 24: // =
            onZoom?(command ? 1 : 1.1)
        case 27: // -
            onZoom?(command ? 1 : 1 / 1.1)
        case 53: // Esc
            onClose?()
        case 123:
            onMove?(-step, 0)
        case 124:
            onMove?(step, 0)
        case 125:
            onMove?(0, -step)
        case 126:
            onMove?(0, step)
        default:
            super.keyDown(with: event)
        }
    }
}
