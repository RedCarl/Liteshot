import AppKit

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: [EditorWindowController] = []

    static func open(image: CGImage) {
        let controller = EditorWindowController(image: image)
        openControllers.append(controller)
        NSApp.unhide(nil)
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            controller.window?.makeKeyAndOrderFront(nil)
            controller.window?.makeKey()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let activated = NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSLog("Liteshot editor: isActive=%d key=%d activateOk=%d", NSApp.isActive ? 1 : 0, (controller.window?.isKeyWindow ?? false) ? 1 : 0, activated ? 1 : 0)
        }
    }

    init(image: CGImage) {
        let controller = EditorViewController(image: image)
        let window = NSWindow(contentViewController: controller)
        window.title = L10n.t("Liteshot 编辑器", "Liteshot Editor") + " · \(image.width)×\(image.height)"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 760))
        window.minSize = NSSize(width: 680, height: 480)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        positionOnMouseScreen()
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }

    private func positionOnMouseScreen() {
        guard let window else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }
        let size = window.frame.size
        window.setFrameOrigin(
            CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            )
        )
    }
}
