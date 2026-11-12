import AppKit

enum SelectionAction: Int {
    case copy
    case save
    case pin
    case scroll
    case ocr
    case close
}

/// 覆盖全屏的截图选区窗口：置顶到屏幕保护程序层级，盖住普通窗口与全屏 App。
/// 用 nonactivatingPanel，即使 App 没被系统激活也能拿到键盘焦点，
/// 避免热键唤起覆盖层后 Esc / 文字输入失灵。
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // 截图覆盖层要瞬间出现/消失，不要系统窗口的缩放/淡入动画。
        animationBehavior = .none
    }
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
    private let scrollMode: Bool
    private let skipActionBar: Bool
    private var windowHits: [WindowHit] = []
    private var hoveredWindowIndex: Int?
    private var selectedWindows: [WindowHit] = []
    private var didDrag = false
    private var scrollStrategy: ScrollStrategy
    private var directionButtons: [NSButton] = []
    private var aspectLocked = false
    private var lockedAspect: CGFloat = 1
    private var lockButton: NSButton?

    var onComplete: ((CGImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onPickWindow: ((CapturableWindow) -> Void)?
    var onScrollDirectionChanged: ((ScrollStrategy) -> Void)?
    var onScrollRegionSelected: ((CGRect) -> Void)?
    var onAction: ((SelectionAction, CGImage, CGRect) -> Void)?
    /// 顶部悬浮模式条：全屏 / 滚动 / 跨屏 / 延迟 / 上次区域 / OCR / 二维码 / 历史。
    var onRequestCaptureMode: ((CaptureMode) -> Void)?
    var onRequestHistory: (() -> Void)?

    // MARK: - 内联编辑状态

    private var actionBar: NSView?
    private var canvas: EditorCanvasView?
    private var annotationDocument: EditorDocument?
    private var pendingImage: CGImage?
    private var pendingPixelRect: CGRect?
    /// 选区/窗口在覆盖层里的视图矩形（左下原点，point）。
    private var editingViewRect: CGRect?
    private var sizeLabel: NSView?
    private var toolButtons: [AnnotationTool: ToolbarIconButton] = [:]
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private var moveButton: ToolbarIconButton?
    private var chrome: SelectionChromeView?
    private var selectionMoveMode = false
    private var colorSwatches: [ColorSwatchButton] = []
    private var modeBar: NSView?
    private var escMonitor: Any?

    private var showsActionBar: Bool { allowsWindowPicking && !scrollMode && !skipActionBar }
    private var isEditing: Bool { pendingImage != nil }

    private var highlightColor: NSColor {
        NSColor(hex: AppSettings.shared.highlightColorHex) ?? .controlAccentColor
    }

    init(
        frame: NSRect,
        image: CGImage,
        displayID: CGDirectDisplayID,
        allowsWindowPicking: Bool = false,
        scrollMode: Bool = false,
        initialScrollStrategy: ScrollStrategy = .vertical,
        skipActionBar: Bool = false
    ) {
        self.image = image
        self.displayImage = NSImage(cgImage: image, size: frame.size)
        self.allowsWindowPicking = allowsWindowPicking
        self.scrollMode = scrollMode
        self.skipActionBar = skipActionBar
        self.scrollStrategy = initialScrollStrategy
        super.init(frame: frame)
        wantsLayer = true
        loadSnapGuides(displayID: displayID)
        if allowsWindowPicking {
            loadWindowHits(displayID: displayID)
        }
        if scrollMode {
            setupDirectionButtons()
        }
        if allowsWindowPicking, !scrollMode {
            setupLockButton()
            setupModeBar()
        }
    }

    // MARK: - 顶部模式条

    private enum OverlayCommand: Int {
        case fullScreen
        case scroll
        case crossScreen
        case delayed
        case lastArea
        case ocr
        case qr
        case history
    }

    private func setupModeBar() {
        let items: [(OverlayCommand, String, String)] = [
            (.fullScreen, "arrow.up.left.and.arrow.down.right", L10n.t("全屏截图", "Full screen")),
            (.scroll, "arrow.up.and.down", L10n.t("滚动截图", "Scrolling capture")),
            (.crossScreen, "rectangle.split.2x1", L10n.t("跨屏区域", "Cross-display region")),
            (.delayed, "timer", L10n.t("延迟截图", "Delayed capture")),
            (.lastArea, "arrow.counterclockwise", L10n.t("上一次区域", "Last area")),
            (.ocr, "text.viewfinder", L10n.t("识别文字", "OCR")),
            (.qr, "qrcode", L10n.t("二维码 / 条形码", "QR / barcode")),
            (.history, "clock.arrow.circlepath", L10n.t("截图历史", "Capture history")),
        ]

        let buttonSize: CGFloat = 32
        let gap: CGFloat = 4
        let padding: CGFloat = 6
        let width = padding * 2 + buttonSize * CGFloat(items.count) + gap * CGFloat(items.count - 1)
        let height = buttonSize + padding * 2

        let bar = ToolbarBarView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        bar.layer?.cornerRadius = 9
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        var x = padding
        for (command, symbol, title) in items {
            let button = ToolbarIconButton(title: "", target: self, action: #selector(modeTapped(_:)))
            button.tag = command.rawValue
            button.isBordered = false
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(configuration)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .white
            button.wantsLayer = true
            button.layer?.cornerRadius = 4
            button.toolTip = title
            button.frame = CGRect(x: x, y: padding, width: buttonSize, height: buttonSize)
            bar.addSubview(button)
            x += buttonSize + gap
        }

        addSubview(bar)
        modeBar = bar
    }

    @objc private func modeTapped(_ sender: NSButton) {
        guard let command = OverlayCommand(rawValue: sender.tag) else { return }
        switch command {
        case .fullScreen:
            selectFullScreen()
        case .scroll:
            onRequestCaptureMode?(.scroll)
        case .crossScreen:
            onRequestCaptureMode?(.crossScreen)
        case .delayed:
            onRequestCaptureMode?(.delayed)
        case .lastArea:
            onRequestCaptureMode?(.lastArea)
        case .ocr:
            onRequestCaptureMode?(.ocr)
        case .qr:
            onRequestCaptureMode?(.qr)
        case .history:
            onRequestHistory?()
        }
    }

    private func selectFullScreen() {
        modeBar?.isHidden = true
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        showEditingToolbar(image: image, pixelRect: full, viewRect: bounds)
    }

    private func setupLockButton() {
        let button = CursorButton(title: "", target: self, action: #selector(toggleAspectLock))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.contentTintColor = .white
        button.toolTip = L10n.t("锁定比例 (R)", "Lock Aspect Ratio (R)")
        addSubview(button)
        lockButton = button
        updateLockButton()
    }

    private func updateLockButton() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        lockButton?.image = NSImage(
            systemSymbolName: aspectLocked ? "lock.fill" : "lock.open",
            accessibilityDescription: L10n.t("锁定比例", "Lock Aspect Ratio")
        )?.withSymbolConfiguration(configuration)
    }

    @objc private func toggleAspectLock() {
        aspectLocked.toggle()
        if aspectLocked {
            if selection.width > 2, selection.height > 2 {
                lockedAspect = selection.width / selection.height
            } else {
                lockedAspect = 1
            }
        }
        updateLockButton()
        needsDisplay = true
    }

    private func setupDirectionButtons() {
        let titles = [
            L10n.t("竖向", "Vertical"),
            L10n.t("横向", "Horizontal"),
            L10n.t("全景", "Panorama"),
        ]
        for (index, title) in titles.enumerated() {
            let button = CursorButton(title: title, target: self, action: #selector(directionTapped(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = .white
            addSubview(button)
            directionButtons.append(button)
        }
        updateDirectionButtons()
    }

    private func updateDirectionButtons() {
        let selected: Int
        switch scrollStrategy {
        case .vertical: selected = 0
        case .horizontal: selected = 1
        case .panorama: selected = 2
        }
        for (index, button) in directionButtons.enumerated() {
            button.layer?.backgroundColor = (index == selected
                ? highlightColor
                : NSColor.black.withAlphaComponent(0.55)).cgColor
        }
    }

    @objc private func directionTapped(_ sender: NSButton) {
        switch sender.tag {
        case 0: scrollStrategy = .vertical
        case 1: scrollStrategy = .horizontal
        default: scrollStrategy = .panorama
        }
        updateDirectionButtons()
        onScrollDirectionChanged?(scrollStrategy)
    }

    /// 顶部可用边界（视图坐标）：菜单栏/刘海下沿。
    private var safeTopEdge: CGFloat {
        guard let screen = window?.screen ?? NSScreen.main else { return bounds.height }
        let edge = screen.visibleFrame.maxY - screen.frame.minY
        return min(bounds.height, max(0, edge))
    }

    /// 底部可用边界（视图坐标）：Dock 上沿。
    private var safeBottomEdge: CGFloat {
        guard let screen = window?.screen ?? NSScreen.main else { return 0 }
        return max(0, screen.visibleFrame.minY - screen.frame.minY)
    }

    override func layout() {
        super.layout()
        if let modeBar {
            // 模式条放在菜单栏/刘海下方，避免被刘海挡住。
            modeBar.frame.origin = CGPoint(
                x: (bounds.width - modeBar.frame.width) / 2,
                y: safeTopEdge - modeBar.frame.height - 10
            )
        }
        if let lockButton {
            lockButton.frame = CGRect(x: bounds.width - 44, y: bounds.height - 88, width: 32, height: 32)
        }
        guard scrollMode else { return }
        let width: CGFloat = 64
        let height: CGFloat = 24
        let gap: CGFloat = 8
        let total = width * CGFloat(directionButtons.count) + gap * CGFloat(max(0, directionButtons.count - 1))
        var x = (bounds.width - total) / 2
        let y = bounds.height - 72
        for button in directionButtons {
            button.frame = CGRect(x: x, y: y, width: width, height: height)
            x += width + gap
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
        // windowHits 按 CGWindowList 的前后顺序插入（前 → 后），
        // 取第一个包含光标的窗口才是屏幕上真正可见的那一个。
        // 不能按“最小面积”挑：那会把被大窗口盖住的 Finder 窗口也算进来。
        windowHits.firstIndex { $0.rect.contains(point) }
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func installEscapeMonitorIfNeeded() {
        guard window != nil, escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            // Esc 永远退出截图：不依赖当前第一响应者（文字框 / 颜色面板 / 画布）。
            self.onCancel?()
            return nil
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resetCursorRects() {
        // 框选阶段用十字；选区定下来、工具条出现后恢复普通箭头，
        // 否则鼠标移到工具条/按钮上时仍然显示十字。
        addCursorRect(bounds, cursor: isEditing ? .arrow : .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
        installEscapeMonitorIfNeeded()

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

        let maskColor = NSColor(hex: AppSettings.shared.maskColorHex) ?? .black
        maskColor.withAlphaComponent(AppSettings.shared.maskOpacity).setFill()
        bounds.fill()

        if selection.width == 0,
           !isEditing,
           allowsWindowPicking,
           let index = hoveredWindowIndex,
           windowHits.indices.contains(index) {
            let hit = windowHits[index]

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: hit.rect).addClip()
            displayImage.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            highlightColor.setStroke()
            let border = NSBezierPath(rect: hit.rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()

            drawWindowTitle(for: hit)
        }

        for (order, hit) in selectedWindows.enumerated() {
            highlightColor.setStroke()
            let border = NSBezierPath(rect: hit.rect.insetBy(dx: 2, dy: 2))
            border.lineWidth = 3
            border.stroke()
            drawWindowBadge(
                number: order + 1,
                at: CGPoint(x: hit.rect.minX, y: hit.rect.maxY)
            )
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

            if !isEditing {
                drawSizeLabel()
            }
        } else if !isEditing {
            drawHint()
        }

        drawSnapGuides()
        if !isEditing, dragStart != nil || selection.width == 0 {
            drawMagnifier()
        }
        drawStatus()
    }

    private func drawWindowBadge(number: Int, at point: CGPoint) {
        let radius: CGFloat = 11
        let center = CGPoint(
            x: min(max(point.x + radius + 4, radius + 4), bounds.width - radius - 4),
            y: min(max(point.y - radius - 4, radius + 4), bounds.height - radius - 4)
        )
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        highlightColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.setStroke()
        let outline = NSBezierPath(ovalIn: circle)
        outline.lineWidth = 1.5
        outline.stroke()

        let text = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
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

    private func compositeSelectedWindows() -> (image: CGImage, pixelRect: CGRect, viewRect: CGRect)? {
        guard !selectedWindows.isEmpty else { return nil }
        let union = selectedWindows.reduce(CGRect.null) { $0.union($1.rect) }.intersection(bounds)
        guard union.width >= 1, union.height >= 1 else { return nil }
        let pixels = pixelRect(for: union)
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: Int(pixels.width),
            height: Int(pixels.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(pixels.height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        for hit in selectedWindows {
            let windowPixels = pixelRect(for: hit.rect)
            guard let cropped = image.cropping(to: windowPixels) else { continue }
            let destination = CGRect(
                x: (hit.rect.minX - union.minX) * scaleX,
                y: (union.maxY - hit.rect.maxY) * scaleY,
                width: hit.rect.width * scaleX,
                height: hit.rect.height * scaleY
            )
            NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
                .draw(in: destination)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let composed = context.makeImage() else { return nil }
        return (composed, pixels, union)
    }

    // MARK: - 内联编辑工具条

    private enum BarEntry {
        case tool(AnnotationTool)
        case move
        case colors
        case undo
        case redo
        case action(SelectionAction)
        case separator
    }

    private static let palette: [(hex: String, name: String)] = [
        ("#FF3B30", "红"),
        ("#FFD60A", "黄"),
        ("#34C759", "绿"),
        ("#0A84FF", "蓝"),
        ("#FFFFFF", "白"),
        ("#000000", "黑"),
    ]

    private func showEditingToolbar(
        image: CGImage,
        pixelRect: CGRect,
        viewRect: CGRect,
        annotations: [Annotation] = [],
        initialTool: AnnotationTool = .select,
        moveMode: Bool? = nil
    ) {
        dismissEditing()
        if let moveMode {
            selectionMoveMode = moveMode
        }

        pendingImage = image
        pendingPixelRect = pixelRect
        editingViewRect = viewRect

        let document = EditorDocument()
        for annotation in annotations {
            document.add(annotation)
        }
        let canvas = EditorCanvasView(image: image, document: document)
        canvas.inlineMode = true
        canvas.frame = viewRect
        canvas.tool = selectionMoveMode ? .select : initialTool
        canvas.currentStyle = ToolStyleStore.style(for: canvas.tool)
        canvas.onFinishRequest = { [weak self] in
            self?.perform(.copy)
        }
        canvas.onCancelRequest = { [weak self] in
            self?.onCancel?()
        }
        canvas.onSaveRequest = { [weak self] in
            self?.perform(.save)
        }
        document.onChange = { [weak self] in
            self?.canvas?.needsDisplay = true
            self?.updateUndoState()
        }
        addSubview(canvas)
        self.annotationDocument = document
        self.canvas = canvas

        let chrome = SelectionChromeView(frame: bounds)
        chrome.rect = viewRect
        chrome.moveMode = selectionMoveMode
        chrome.onPreview = { [weak self] rect in
            self?.previewSelectionFrame(rect)
        }
        chrome.onCommit = { [weak self] rect in
            self?.commitSelectionFrame(rect)
        }
        addSubview(chrome)
        self.chrome = chrome

        lockButton?.isHidden = true
        modeBar?.isHidden = true

        buildToolbar(for: viewRect)
        updateSizeLabel(for: viewRect)
        updateUndoState()

        window?.invalidateCursorRects(for: self)
        window?.invalidateCursorRects(for: canvas)
        NSCursor.arrow.set()
        window?.makeFirstResponder(canvas)
        needsDisplay = true
    }

    private func buildToolbar(for selection: CGRect) {
        let entries: [BarEntry] = [
            .tool(.select),
            .move,
            .tool(.rectangle),
            .tool(.ellipse),
            .tool(.arrow),
            .tool(.pencil),
            .tool(.highlight),
            .tool(.mosaic),
            .tool(.counter),
            .tool(.text),
            .separator,
            .colors,
            .separator,
            .undo,
            .redo,
            .separator,
            .action(.pin),
            .action(.scroll),
            .action(.ocr),
            .separator,
            .action(.save),
            .action(.close),
            .action(.copy),
        ]

        let buttonWidth: CGFloat = 30
        let buttonHeight: CGFloat = 28
        let gap: CGFloat = 3
        let padding: CGFloat = 6
        let separatorWidth: CGFloat = 7
        let barHeight = buttonHeight + padding * 2

        let swatchSize: CGFloat = 20
        let swatchGap: CGFloat = 4
        let paletteWidth = swatchSize * CGFloat(Self.palette.count)
            + swatchGap * CGFloat(Self.palette.count - 1)

        func width(of entry: BarEntry) -> CGFloat {
            switch entry {
            case .separator: return separatorWidth
            case .colors: return paletteWidth
            default: return buttonWidth
            }
        }

        let totalWidth = entries.reduce(padding * 2) { $0 + width(of: $1) }
            + gap * CGFloat(max(0, entries.count - 1))

        let bar = ToolbarBarView(frame: .zero)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.84).cgColor
        bar.layer?.cornerRadius = 8
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        var x = padding
        for entry in entries {
            let w = width(of: entry)
            switch entry {
            case .separator:
                let line = NSView(frame: CGRect(x: x + 3, y: padding + 4, width: 1, height: buttonHeight - 8))
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
                bar.addSubview(line)

            case .tool(let tool):
                let button = ToolbarIconButton(title: "", target: self, action: #selector(toolTapped(_:)))
                button.tag = AnnotationTool.allCases.firstIndex(of: tool) ?? 0
                button.isBordered = false
                let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = NSImage(
                    systemSymbolName: tool.symbolName,
                    accessibilityDescription: tool.title
                )?.withSymbolConfiguration(configuration)
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                button.contentTintColor = .white
                button.wantsLayer = true
                button.layer?.cornerRadius = 4
                button.toolTip = tool.title
                button.frame = CGRect(x: x, y: padding, width: w, height: buttonHeight)
                button.baseBackground = tool == .select
                    ? NSColor.white.withAlphaComponent(0.18)
                    : .clear
                bar.addSubview(button)
                toolButtons[tool] = button

            case .colors:
                colorSwatches.removeAll()
                var swatchX = x
                for (index, entry) in Self.palette.enumerated() {
                    let swatch = ColorSwatchButton(
                        title: "",
                        target: self,
                        action: #selector(colorSwatchTapped(_:))
                    )
                    swatch.tag = index
                    swatch.isBordered = false
                    swatch.wantsLayer = true
                    swatch.layer?.cornerRadius = (swatchSize - 2) / 2
                    swatch.swatchColor = NSColor(hex: entry.hex) ?? .systemRed
                    swatch.swatchHex = entry.hex
                    swatch.toolTip = L10n.t("颜色", "Color") + " · " + entry.name
                    swatch.frame = CGRect(
                        x: swatchX,
                        y: padding + (buttonHeight - swatchSize) / 2,
                        width: swatchSize,
                        height: swatchSize
                    )
                    bar.addSubview(swatch)
                    colorSwatches.append(swatch)
                    swatchX += swatchSize + swatchGap
                }

            case .move:
                let button = ToolbarIconButton(title: "", target: self, action: #selector(moveTapped))
                button.isBordered = false
                let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = NSImage(
                    systemSymbolName: "arrow.up.left.and.arrow.down.right",
                    accessibilityDescription: L10n.t("移动选区", "Move selection")
                )?.withSymbolConfiguration(configuration)
                button.imagePosition = .imageOnly
                button.contentTintColor = .white
                button.wantsLayer = true
                button.layer?.cornerRadius = 4
                button.toolTip = L10n.t("移动 / 调整选区", "Move / resize selection")
                button.frame = CGRect(x: x, y: padding, width: w, height: buttonHeight)
                bar.addSubview(button)
                moveButton = button

            case .redo:
                let button = ToolbarIconButton(title: "", target: self, action: #selector(redoTapped))
                button.isBordered = false
                let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = NSImage(
                    systemSymbolName: "arrow.uturn.forward",
                    accessibilityDescription: L10n.t("重做", "Redo")
                )?.withSymbolConfiguration(configuration)
                button.imagePosition = .imageOnly
                button.contentTintColor = .white
                button.wantsLayer = true
                button.layer?.cornerRadius = 4
                button.toolTip = L10n.t("重做 (⇧⌘Z)", "Redo (⇧⌘Z)")
                button.frame = CGRect(x: x, y: padding, width: w, height: buttonHeight)
                bar.addSubview(button)
                redoButton = button

            case .undo:
                let button = ToolbarIconButton(title: "", target: self, action: #selector(undoTapped))
                button.isBordered = false
                let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = NSImage(
                    systemSymbolName: "arrow.uturn.backward",
                    accessibilityDescription: L10n.t("撤销", "Undo")
                )?.withSymbolConfiguration(configuration)
                button.imagePosition = .imageOnly
                button.contentTintColor = .white
                button.wantsLayer = true
                button.layer?.cornerRadius = 4
                button.toolTip = L10n.t("撤销 (⌘Z)", "Undo (⌘Z)")
                button.frame = CGRect(x: x, y: padding, width: w, height: buttonHeight)
                bar.addSubview(button)
                undoButton = button

            case .action(let action):
                let item = actionPresentation(action)
                let button = ToolbarIconButton(title: "", target: self, action: #selector(actionTapped(_:)))
                button.tag = action.rawValue
                button.isBordered = false
                let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = NSImage(
                    systemSymbolName: item.symbol,
                    accessibilityDescription: item.title
                )?.withSymbolConfiguration(configuration)
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                switch action {
                case .copy: button.contentTintColor = .systemGreen
                case .close: button.contentTintColor = .systemRed
                default: button.contentTintColor = .white
                }
                button.wantsLayer = true
                button.layer?.cornerRadius = 4
                button.toolTip = item.tooltip
                button.frame = CGRect(x: x, y: padding, width: w, height: buttonHeight)
                bar.addSubview(button)
            }
            x += w + gap
        }

        var originX = selection.midX - totalWidth / 2
        originX = min(max(originX, 8), bounds.width - totalWidth - 8)

        let barGap: CGFloat = 8
        let topLimit = safeTopEdge - barHeight - 8
        let bottomLimit = safeBottomEdge + 8
        var originY: CGFloat
        if selection.minY - barHeight - barGap >= bottomLimit {
            // 选区下方有空间：放在下方（QQ / 微信截图的位置）。
            originY = selection.minY - barHeight - barGap
        } else if selection.maxY + barHeight + barGap <= topLimit + barHeight {
            // 下方不够，放选区上方。
            originY = selection.maxY + barGap
        } else {
            // 选区几乎占满屏幕（含全屏）：贴在 Dock 上方，避开刘海。
            originY = bottomLimit
        }
        originY = min(max(originY, bottomLimit), topLimit)

        bar.frame = CGRect(x: originX, y: originY, width: totalWidth, height: barHeight)
        addSubview(bar)
        actionBar = bar

        updateToolSelection()
    }

    private func actionPresentation(_ action: SelectionAction) -> (title: String, symbol: String, tooltip: String) {
        switch action {
        case .copy:
            return (
                L10n.t("完成", "Done"),
                "checkmark",
                L10n.t("完成并复制 (Enter / ⌘C)", "Finish and copy (Enter / ⌘C)")
            )
        case .save:
            return (
                L10n.t("保存", "Save"),
                "square.and.arrow.down",
                L10n.t("保存到文件夹 (⌘S)", "Save to folder (⌘S)")
            )
        case .pin:
            return (L10n.t("钉图", "Pin"), "pin", L10n.t("钉在屏幕上", "Pin on screen"))
        case .scroll:
            return (L10n.t("滚动截图", "Scroll"), "arrow.up.and.down", L10n.t("滚动截图", "Scrolling capture"))
        case .ocr:
            return ("OCR", "text.viewfinder", L10n.t("识别文字", "Recognize text"))
        case .close:
            return (L10n.t("取消", "Cancel"), "xmark", L10n.t("取消截图 (Esc)", "Cancel capture (Esc)"))
        }
    }

    private func updateToolSelection() {
        let active = canvas?.tool ?? .select
        for (tool, button) in toolButtons {
            button.baseBackground = (!selectionMoveMode && tool == active)
                ? NSColor.white.withAlphaComponent(0.18)
                : .clear
        }
        moveButton?.baseBackground = selectionMoveMode
            ? NSColor.white.withAlphaComponent(0.18)
            : .clear
        let activeHex = canvas.map { ToolStyleStore.style(for: $0.tool).colorHex }
        for swatch in colorSwatches {
            swatch.isActive = swatch.swatchHex == activeHex
        }
    }

    private func updateUndoState() {
        undoButton?.isEnabled = annotationDocument?.canUndo ?? false
        redoButton?.isEnabled = annotationDocument?.canRedo ?? false
    }

    private func previewSelectionFrame(_ rect: CGRect) {
        guard isEditing else { return }
        selection = rect
        chrome?.sizeText = "\\(Int(pixelRect(for: rect).width)) × \\(Int(pixelRect(for: rect).height))"
        canvas?.isHidden = true
        actionBar?.isHidden = true
        sizeLabel?.isHidden = true
        needsDisplay = true
    }

    private func commitSelectionFrame(_ rect: CGRect) {
        guard let oldView = editingViewRect, let oldPixel = pendingPixelRect else { return }
        canvas?.commitPendingText()
        let annotations = annotationDocument?.annotations ?? []
        let tool = canvas?.tool ?? .select
        let move = selectionMoveMode

        if rect == oldView {
            chrome?.sizeText = ""
            canvas?.isHidden = false
            actionBar?.isHidden = false
            sizeLabel?.isHidden = false
            needsDisplay = true
            return
        }

        let newPixel = pixelRect(for: rect)
        guard newPixel.width >= 1, newPixel.height >= 1,
              let cropped = image.cropping(to: newPixel) else {
            chrome?.sizeText = ""
            canvas?.isHidden = false
            actionBar?.isHidden = false
            sizeLabel?.isHidden = false
            needsDisplay = true
            return
        }

        let dx = oldPixel.minX - newPixel.minX
        let dy = oldPixel.minY - newPixel.minY
        var moved: [Annotation] = []
        for var annotation in annotations {
            annotation.translate(dx: dx, dy: dy)
            moved.append(annotation)
        }

        selection = rect
        selectionMoveMode = move
        dismissEditing()
        selection = rect
        showEditingToolbar(
            image: cropped,
            pixelRect: newPixel,
            viewRect: rect,
            annotations: moved,
            initialTool: tool,
            moveMode: move
        )
        needsDisplay = true
    }

    private func updateSizeLabel(for rect: CGRect) {
        sizeLabel?.removeFromSuperview()
        sizeLabel = nil

        guard let pixelRect = pendingPixelRect else { return }
        let text = "\(Int(pixelRect.width)) × \(Int(pixelRect.height))"
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        let textSize = label.sizeThatFits(NSSize(width: 240, height: 20))

        let container = NSView(frame: CGRect(
            x: 0,
            y: 0,
            width: textSize.width + 14,
            height: textSize.height + 6
        ))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        container.layer?.cornerRadius = 4
        label.frame = CGRect(x: 7, y: 3, width: textSize.width, height: textSize.height)
        container.addSubview(label)

        var originY = rect.maxY - container.frame.height - 8
        if originY < rect.minY + 2 {
            originY = rect.maxY + 6
        }
        originY = min(max(originY, 8), bounds.height - container.frame.height - 8)
        let originX = min(
            max(rect.minX + 8, 8),
            bounds.width - container.frame.width - 8
        )
        container.frame.origin = CGPoint(x: originX, y: originY)
        addSubview(container)
        sizeLabel = container
    }

    private func dismissEditing() {
        canvas?.commitPendingText()
        canvas?.removeFromSuperview()
        canvas = nil
        annotationDocument = nil
        actionBar?.removeFromSuperview()
        actionBar = nil
        sizeLabel?.removeFromSuperview()
        sizeLabel = nil
        toolButtons.removeAll()
        undoButton = nil
        redoButton = nil
        moveButton = nil
        chrome?.removeFromSuperview()
        chrome = nil
        colorSwatches.removeAll()
        pendingImage = nil
        pendingPixelRect = nil
        editingViewRect = nil
        lockButton?.isHidden = false
        modeBar?.isHidden = scrollMode
        window?.invalidateCursorRects(for: self)
        NSCursor.crosshair.set()
    }

    private func bakeImage() -> CGImage? {
        guard let image = pendingImage else { return nil }
        let annotations = annotationDocument?.annotations ?? []

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
        return EditorRenderer.render(image: image, annotations: annotations, options: options) ?? image
    }

    @objc private func toolTapped(_ sender: NSButton) {
        let tools = AnnotationTool.allCases
        guard tools.indices.contains(sender.tag) else { return }
        canvas?.commitPendingText()
        selectionMoveMode = false
        chrome?.moveMode = false
        let tool = tools[sender.tag]
        canvas?.tool = tool
        if let canvas {
            canvas.currentStyle = ToolStyleStore.style(for: tool)
        }
        updateToolSelection()
    }

    @objc private func colorSwatchTapped(_ sender: ColorSwatchButton) {
        guard let canvas else { return }
        let target: AnnotationTool = canvas.tool.isDrawingTool ? canvas.tool : .rectangle
        var style = ToolStyleStore.style(for: target)
        style.colorHex = sender.swatchHex
        ToolStyleStore.save(style, for: target)
        if target == canvas.tool {
            canvas.currentStyle = style
        }
        updateToolSelection()
    }

    @objc private func undoTapped() {
        annotationDocument?.undo()
        canvas?.select(id: nil)
        canvas?.needsDisplay = true
        updateUndoState()
    }

    @objc private func redoTapped() {
        annotationDocument?.redo()
        canvas?.select(id: nil)
        canvas?.needsDisplay = true
        updateUndoState()
    }

    @objc private func moveTapped() {
        canvas?.commitPendingText()
        selectionMoveMode = true
        canvas?.tool = .select
        chrome?.moveMode = true
        updateToolSelection()
    }

    @objc private func actionTapped(_ sender: NSButton) {
        guard let action = SelectionAction(rawValue: sender.tag) else { return }
        perform(action)
    }

    private func perform(_ action: SelectionAction) {
        guard let image = pendingImage, let pixelRect = pendingPixelRect else { return }
        // 复制/保存之前把正在输入的文字落成标注，避免漏字。
        canvas?.commitPendingText()
        switch action {
        case .close:
            onCancel?()
        case .copy, .save, .pin:
            onAction?(action, bakeImage() ?? image, pixelRect)
        case .scroll, .ocr:
            onAction?(action, image, pixelRect)
        }
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
        if scrollMode {
            text = L10n.t(
                "拖拽选区或点击窗口 · 选择滚动方向 · Esc 取消",
                "Drag a region or click a window · Choose a scroll direction · Esc cancels"
            )
        } else if allowsWindowPicking {
            if selectedWindows.isEmpty {
                text = L10n.t(
                    "拖拽选择区域 · 点击窗口直接截取 · Esc 取消",
                    "Drag to select · Click a window to capture it · Esc cancels"
                )
            } else {
                text = L10n.t("已选 ", "Selected ") + "\(selectedWindows.count) " + L10n.t(
                    "个窗口 · Enter 完成 · Shift 继续加选 · Esc 取消",
                    "windows · Enter to finish · Shift to add · Esc cancels"
                )
            }
        } else {
            text = L10n.t("拖拽选择区域 · C 复制色值 · Esc / 右键取消", "Drag to select · C copies color · Esc / right-click cancels")
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let modeBarVisible = !(modeBar?.isHidden ?? true)
        let hintOffset: CGFloat = scrollMode ? 104 : (modeBarVisible ? 96 : 40)
        let origin = CGPoint(
            x: (bounds.width - size.width - 24) / 2,
            y: safeTopEdge - size.height - hintOffset
        )
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
        if AppSettings.shared.sizeLabelAtTop {
            origin.y = selection.maxY + 10
            if origin.y + size.height + 10 > bounds.height {
                origin.y = selection.minY - size.height - 10
            }
        } else if origin.y < 6 {
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

        if allowsWindowPicking, dragStart == nil, selection.width == 0, !isEditing {
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

        if isEditing {
            // 内联画布只盖住选区本身；这里收到的是选区外的点击：开始重新框选。
            dismissEditing()
            selection = .zero
            dragStart = nil
            needsDisplay = true
        }

        if allowsWindowPicking, !scrollMode,
           event.modifierFlags.contains(.shift),
           let index = topmostWindowIndex(at: raw),
           windowHits.indices.contains(index) {
            let hit = windowHits[index]
            if let position = selectedWindows.firstIndex(where: { $0.window.id == hit.window.id }) {
                selectedWindows.remove(at: position)
            } else {
                selectedWindows.append(hit)
            }
            dragStart = nil
            selection = .zero
            needsDisplay = true
            return
        }

        if !selectedWindows.isEmpty {
            selectedWindows.removeAll()
        }

        let x = snapped(raw.x, guides: snapGuidesX)
        let y = snapped(raw.y, guides: snapGuidesY)
        activeSnapX = x.guide
        activeSnapY = y.guide
        dragStart = CGPoint(x: x.value, y: y.value)
        selection = .zero
        didDrag = false
        if allowsWindowPicking {
            hoveredWindowIndex = topmostWindowIndex(at: raw)
        }
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
        let dragDistance = max(abs(current.x - start.x), abs(current.y - start.y))
        if !didDrag, dragDistance <= 6 {
            return
        }
        if dragDistance > 6 {
            didDrag = true
            hoveredWindowIndex = nil
        }
        var width = abs(current.x - start.x)
        var height = abs(current.y - start.y)
        if event.modifierFlags.contains(.shift) {
            let side = max(width, height)
            width = side
            height = side
        } else if aspectLocked {
            if width / max(height, 1) > lockedAspect {
                height = width / lockedAspect
            } else {
                width = height * lockedAspect
            }
        }
        let x = current.x >= start.x ? start.x : start.x - width
        let y = current.y >= start.y ? start.y : start.y - height
        selection = CGRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil

        if scrollMode {
            let rect: CGRect?
            if didDrag, selection.width >= 2, selection.height >= 2 {
                rect = selection
            } else if let index = hoveredWindowIndex, windowHits.indices.contains(index) {
                rect = windowHits[index].rect
            } else {
                rect = nil
            }
            if let rect {
                onScrollRegionSelected?(pixelRect(for: rect))
            }
            return
        }

        if allowsWindowPicking, !didDrag {
            selection = .zero
            if skipActionBar {
                if let index = hoveredWindowIndex, windowHits.indices.contains(index) {
                    let rect = pixelRect(for: windowHits[index].rect)
                    if let cropped = image.cropping(to: rect) {
                        onComplete?(cropped, rect)
                    }
                } else {
                    let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                    onComplete?(image, full)
                }
                return
            }
            if showsActionBar {
                if let index = hoveredWindowIndex, windowHits.indices.contains(index) {
                    let viewRect = windowHits[index].rect.intersection(bounds)
                    let rect = pixelRect(for: viewRect)
                    if viewRect.width >= 1, viewRect.height >= 1, let cropped = image.cropping(to: rect) {
                        showEditingToolbar(image: cropped, pixelRect: rect, viewRect: viewRect)
                    }
                } else {
                    let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                    showEditingToolbar(image: image, pixelRect: full, viewRect: bounds)
                }
                return
            }
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
        if showsActionBar {
            showEditingToolbar(image: cropped, pixelRect: pixels, viewRect: selection)
        } else {
            onComplete?(cropped, pixels)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if isEditing {
            if handleEditingShortcut(event) { return }
            super.keyDown(with: event)
            return
        }

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
            guard selection.width > 0, selection.height > 0 else {
                super.keyDown(with: event)
                return
            }
            switch event.keyCode {
            case 123: selection = selection.offsetBy(dx: -step, dy: 0)
            case 124: selection = selection.offsetBy(dx: step, dy: 0)
            case 125: selection = selection.offsetBy(dx: 0, dy: step)
            default: selection = selection.offsetBy(dx: 0, dy: -step)
            }
            needsDisplay = true
        case 15: // R：锁定比例
            if allowsWindowPicking, !scrollMode {
                toggleAspectLock()
            }
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
            if !selectedWindows.isEmpty {
                if let composed = compositeSelectedWindows() {
                    showEditingToolbar(
                        image: composed.image,
                        pixelRect: composed.pixelRect,
                        viewRect: composed.viewRect
                    )
                }
                return
            }
            if selection.width >= 2, selection.height >= 2 {
                let pixels = pixelRect(for: selection)
                if let cropped = image.cropping(to: pixels) {
                    showEditingToolbar(image: cropped, pixelRect: pixels, viewRect: selection)
                }
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func handleEditingShortcut(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76:
            perform(.copy)
            return true
        case 53:
            onCancel?()
            return true
        default:
            break
        }

        if mods.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c":
                perform(.copy)
                return true
            case "s":
                perform(.save)
                return true
            default:
                break
            }
        }
        return false
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


final class ToolbarBarView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

final class CursorButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ColorSwatchButton: NSButton {
    var swatchHex: String = ""
    var swatchColor: NSColor = .systemRed {
        didSet { layer?.backgroundColor = swatchColor.cgColor }
    }
    var isActive: Bool = false {
        didSet {
            layer?.borderWidth = isActive ? 2.5 : 1
            layer?.borderColor = (isActive
                ? NSColor.white
                : NSColor.black.withAlphaComponent(0.5)).cgColor
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ToolbarIconButton: NSButton {
    var baseBackground: NSColor = .clear {
        didSet { layer?.backgroundColor = baseBackground.cgColor }
    }

    private var hovered = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        layer?.backgroundColor = baseBackground.cgColor
    }
}
