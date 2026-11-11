import AppKit

@MainActor
final class PinManager {
    static let shared = PinManager()

    private var controllers: [PinWindowController] = []
    private var hidden = false

    private init() {}

    var isEmpty: Bool { controllers.isEmpty }

    func pin(_ image: CGImage, center: CGPoint? = nil) {
        let controller = PinWindowController(image: image, center: center)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.show()
        hidden = false
    }

    func pinFromPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let image = NSImage(data: data) else {
            return false
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return false
        }
        pin(cgImage)
        return true
    }

    func hideAll() {
        controllers.forEach { $0.hide() }
        hidden = true
    }

    func showAll() {
        controllers.forEach { $0.showAgain() }
        hidden = false
    }

    func closeAll() {
        controllers.forEach { $0.window?.close() }
        controllers.removeAll()
    }

    var areHidden: Bool { hidden }
}
