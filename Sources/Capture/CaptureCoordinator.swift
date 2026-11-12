import AppKit

enum CaptureMode {
    case region
    case window
    case fullScreen
    case activeWindow
    case lastArea
    case delayed
    case scroll
    case scrollHorizontal
    case panorama
    case adaptive
    case adaptiveCopy
    case lastAreaSave
    case lastAreaCopy
    case ocrSilent
    case crossScreen
    case ocr
    case qr
}

enum CaptureError: LocalizedError {
    case noScreen
    case noWindow
    case noActiveWindow

    var errorDescription: String? {
        switch self {
        case .noScreen:
            return L10n.t("没有找到可截图的屏幕。", "No screen available for capture.")
        case .noWindow:
            return L10n.t("当前屏幕上没有可截取的窗口。", "No capturable window on this screen.")
        case .noActiveWindow:
            return L10n.t("没有找到活动窗口。", "No active window found.")
        }
    }
}

@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var overlayWindow: NSWindow?
    private var countdownWindow: NSWindow?
    private var scrollSession: ScrollCaptureSession?
    private var crossScreenController: CrossScreenCaptureController?
    private var pendingScrollStrategy: ScrollStrategy = .vertical
    private var isCapturing = false

    private init() {}

    func beginRegionCapture() {
        begin(.region)
    }

    func beginDelayed(seconds: Int) {
        begin(.delayed, delayOverride: seconds)
    }

    func begin(_ mode: CaptureMode, delayOverride: Int? = nil) {
        guard !isCapturing, overlayWindow == nil, countdownWindow == nil,
              scrollSession == nil, crossScreenController == nil else { return }

        // 先用非侵入式接口判断；没权限只弹应用自己的权限窗口，
        // 系统 TCC 弹窗留到用户点「打开设置」时再触发。
        guard ScreenPermission.isGranted else {
            PermissionWindowController.shared.show()
            return
        }
        beginAfterPermission(mode, delayOverride: delayOverride)
    }

    private func beginAfterPermission(_ mode: CaptureMode, delayOverride: Int?) {
        let delay = mode == .delayed
            ? max(1, delayOverride ?? AppSettings.shared.delaySeconds)
            : 0
        if delay > 0 {
            runCountdown(seconds: delay) { [weak self] in
                guard let self else { return }
                if mode == .delayed {
                    if let screen = self.screenUnderMouse(),
                       LastAreaStore.load(displayID: screen.displayID) != nil {
                        self.perform(.lastArea)
                    } else {
                        self.perform(.fullScreen)
                    }
                } else {
                    self.perform(mode)
                }
            }
        } else {
            perform(mode)
        }
    }

    // MARK: - Flow

    private func perform(_ mode: CaptureMode) {
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                switch mode {
                case .region, .delayed:
                    try await startRegionCapture()
                case .adaptive:
                    try await startAdaptiveCapture()
                case .adaptiveCopy:
                    try await startAdaptiveCopyCapture()
                case .lastAreaSave:
                    try await startLastAreaSave()
                case .lastAreaCopy:
                    try await startLastAreaCopy()
                case .window:
                    try await startWindowCapture()
                case .fullScreen:
                    try await startFullScreenCapture()
                case .activeWindow:
                    try await startActiveWindowCapture()
                case .lastArea:
                    try await startLastAreaCapture()
                case .scroll:
                    try await startScrollCapture(strategy: .vertical)
                case .scrollHorizontal:
                    try await startScrollCapture(strategy: .horizontal)
                case .panorama:
                    try await startScrollCapture(strategy: .panorama)
                case .crossScreen:
                    try await startCrossScreenCapture()
                case .ocr, .qr, .ocrSilent:
                    try await startRecognitionCapture(mode: mode)
                }
            } catch {
                showError(error)
            }
        }
    }

    private func captureCurrentScreen() async throws -> (NSScreen, CGImage) {
        guard let screen = screenUnderMouse() else { throw CaptureError.noScreen }
        let settings = AppSettings.shared
        let image = try await ScreenCaptureService.capture(
            displayID: screen.displayID,
            pixelWidth: Int(screen.pixelSize.width),
            pixelHeight: Int(screen.pixelSize.height),
            showsCursor: settings.includeCursor
        )
        return (screen, image)
    }

    private func startRegionCapture() async throws {
        let (screen, image) = try await captureCurrentScreen()
        presentRegionOverlay(on: screen, image: image)
    }

    private func startFullScreenCapture() async throws {
        let (_, image) = try await captureCurrentScreen()
        commit(image)
    }

    private func startLastAreaCapture() async throws {
        guard let screen = screenUnderMouse() else { throw CaptureError.noScreen }
        let image = try await ScreenCaptureService.capture(
            displayID: screen.displayID,
            pixelWidth: Int(screen.pixelSize.width),
            pixelHeight: Int(screen.pixelSize.height),
            showsCursor: AppSettings.shared.includeCursor
        )

        guard let saved = LastAreaStore.load(displayID: screen.displayID) else {
            presentRegionOverlay(on: screen, image: image)
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = saved.intersection(imageBounds).integral
        guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
            presentRegionOverlay(on: screen, image: image)
            return
        }
        commit(cropped)
    }

    private func startLastAreaSave() async throws {
        guard let screen = screenUnderMouse() else { throw CaptureError.noScreen }
        let image = try await ScreenCaptureService.capture(
            displayID: screen.displayID,
            pixelWidth: Int(screen.pixelSize.width),
            pixelHeight: Int(screen.pixelSize.height),
            showsCursor: AppSettings.shared.includeCursor
        )

        guard let saved = LastAreaStore.load(displayID: screen.displayID) else {
            presentRegionOverlay(
                on: screen,
                image: image,
                allowsWindowPicking: true,
                skipActionBar: true,
                onSelected: { [weak self] cropped, _ in
                    self?.saveDirectly(cropped)
                }
            )
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = saved.intersection(imageBounds).integral
        guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else {
            presentRegionOverlay(
                on: screen,
                image: image,
                allowsWindowPicking: true,
                skipActionBar: true,
                onSelected: { [weak self] cropped, _ in
                    self?.saveDirectly(cropped)
                }
            )
            return
        }
        saveDirectly(cropped)
    }

    private func saveDirectly(_ image: CGImage) {
        let settings = AppSettings.shared
        let options = ExportOptions(
            scale: settings.exportScale1x ? 0.5 : 1,
            cornerRadius: CGFloat(settings.exportCornerRadius),
            shadow: settings.exportShadow,
            shadowBlur: CGFloat(settings.exportShadowBlur),
            shadowOpacity: settings.exportShadowOpacity,
            shadowColorHex: settings.exportShadowColorHex,
            transparent: settings.exportTransparent
        )
        let output = EditorRenderer.render(image: image, annotations: [], options: options) ?? image

        if settings.copyToClipboard {
            ClipboardService.copy(image: output)
        }

        do {
            let url = try SaveService.save(
                image: output,
                to: settings.saveDirectory,
                format: settings.format,
                quality: settings.jpegQuality,
                template: settings.filenameTemplate
            )
            if settings.revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            NSSound(named: "Glass")?.play()
        } catch {
            showError(error)
        }
    }

    private func startLastAreaCopy() async throws {
        guard let screen = screenUnderMouse() else { throw CaptureError.noScreen }
        let image = try await ScreenCaptureService.capture(
            displayID: screen.displayID,
            pixelWidth: Int(screen.pixelSize.width),
            pixelHeight: Int(screen.pixelSize.height),
            showsCursor: AppSettings.shared.includeCursor
        )

        guard let saved = LastAreaStore.load(displayID: screen.displayID) else {
            presentRegionOverlay(
                on: screen,
                image: image,
                allowsWindowPicking: true,
                skipActionBar: true,
                onSelected: { cropped, _ in
                    ClipboardService.copy(image: cropped)
                    NSSound(named: "Glass")?.play()
                }
            )
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = saved.intersection(imageBounds).integral
        if rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) {
            ClipboardService.copy(image: cropped)
            NSSound(named: "Glass")?.play()
        } else {
            presentRegionOverlay(
                on: screen,
                image: image,
                allowsWindowPicking: true,
                skipActionBar: true,
                onSelected: { cropped, _ in
                    ClipboardService.copy(image: cropped)
                    NSSound(named: "Glass")?.play()
                }
            )
        }
    }

    private func startWindowCapture() async throws {
        let (screen, image) = try await captureCurrentScreen()
        let windows = WindowCaptureService.windows(on: screen.displayID)
        guard !windows.isEmpty else { throw CaptureError.noWindow }

        let items = windows.map {
            WindowPickerView.Item(window: $0, rect: viewRect(for: $0.frame, screen: screen))
        }
        presentWindowPicker(on: screen, image: image, items: items)
    }

    private func startActiveWindowCapture() async throws {
        let pid = ActiveAppTracker.shared.lastActivePID
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid, pid != getpid() else { throw CaptureError.noActiveWindow }

        let windows = WindowCaptureService.windows().filter { $0.ownerPID == pid }
        guard let target = windows.first else { throw CaptureError.noActiveWindow }

        guard let screen = screen(containing: target.frame) ?? NSScreen.main else {
            throw CaptureError.noScreen
        }
        let scale = screen.backingScaleFactor
        let image = try await WindowCaptureService.capture(
            windowID: target.id,
            pixelWidth: Int((target.frame.width * scale).rounded()),
            pixelHeight: Int((target.frame.height * scale).rounded()),
            showsCursor: AppSettings.shared.includeCursor
        )
        commit(image)
    }

    // MARK: - Overlays

    private func startAdaptiveCapture() async throws {
        let (screen, image) = try await captureCurrentScreen()
        presentRegionOverlay(on: screen, image: image, allowsWindowPicking: true)
    }

    private func startAdaptiveCopyCapture() async throws {
        let (screen, image) = try await captureCurrentScreen()
        presentRegionOverlay(
            on: screen,
            image: image,
            allowsWindowPicking: true,
            skipActionBar: true,
            onSelected: { cropped, _ in
                ClipboardService.copy(image: cropped)
                NSSound(named: "Glass")?.play()
            }
        )
    }

    private func startScrollCapture(strategy: ScrollStrategy) async throws {
        let (screen, image) = try await captureCurrentScreen()
        pendingScrollStrategy = strategy
        presentRegionOverlay(
            on: screen,
            image: image,
            allowsWindowPicking: true,
            scrollMode: true,
            initialScrollStrategy: strategy,
            onScrollDirectionChanged: { [weak self] strategy in
                self?.pendingScrollStrategy = strategy
            },
            onScrollRegionSelected: { [weak self] pixelRect in
                guard let self else { return }
                self.dismissOverlay(hideApp: false)
                self.beginScrollSession(
                    on: screen,
                    pixelRect: pixelRect,
                    strategy: self.pendingScrollStrategy
                )
            }
        )
    }

    private func startCrossScreenCapture() async throws {
        guard let interactiveScreen = screenUnderMouse() else { throw CaptureError.noScreen }
        var images: [CGDirectDisplayID: CGImage] = [:]

        for screen in NSScreen.screens {
            guard let image = try? await ScreenCaptureService.capture(
                displayID: screen.displayID,
                pixelWidth: Int(screen.pixelSize.width),
                pixelHeight: Int(screen.pixelSize.height),
                showsCursor: false
            ) else { continue }
            images[screen.displayID] = image
        }

        guard !images.isEmpty else { throw CaptureError.noScreen }

        let controller = CrossScreenCaptureController(
            screens: NSScreen.screens,
            images: images,
            interactiveScreen: interactiveScreen
        )
        crossScreenController = controller
        controller.onComplete = { [weak self] selection in
            guard let self else { return }
            self.crossScreenController = nil
            let scale = interactiveScreen.backingScaleFactor
            if let composed = self.compositeCrossScreen(
                selection: selection,
                screens: NSScreen.screens,
                images: images,
                outputScale: scale
            ) {
                self.commit(composed)
            } else {
                self.showError(NSError(
                    domain: "Liteshot",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("跨屏合成失败。", "Failed to compose the cross-display capture.")]
                ))
            }
        }
        controller.onCancel = { [weak self] in
            self?.crossScreenController = nil
        }
        controller.start()
    }

    private func compositeCrossScreen(
        selection: CGRect,
        screens: [NSScreen],
        images: [CGDirectDisplayID: CGImage],
        outputScale: CGFloat
    ) -> CGImage? {
        let width = Int((selection.width * outputScale).rounded())
        let height = Int((selection.height * outputScale).rounded())
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        for screen in screens {
            guard let image = images[screen.displayID] else { continue }
            let intersection = selection.intersection(screen.frame)
            guard intersection.width > 1, intersection.height > 1 else { continue }

            let scale = screen.backingScaleFactor
            let localX = (intersection.minX - screen.frame.minX) * scale
            let localTop = (screen.frame.height - (intersection.maxY - screen.frame.minY)) * scale
            let pixelRect = CGRect(
                x: localX,
                y: localTop,
                width: intersection.width * scale,
                height: intersection.height * scale
            ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

            guard pixelRect.width > 0, pixelRect.height > 0,
                  let cropped = image.cropping(to: pixelRect) else { continue }

            let destination = CGRect(
                x: (intersection.minX - selection.minX) * outputScale,
                y: (selection.maxY - intersection.maxY) * outputScale,
                width: intersection.width * outputScale,
                height: intersection.height * outputScale
            )
            NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
                .draw(in: destination)
        }

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private func startRecognitionCapture(mode: CaptureMode) async throws {
        let (screen, image) = try await captureCurrentScreen()
        presentRegionOverlay(on: screen, image: image, onSelected: { [weak self] cropped, _ in
            self?.runRecognition(on: cropped, mode: mode)
        })
    }

    private func runRecognition(on image: CGImage, mode: CaptureMode) {
        Task { @MainActor in
            do {
                switch mode {
                case .ocr:
                    let text = try OCRService.recognizeText(in: image)
                    OCRResultWindowController.shared.show(title: L10n.t("OCR 结果", "OCR Result"), text: text)
                case .ocrSilent:
                    var text = try OCRService.recognizeText(in: image)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !AppSettings.shared.ocrPreserveNewlines {
                        text = text.replacingOccurrences(of: "\n", with: " ")
                    }
                    if text.isEmpty {
                        NSSound.beep()
                    } else {
                        let pasteboard = NSPasteboard.general
                        if AppSettings.shared.ocrAppendToClipboard,
                           let existing = pasteboard.string(forType: .string),
                           !existing.isEmpty {
                            pasteboard.clearContents()
                            pasteboard.setString(existing + "\n" + text, forType: .string)
                        } else {
                            pasteboard.clearContents()
                            pasteboard.setString(text, forType: .string)
                        }
                        NSSound(named: "Glass")?.play()
                    }
                case .qr:
                    let payloads = try OCRService.recognizeBarcodes(in: image)
                    OCRResultWindowController.shared.show(
                        title: L10n.t("二维码 / 条形码", "QR / Barcode"),
                        text: payloads.joined(separator: "\n")
                    )
                default:
                    break
                }
            } catch {
                showError(error)
            }
        }
    }

    private func beginScrollSession(on screen: NSScreen, pixelRect: CGRect, strategy: ScrollStrategy) {
        let session = ScrollCaptureSession(screen: screen, pixelRect: pixelRect, strategy: strategy)
        scrollSession = session

        session.onFinish = { [weak self] image in
            self?.scrollSession = nil
            self?.commit(image)
        }
        session.onCancel = { [weak self] in
            self?.scrollSession = nil
        }

        Task { @MainActor in
            do {
                try await session.start()
            } catch {
                self.scrollSession = nil
                self.showError(error)
            }
        }
    }

    private func presentRegionOverlay(
        on screen: NSScreen,
        image: CGImage,
        allowsWindowPicking: Bool = false,
        scrollMode: Bool = false,
        initialScrollStrategy: ScrollStrategy = .vertical,
        skipActionBar: Bool = false,
        onScrollDirectionChanged: ((ScrollStrategy) -> Void)? = nil,
        onScrollRegionSelected: ((CGRect) -> Void)? = nil,
        onSelected: ((CGImage, CGRect) -> Void)? = nil
    ) {
        let window = makeOverlayWindow(on: screen)
        let view = SelectionOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image,
            displayID: screen.displayID,
            allowsWindowPicking: allowsWindowPicking,
            scrollMode: scrollMode,
            initialScrollStrategy: initialScrollStrategy,
            skipActionBar: skipActionBar
        )
        if allowsWindowPicking, !scrollMode {
            view.onPickWindow = { [weak self] window in
                self?.handleWindowPick([window], on: screen)
            }
        }
        view.onScrollDirectionChanged = onScrollDirectionChanged
        view.onScrollRegionSelected = onScrollRegionSelected
        view.onRequestCaptureMode = { [weak self] mode in
            guard let self else { return }
            self.dismissOverlay(hideApp: false)
            self.begin(mode)
        }
        view.onRequestHistory = { [weak self] in
            guard let self else { return }
            self.dismissOverlay(hideApp: false)
            HistoryWindowController.shared.show()
        }
        if allowsWindowPicking, !scrollMode {
            view.onAction = { [weak self] action, image, pixelRect in
                guard let self else { return }
                switch action {
                case .copy:
                    self.dismissOverlay(hideApp: true)
                    ClipboardService.copy(image: image)
                    NSSound(named: "Glass")?.play()
                case .save:
                    self.dismissOverlay(hideApp: true)
                    let settings = AppSettings.shared
                    do {
                        let url = try SaveService.save(
                            image: image,
                            to: settings.saveDirectory,
                            format: settings.format,
                            quality: settings.jpegQuality,
                            template: settings.filenameTemplate
                        )
                        if settings.revealInFinder {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } catch {
                        self.showError(error)
                    }
                case .scroll:
                    self.dismissOverlay(hideApp: false)
                    self.beginScrollSession(on: screen, pixelRect: pixelRect, strategy: .vertical)
                case .ocr:
                    self.dismissOverlay(hideApp: false)
                    self.runRecognition(on: image, mode: .ocr)
                case .pin:
                    self.dismissOverlay(hideApp: true)
                    PinManager.shared.pin(image)
                case .close:
                    self.dismissOverlay(hideApp: true)
                }
            }
        }
        view.onComplete = { [weak self] cropped, pixelRect in
            LastAreaStore.save(pixelRect, displayID: screen.displayID)
            if let onSelected {
                self?.dismissOverlay(hideApp: true)
                onSelected(cropped, pixelRect)
            } else {
                self?.commit(cropped)
            }
        }
        view.onCancel = { [weak self] in
            self?.dismissOverlay()
        }

        window.contentView = view
        showOverlay(window, firstResponder: view)
    }

    private func presentWindowPicker(on screen: NSScreen, image: CGImage, items: [WindowPickerView.Item]) {
        let window = makeOverlayWindow(on: screen)
        let view = WindowPickerView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image,
            items: items
        )
        view.onPick = { [weak self] picked in
            self?.handleWindowPick(picked, on: screen)
        }
        view.onCancel = { [weak self] in
            self?.dismissOverlay()
        }

        window.contentView = view
        showOverlay(window, firstResponder: view)
    }

    private func handleWindowPick(_ windows: [CapturableWindow], on screen: NSScreen) {
        guard !windows.isEmpty else { return }
        dismissOverlay()

        Task { @MainActor in
            let scale = screen.backingScaleFactor
            var captured: [(CapturableWindow, CGImage)] = []

            for window in windows {
                do {
                    let image = try await WindowCaptureService.capture(
                        windowID: window.id,
                        pixelWidth: Int((window.frame.width * scale).rounded()),
                        pixelHeight: Int((window.frame.height * scale).rounded()),
                        showsCursor: AppSettings.shared.includeCursor
                    )
                    captured.append((window, image))
                } catch {
                    // 单个窗口失败不影响其余窗口。
                }
            }

            guard !captured.isEmpty else {
                showError(NSError(
                    domain: "Liteshot",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("窗口截取失败，窗口可能已经关闭。", "Window capture failed. The window may have closed.")]
                ))
                return
            }

            if captured.count == 1 {
                commit(captured[0].1)
                return
            }

            guard let composed = compositeWindows(captured, scale: scale) else {
                showError(NSError(
                    domain: "Liteshot",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("多窗口合成失败。", "Failed to compose the selected windows.")]
                ))
                return
            }
            commit(composed)
        }
    }

    /// 按屏幕相对位置把多个窗口合成一张透明背景图（后选窗口绘制在上层）。
    private func compositeWindows(
        _ windows: [(CapturableWindow, CGImage)],
        scale: CGFloat
    ) -> CGImage? {
        let union = windows.reduce(CGRect.null) { $0.union($1.0.frame) }
        let width = Int((union.width * scale).rounded())
        let height = Int((union.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        for (window, image) in windows.reversed() {
            let rect = CGRect(
                x: (window.frame.minX - union.minX) * scale,
                y: (window.frame.minY - union.minY) * scale,
                width: window.frame.width * scale,
                height: window.frame.height * scale
            )
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                .draw(in: rect)
        }

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private func makeOverlayWindow(on screen: NSScreen) -> NSWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.becomesKeyOnlyIfNeeded = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.setFrame(screen.frame, display: true)
        return window
    }

    private func showOverlay(_ window: NSWindow, firstResponder: NSView) {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        window.makeFirstResponder(firstResponder)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        overlayWindow = window
    }

    private func runCountdown(seconds: Int, completion: @escaping @MainActor () -> Void) {
        guard let screen = screenUnderMouse() else {
            completion()
            return
        }

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.becomesKeyOnlyIfNeeded = false
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = CountdownView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            total: seconds
        )
        window.contentView = view
        window.orderFrontRegardless()
        countdownWindow = window

        Task { @MainActor in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                view.remaining = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            window.orderOut(nil)
            window.contentView = nil
            self.countdownWindow = nil
            completion()
        }
    }

    // MARK: - Output

    private func commit(_ image: CGImage) {
        let settings = AppSettings.shared
        HistoryStore.shared.record(image)

        let exportOptions = ExportOptions(
            scale: settings.exportScale1x ? 0.5 : 1,
            cornerRadius: CGFloat(settings.exportCornerRadius),
            shadow: settings.exportShadow,
            shadowBlur: CGFloat(settings.exportShadowBlur),
            shadowOpacity: settings.exportShadowOpacity,
            shadowColorHex: settings.exportShadowColorHex,
            transparent: settings.exportTransparent
        )
        let output = EditorRenderer.render(image: image, annotations: [], options: exportOptions) ?? image

        // 没开自动保存时至少保证剪贴板有内容，避免“截了个寂寞”。
        if settings.copyToClipboard || !settings.autoSave {
            ClipboardService.copy(image: output)
        }

        if settings.autoSave {
            do {
                let url = try SaveService.save(
                    image: output,
                    to: settings.saveDirectory,
                    format: settings.format,
                    quality: settings.jpegQuality,
                    template: settings.filenameTemplate
                )
                if settings.revealInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                showError(error)
            }
        }

        NSSound(named: "Glass")?.play()
        dismissOverlay()
    }

    private func dismissOverlay(hideApp: Bool = true) {
        overlayWindow?.orderOut(nil)
        overlayWindow?.contentView = nil
        overlayWindow = nil

        countdownWindow?.orderOut(nil)
        countdownWindow?.contentView = nil
        countdownWindow = nil

        NSCursor.arrow.set()
        if hideApp {
            // 把焦点还给用户原来的 App；用 deactivate 而不是 hide，
            // 否则已有的钉图窗口会跟着整个 App 一起被隐藏。
            NSApp.deactivate()
        }
    }

    // MARK: - Helpers

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screen(containing cgRect: CGRect) -> NSScreen? {
        NSScreen.screens
            .filter { CGDisplayBounds($0.displayID).intersects(cgRect) }
            .max { lhs, rhs in
                CGDisplayBounds(lhs.displayID).intersection(cgRect).area
                    < CGDisplayBounds(rhs.displayID).intersection(cgRect).area
            }
    }

    /// CG 全局坐标（左上原点）→ 覆盖层视图坐标（左下原点）。
    private func viewRect(for cgRect: CGRect, screen: NSScreen) -> CGRect {
        let display = CGDisplayBounds(screen.displayID)
        let x = cgRect.minX - display.minX
        let top = cgRect.minY - display.minY
        let y = display.height - top - cgRect.height
        return CGRect(x: x, y: y, width: cgRect.width, height: cgRect.height)
    }

    private func showError(_ error: Error) {
        // 覆盖层在 screenSaver 层级，模态框会被压在下面、整个 App 看起来卡死。
        if overlayWindow != nil {
            dismissOverlay(hideApp: false)
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.t("截图失败", "Capture Failed")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.t("好", "OK"))
        _ = presentAlertOnActiveScreen(alert)
    }

    /// 多显示器时把模态框放到鼠标所在屏幕，避免弹到别的屏幕上。
    private func presentAlertOnActiveScreen(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.layout()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        if let screen {
            let size = alert.window.frame.size
            let target = CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            )
            alert.window.setFrameOrigin(target)
            NSApp.activate(ignoringOtherApps: true)
            // runModal 可能按当前活动屏幕重新居中；在模态循环里再拉回鼠标所在屏幕。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                alert.window.setFrameOrigin(target)
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        return alert.runModal()
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
