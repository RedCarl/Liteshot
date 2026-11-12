import AppKit

@MainActor
final class EditorCanvasView: NSView {
    let image: CGImage
    let document: EditorDocument

    var tool: AnnotationTool = .select {
        didSet {
            if tool != oldValue { window?.invalidateCursorRects(for: self) }
        }
    }

    var currentStyle: ToolStyle = ToolStyleStore.default(for: .rectangle)
    var mosaicAlgorithm: String = "crystal"
    var textAlignment: String = "left"
    var textAsWatermark: Bool = false
    var selectedID: UUID?
    var onChange: (() -> Void)?

    /// 截图覆盖层内联模式：画布精确贴合选区，不画背景/留白/阴影。
    var inlineMode = false {
        didSet {
            guard inlineMode != oldValue else { return }
            needsLayout = true
            needsDisplay = true
        }
    }
    /// 内联模式下按回车 / 双击：完成并复制。
    var onFinishRequest: (() -> Void)?
    /// 内联模式下按 Esc：退出截图。
    var onCancelRequest: (() -> Void)?
    /// 内联模式下按 ⌘S：保存并退出。
    var onSaveRequest: (() -> Void)?

    private enum Interaction {
        case none
        case creating
        case moving(Annotation)
        case resizing(Annotation, Int)
    }

    private var interaction: Interaction = .none
    private var draft: Annotation?
    private var transient: Annotation?
    private var dragOrigin: CGPoint = .zero
    private var imageRect: CGRect = .zero
    private var displayScale: CGFloat = 1
    private var textField: NSTextField?
    private var textInputPoint: CGPoint = .zero

    init(image: CGImage, document: EditorDocument) {
        self.image = image
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        updateImageRect()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = tool == .select ? .arrow : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard imageRect.width > 0 else { return }

        if inlineMode {
            drawInline()
            return
        }

        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: 2)
        shadow.set()
        NSImage(cgImage: image, size: imageRect.size).draw(in: imageRect)
        NSGraphicsContext.restoreGraphicsState()

        for annotation in document.annotations where annotation.id != transient?.id {
            drawAnnotation(annotation)
        }
        if let transient {
            drawAnnotation(transient)
        }
        if let draft {
            drawAnnotation(draft)
        }

        if let selected = selectedAnnotation {
            drawSelection(for: selected)
        }
    }

    private func drawInline() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()

        // inline 模式不画截图本身：覆盖层保持透明，让桌面原本的画面透出来。
        for annotation in document.annotations where annotation.id != transient?.id {
            drawAnnotation(annotation)
        }
        if let transient {
            drawAnnotation(transient)
        }
        if let draft {
            drawAnnotation(draft)
        }
        if let selected = selectedAnnotation {
            drawSelection(for: selected)
        }

        NSGraphicsContext.restoreGraphicsState()

        (NSColor(hex: "#2F7CF6") ?? .controlAccentColor).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()
    }

    private func drawAnnotation(_ annotation: Annotation) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: displayScale, y: displayScale)
        EditorRenderer.draw(annotation, baseImage: image)
        context.restoreGState()
    }

    private func drawSelection(for annotation: Annotation) {
        let rect = viewRect(for: annotation)
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        border.lineWidth = 1.5
        border.stroke()

        for point in handlePoints(for: annotation) {
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            handleRect.fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: handleRect)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if tool != .text, textField != nil {
            finishTextInput(commit: true)
        }
        if inlineMode, event.clickCount == 2, tool != .text {
            onFinishRequest?()
            return
        }
        window?.makeFirstResponder(self)
        updateImageRect()
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = imagePoint(viewPoint)
        dragOrigin = point

        if tool == .select {
            guard let selected = selectedAnnotation else {
                if let hit = annotationHit(at: point) {
                    selectedID = hit.id
                    interaction = .moving(hit)
                } else {
                    selectedID = nil
                }
                needsDisplay = true
                onChange?()
                return
            }

            if let handle = handleIndex(at: viewPoint, for: selected) {
                interaction = .resizing(selected, handle)
                return
            }

            if let hit = annotationHit(at: point) {
                selectedID = hit.id
                interaction = .moving(hit)
            } else {
                selectedID = nil
                interaction = .none
            }
            needsDisplay = true
            onChange?()
            return
        }

        if tool == .text {
            beginTextInput(at: point)
            return
        }

        if tool == .counter {
            let next = (document.annotations.compactMap { $0.tool == .counter ? $0.number : nil }.max() ?? 0) + 1
            var annotation = Annotation(tool: .counter, start: point, end: point, style: currentStyle)
            annotation.number = next
            document.add(annotation)
            selectedID = annotation.id
            needsDisplay = true
            onChange?()
            return
        }

        selectedID = nil
        interaction = .creating
        var created = Annotation(
            tool: tool,
            start: point,
            end: point,
            points: tool == .pencil || tool == .highlight || tool == .mosaic ? [point] : [],
            style: currentStyle
        )
        if tool == .mosaic {
            created.mosaicAlgorithm = mosaicAlgorithm
        }
        draft = created
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(convert(event.locationInWindow, from: nil))

        switch interaction {
        case .creating:
            guard var draft else { return }
            if draft.isFreehand {
                if let last = draft.points.last, hypot(point.x - last.x, point.y - last.y) < 1 {
                    return
                }
                draft.points.append(point)
                draft.end = point
            } else {
                draft.end = point
            }
            self.draft = draft

        case .moving(let original):
            var moved = original
            moved.translate(dx: point.x - dragOrigin.x, dy: point.y - dragOrigin.y)
            transient = moved

        case .resizing(let original, let handle):
            transient = resized(original, handle: handle, to: point)

        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch interaction {
        case .creating:
            if let draft, isValid(draft) {
                document.add(draft)
                selectedID = draft.id
            }
            draft = nil

        case .moving(let original), .resizing(let original, _):
            if let transient, transient != original {
                document.replace(transient)
                selectedID = transient.id
            }

        case .none:
            break
        }

        interaction = .none
        transient = nil
        needsDisplay = true
        onChange?()
    }

    // MARK: - Inline text

    private func beginTextInput(at imagePoint: CGPoint) {
        finishTextInput(commit: true)

        textInputPoint = imagePoint
        let origin = viewPoint(imagePoint)
        let fontSize = max(12, currentStyle.fontSize * displayScale)
        let field = NSTextField(frame: NSRect(x: origin.x, y: origin.y, width: 240, height: fontSize + 12))
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        field.textColor = currentStyle.color
        field.font = .systemFont(ofSize: fontSize, weight: .medium)
        field.focusRingType = .none
        field.placeholderString = L10n.t("输入文字，⇧↩ 换行，↩ 确认", "Type text, ⇧↩ for newline, ↩ to confirm")
        field.delegate = self
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    private func finishTextInput(commit: Bool) {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        textField = nil

        guard commit, !text.isEmpty else { return }

        if textAsWatermark {
            var annotation = Annotation(
                tool: .watermark,
                start: .zero,
                end: CGPoint(x: image.width, y: image.height),
                style: currentStyle
            )
            annotation.text = text
            annotation.textAlignment = "center"
            document.add(annotation)
            selectedID = annotation.id
            needsDisplay = true
            onChange?()
            return
        }

        var annotation = Annotation(tool: .text, start: textInputPoint, end: textInputPoint, style: currentStyle)
        annotation.text = text
        annotation.textAlignment = textAlignment
        document.add(annotation)
        selectedID = annotation.id
        needsDisplay = true
        onChange?()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if inlineMode {
            if handleInlineShortcut(event) { return }
        }

        switch event.keyCode {
        case 53: // Esc
            if draft != nil || transient != nil {
                draft = nil
                transient = nil
                interaction = .none
            } else {
                selectedID = nil
            }
            needsDisplay = true

        case 51, 117: // Delete / Forward Delete
            if let selectedID {
                document.remove(id: selectedID)
                self.selectedID = nil
                needsDisplay = true
                onChange?()
            }

        case 123, 124, 125, 126: // Arrows
            guard let selectedID, let annotation = document.annotations.first(where: { $0.id == selectedID }) else {
                super.keyDown(with: event)
                return
            }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var moved = annotation
            switch event.keyCode {
            case 123: moved.translate(dx: -step, dy: 0)
            case 124: moved.translate(dx: step, dy: 0)
            case 125: moved.translate(dx: 0, dy: step)
            default: moved.translate(dx: 0, dy: -step)
            }
            document.replace(moved)
            needsDisplay = true

        default:
            super.keyDown(with: event)
        }
    }

    private func handleInlineShortcut(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc：直接退出截图
            onCancelRequest?()
            return true

        case 36, 76: // Return / Enter
            onFinishRequest?()
            return true

        default:
            break
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isUndoModifier = mods.contains(.command) || mods.contains(.control)
        if isUndoModifier, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "z":
                if mods.contains(.shift) {
                    document.redo()
                } else {
                    document.undo()
                }
                selectedID = nil
                needsDisplay = true
                onChange?()
                return true
            case "c":
                onFinishRequest?()
                return true
            case "s":
                onSaveRequest?()
                return true
            default:
                break
            }
        }
        return false
    }

    // MARK: - Public

    func select(id: UUID?) {
        selectedID = id
        needsDisplay = true
        onChange?()
    }

    func refresh() {
        updateImageRect()
        needsDisplay = true
    }

    func commitPendingText() {
        finishTextInput(commit: true)
    }

    // MARK: - Geometry

    private func updateImageRect() {
        if inlineMode {
            guard bounds.width > 1, bounds.height > 1, image.width > 0, image.height > 0 else { return }
            displayScale = bounds.width / CGFloat(image.width)
            imageRect = bounds
            return
        }

        let padding: CGFloat = 24
        let available = bounds.insetBy(dx: padding, dy: padding)
        guard available.width > 1, available.height > 1, image.width > 0, image.height > 0 else { return }

        let fit = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
        displayScale = min(1, max(fit, 0.02))
        let size = CGSize(width: CGFloat(image.width) * displayScale, height: CGFloat(image.height) * displayScale)
        imageRect = CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
        guard displayScale > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - imageRect.minX) / displayScale,
            y: (viewPoint.y - imageRect.minY) / displayScale
        )
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imagePoint.x * displayScale,
            y: imageRect.minY + imagePoint.y * displayScale
        )
    }

    private func viewRect(for annotation: Annotation) -> CGRect {
        let rect = annotation.bounds
        return CGRect(
            x: imageRect.minX + rect.minX * displayScale,
            y: imageRect.minY + rect.minY * displayScale,
            width: rect.width * displayScale,
            height: rect.height * displayScale
        )
    }

    private var selectedAnnotation: Annotation? {
        guard let selectedID else { return nil }
        if let transient, transient.id == selectedID { return transient }
        return document.annotations.first { $0.id == selectedID }
    }

    private func handlePoints(for annotation: Annotation) -> [CGPoint] {
        if annotation.tool == .line || annotation.tool == .arrow {
            return [viewPoint(annotation.start), viewPoint(annotation.end)]
        }
        if annotation.isFreehand || annotation.tool == .text {
            return []
        }
        let rect = viewRect(for: annotation)
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
    }

    private func handleIndex(at point: CGPoint, for annotation: Annotation) -> Int? {
        for (index, handle) in handlePoints(for: annotation).enumerated() {
            if hypot(point.x - handle.x, point.y - handle.y) <= 7 {
                return index
            }
        }
        return nil
    }

    private func annotationHit(at point: CGPoint) -> Annotation? {
        document.annotations.reversed().first { $0.bounds.contains(point) }
    }

    private func resized(_ original: Annotation, handle: Int, to point: CGPoint) -> Annotation {
        var result = original

        if original.tool == .line || original.tool == .arrow {
            if handle == 0 { result.start = point } else { result.end = point }
            return result
        }

        var minX = min(original.start.x, original.end.x)
        var maxX = max(original.start.x, original.end.x)
        var minY = min(original.start.y, original.end.y)
        var maxY = max(original.start.y, original.end.y)

        switch handle {
        case 0: minX = point.x; minY = point.y
        case 1: minY = point.y
        case 2: maxX = point.x; minY = point.y
        case 3: maxX = point.x
        case 4: maxX = point.x; maxY = point.y
        case 5: maxY = point.y
        case 6: minX = point.x; maxY = point.y
        case 7: minX = point.x
        default: break
        }

        result.start = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
        result.end = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
        return result
    }

    private func isValid(_ annotation: Annotation) -> Bool {
        switch annotation.tool {
        case .pencil, .highlight, .mosaic:
            return annotation.points.count >= 2
        case .line, .arrow:
            return hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y) >= 2
        case .text:
            return !(annotation.text ?? "").isEmpty
        default:
            return abs(annotation.end.x - annotation.start.x) >= 2
                && abs(annotation.end.y - annotation.start.y) >= 2
        }
    }
}

extension EditorCanvasView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        // 点工具条或点画布别处时，把正在输入的文字落成标注。
        if textField != nil {
            finishTextInput(commit: true)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                textView.insertNewline(nil)
                return true
            }
            finishTextInput(commit: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextInput(commit: false)
            return true
        }
        return false
    }
}
