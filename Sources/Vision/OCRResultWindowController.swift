import AppKit

@MainActor
final class OCRResultWindowController: NSWindowController {
    static let shared = OCRResultWindowController()

    private let textView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var history: [(title: String, text: String)] = []
    private var historyIndex = -1

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("识别结果", "Recognition Result")
        window.minSize = NSSize(width: 360, height: 240)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let content = NSView()
        window.contentView = content

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        textView.isRichText = false
        textView.isEditable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView

        let prevButton = NSButton(title: L10n.t("上一个", "Previous"), target: self, action: #selector(showPrevious))
        prevButton.bezelStyle = .rounded
        prevButton.keyEquivalent = "["
        prevButton.keyEquivalentModifierMask = [.command]
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(prevButton)

        let nextButton = NSButton(title: L10n.t("下一个", "Next"), target: self, action: #selector(showNext))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "]"
        nextButton.keyEquivalentModifierMask = [.command]
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(nextButton)

        let copyButton = NSButton(title: L10n.t("复制", "Copy"), target: self, action: #selector(copyText))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command]
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(copyButton)

        let closeButton = NSButton(title: L10n.t("关闭", "Close"), target: self, action: #selector(closePanel))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "w"
        closeButton.keyEquivalentModifierMask = [.command]
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),

            nextButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            prevButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            copyButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            closeButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 72),
            copyButton.widthAnchor.constraint(equalToConstant: 72),
            prevButton.widthAnchor.constraint(equalToConstant: 64),
            nextButton.widthAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLast() {
        guard !history.isEmpty else { return }
        historyIndex = history.count - 1
        render()
        if let window, !window.isVisible {
            window.center()
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func show(title: String, text: String) {
        history.append((title, text))
        if history.count > 20 {
            history.removeFirst()
        }
        historyIndex = history.count - 1
        render()
        window?.title = title

        if let window, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
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
        window?.makeFirstResponder(textView)
    }

    func showPreviousResult() { showPrevious() }

    func showNextResult() { showNext() }

    @objc private func showPrevious() {
        guard historyIndex > 0 else {
            NSSound.beep()
            return
        }
        historyIndex -= 1
        render()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showNext() {
        guard historyIndex + 1 < history.count else {
            NSSound.beep()
            return
        }
        historyIndex += 1
        render()
        window?.makeKeyAndOrderFront(nil)
    }

    private func render() {
        guard history.indices.contains(historyIndex) else { return }
        let entry = history[historyIndex]
        titleLabel.stringValue = "\(entry.title)  \(historyIndex + 1)/\(history.count)"
        textView.string = entry.text.isEmpty
            ? L10n.t("（未识别到内容）", "(No content recognized)")
            : entry.text
        window?.title = entry.title
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }

    @objc private func closePanel() {
        window?.performClose(nil)
    }
}
