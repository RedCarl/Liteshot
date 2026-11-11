import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("关于 Liteshot", "About Liteshot")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "Liteshot")
        name.font = .systemFont(ofSize: 24, weight: .bold)
        name.alignment = .center

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: L10n.t("版本", "Version") + " \(version) (\(build))")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let description = NSTextField(
            wrappingLabelWithString: L10n.t(
                "轻量原生的 macOS 截图工具\n区域 · 窗口 · 滚动截图 · 标注 · OCR · 钉图",
                "A lightweight native screenshot tool for macOS\nRegion · Window · Scrolling · Annotations · OCR · Pins"
            )
        )
        description.alignment = .center
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        description.translatesAutoresizingMaskIntoConstraints = false

        let copyright = NSTextField(labelWithString: "© 2026 Liteshot")
        copyright.font = .systemFont(ofSize: 11)
        copyright.textColor = .tertiaryLabelColor
        copyright.alignment = .center

        let close = NSButton(title: L10n.t("好", "OK"), target: self, action: #selector(closePanel))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\r"
        close.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, name, versionLabel, description, copyright, close])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96),
            description.widthAnchor.constraint(equalToConstant: 300),
            close.widthAnchor.constraint(equalToConstant: 88),
            close.heightAnchor.constraint(equalToConstant: 30),

            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
    }

    func show() {
        if let window,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let size = window.frame.size
            window.setFrameOrigin(
                CGPoint(
                    x: screen.frame.midX - size.width / 2,
                    y: screen.frame.midY - size.height / 2
                )
            )
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func closePanel() {
        window?.orderOut(nil)
    }
}
