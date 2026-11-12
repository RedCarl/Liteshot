import AppKit
import CoreGraphics

enum ScrollStrategy {
    case vertical
    case horizontal
    case panorama
}

enum ScrollCaptureError: LocalizedError {
    case noScreen
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScreen:
            return L10n.t("没有找到可截图的屏幕。", "No screen available for capture.")
        case .captureFailed(let message):
            return L10n.t("滚动截图失败：", "Scrolling capture failed: ") + message
        }
    }
}

/// 竖向滚动截图会话：按固定间隔截取选区，ScrollStitcher 拼接；HUD 提供完成/取消。
@MainActor
final class ScrollCaptureSession: NSObject {
    private let screen: NSScreen
    private let pixelRect: CGRect
    private var strategy: ScrollStrategy
    private var stitcher: any ScrollStitching

    private var hudWindow: NSPanel?
    private var borderWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var thumbnailView: NSImageView?
    private var captureTask: Task<Void, Never>?
    private var isFinishing = false

    var onFinish: ((CGImage) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, pixelRect: CGRect, strategy: ScrollStrategy = .vertical) {
        self.screen = screen
        self.pixelRect = pixelRect
        self.strategy = strategy

        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        switch strategy {
        case .vertical:
            self.stitcher = ScrollStitcher(width: width, height: height, axis: .vertical)
        case .horizontal:
            self.stitcher = ScrollStitcher(width: width, height: height, axis: .horizontal)
        case .panorama:
            self.stitcher = PanoramaStitcher(width: width, height: height)
        }
        super.init()

        wireStitcherCallbacks()
    }

    private func wireStitcherCallbacks() {
        stitcher.onUpdate = { [weak self] height in
            self?.updateStatus(height)
            self?.updateThumbnail()
        }
        stitcher.onWarning = { [weak self] message in
            self?.statusLabel?.stringValue = message
        }
    }

    private var initialStatusText: String {
        switch strategy {
        case .vertical:
            return L10n.t("竖向滚动开始拼接…", "Scroll vertically to start…")
        case .horizontal:
            return L10n.t("横向滚动开始拼接…", "Scroll horizontally to start…")
        case .panorama:
            return L10n.t("滚动页面开始全景拼接…", "Scroll in any direction to start…")
        }
    }

    private func rebuildStitcher() {
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        switch strategy {
        case .vertical:
            stitcher = ScrollStitcher(width: width, height: height, axis: .vertical)
        case .horizontal:
            stitcher = ScrollStitcher(width: width, height: height, axis: .horizontal)
        case .panorama:
            stitcher = PanoramaStitcher(width: width, height: height)
        }
        wireStitcherCallbacks()
        statusLabel?.stringValue = initialStatusText
        thumbnailView?.image = nil
    }

    @objc private func strategyChanged(_ sender: NSSegmentedControl) {
        let selected: ScrollStrategy
        switch sender.selectedSegment {
        case 1: selected = .horizontal
        case 2: selected = .panorama
        default: selected = .vertical
        }
        guard selected != strategy else { return }

        // 已经拼过帧就不允许换方向，避免画布语义混乱。
        guard stitcher.stitchedLength <= stitcher.baseLength + 4 else {
            NSSound.beep()
            sender.selectedSegment = currentSegment
            return
        }

        strategy = selected
        rebuildStitcher()
    }

    private var currentSegment: Int {
        switch strategy {
        case .vertical: return 0
        case .horizontal: return 1
        case .panorama: return 2
        }
    }

    func start() async throws {
        guard ScreenPermission.isGranted else {
            throw ScrollCaptureError.captureFailed(L10n.t("需要屏幕录制权限", "Screen recording permission is required"))
        }
        showBorder()
        showHUD()
        startPolling()
    }

    // MARK: - Capture

    private func startPolling() {
        captureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(220))
                guard let self, !self.isFinishing else { return }
                await self.captureOnce()
            }
        }
    }

    private func captureOnce() async {
        do {
            let full = try await ScreenCaptureService.capture(
                displayID: screen.displayID,
                pixelWidth: Int(screen.pixelSize.width),
                pixelHeight: Int(screen.pixelSize.height),
                showsCursor: false
            )
            let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
            let rect = pixelRect.intersection(bounds).integral
            guard rect.width >= 1, rect.height >= 1, let cropped = full.cropping(to: rect) else {
                return
            }
            stitcher.add(cropped)
        } catch {
            statusLabel?.stringValue = L10n.t("截取失败，重试中…", "Capture failed, retrying…")
        }
    }

    // MARK: - UI

    private func showHUD() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.84).cgColor
        content.layer?.cornerRadius = 12

        let thumbnail = NSImageView()
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        thumbnail.layer?.cornerRadius = 6
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(thumbnail)
        thumbnailView = thumbnail

        let label = NSTextField(labelWithString: initialStatusText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = label

        let finish = NSButton(title: L10n.t("完成", "Done"), target: self, action: #selector(finishTapped))
        finish.title = L10n.t("完成", "Done")
        finish.bezelStyle = .rounded
        finish.controlSize = .small

        let cancel = NSButton(title: L10n.t("取消", "Cancel"), target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .small

        let buttons = NSStackView(views: [finish, cancel])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let direction = NSSegmentedControl(
            labels: [
                L10n.t("竖向", "Vertical"),
                L10n.t("横向", "Horizontal"),
                L10n.t("全景", "Panorama"),
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(strategyChanged(_:))
        )
        direction.selectedSegment = currentSegment
        direction.controlSize = .small
        direction.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [label, direction])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(textStack)
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            thumbnail.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 88),
            thumbnail.heightAnchor.constraint(equalToConstant: 54),

            textStack.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        panel.contentView = content
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - 280,
                y: screen.frame.minY + 80,
                width: 560,
                height: 72
            ),
            display: true
        )
        panel.orderFrontRegardless()
        hudWindow = panel
    }

    private func updateThumbnail() {
        guard let thumbnailView, let image = stitcher.makeImage() else { return }
        thumbnailView.image = NSImage(cgImage: image, size: NSSize(width: 88, height: 54))
    }

    private func showBorder() {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let scale = screen.backingScaleFactor
        let localRect = CGRect(
            x: pixelRect.minX / scale,
            y: screen.frame.height - pixelRect.minY / scale - pixelRect.height / scale,
            width: pixelRect.width / scale,
            height: pixelRect.height / scale
        )
        let view = ScrollBorderView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            highlight: localRect
        )
        window.contentView = view
        window.orderFrontRegardless()
        borderWindow = window
    }

    private func updateStatus(_ length: Int) {
        statusLabel?.stringValue = L10n.t("已拼接", "Stitched") + " \(length) px"
        if stitcher.isFull {
            finish()
        }
    }

    private func closeWindows() {
        hudWindow?.orderOut(nil)
        hudWindow = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
    }

    // MARK: - Actions

    @objc private func finishTapped() {
        finish()
    }

    @objc private func cancelTapped() {
        cancel()
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        captureTask?.cancel()
        captureTask = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))

            let scrolled = stitcher.stitchedLength > stitcher.baseLength + 4
            guard scrolled, let image = stitcher.makeImage() else {
                // 没滚动起来不弹模态框：留在 HUD 里提示，用户放慢速度再试。
                isFinishing = false
                statusLabel?.stringValue = L10n.t(
                    "没有检测到滚动，请放慢速度再试一次",
                    "No scrolling detected. Scroll slower and try again."
                )
                NSSound.beep()
                startPolling()
                return
            }
            closeWindows()
            onFinish?(image)
        }
    }

    private func cancel() {
        guard !isFinishing else { return }
        isFinishing = true
        captureTask?.cancel()
        captureTask = nil
        closeWindows()
        onCancel?()
    }

}

@MainActor
private final class ScrollBorderView: NSView {
    private let highlight: CGRect

    init(frame: NSRect, highlight: CGRect) {
        self.highlight = highlight
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: highlight.insetBy(dx: -2, dy: -2))
        path.lineWidth = 1.5
        path.stroke()
    }
}
