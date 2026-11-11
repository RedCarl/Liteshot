import AppKit
import CoreImage

struct ExportOptions {
    var scale: CGFloat = 1
    var cornerRadius: CGFloat = 0
    var shadow: Bool = false
    var shadowBlur: CGFloat = 18
    var shadowOpacity: Double = 0.45
    var transparent: Bool = false
}

enum EditorRenderer {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 按图片原始像素尺寸 1:1 渲染，输出可直接写文件/剪贴板。
    static func render(
        image: CGImage,
        annotations: [Annotation],
        options: ExportOptions = ExportOptions()
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let scale = max(0.1, options.scale)
        let padding = options.shadow ? max(24, options.shadowBlur + 8) : 0
        let outputWidth = max(1, Int((CGFloat(width) * scale + padding * 2).rounded()))
        let outputHeight = max(1, Int((CGFloat(height) * scale + padding * 2).rounded()))

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high

        // 翻转成左上原点，再缩放到目标输出像素。
        context.translateBy(x: 0, y: CGFloat(outputHeight))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: padding, y: padding)
        context.scaleBy(x: scale, y: scale)

        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        let clippedPath = NSBezierPath(
            roundedRect: imageRect,
            xRadius: options.cornerRadius,
            yRadius: options.cornerRadius
        )

        if options.shadow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(options.shadowOpacity)
            shadow.shadowBlurRadius = options.shadowBlur
            shadow.shadowOffset = NSSize(width: 0, height: options.shadowBlur / 3)
            shadow.set()
            NSColor.black.setFill()
            clippedPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if !options.transparent {
            NSColor.white.setFill()
            imageRect.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        if options.cornerRadius > 0 {
            clippedPath.addClip()
        }
        NSImage(cgImage: image, size: NSSize(width: width, height: height)).draw(in: imageRect)
        for annotation in annotations {
            draw(annotation, baseImage: image)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// 假定当前绘图上下文已转到图片坐标系（1 单位 = 1 像素，左上原点）。
    static func draw(_ annotation: Annotation, baseImage: CGImage? = nil) {
        let color = annotation.style.color
        let lineWidth = max(1, annotation.style.lineWidth)

        switch annotation.tool {
        case .rectangle:
            color.setStroke()
            let path = NSBezierPath(rect: boundsRect(annotation))
            path.lineWidth = lineWidth
            path.stroke()

        case .ellipse:
            color.setStroke()
            let path = NSBezierPath(ovalIn: boundsRect(annotation))
            path.lineWidth = lineWidth
            path.stroke()

        case .line:
            strokeLine(from: annotation.start, to: annotation.end, color: color, width: lineWidth)

        case .arrow:
            strokeLine(from: annotation.start, to: annotation.end, color: color, width: lineWidth)
            fillArrowHead(from: annotation.start, to: annotation.end, color: color, lineWidth: lineWidth)

        case .pencil:
            strokeFreehand(annotation.points, color: color.withAlphaComponent(1), width: lineWidth)

        case .highlight:
            strokeFreehand(annotation.points, color: color.withAlphaComponent(0.35), width: max(lineWidth, 8))

        case .regionHighlight:
            color.withAlphaComponent(0.28).setFill()
            NSBezierPath(rect: boundsRect(annotation)).fill()

        case .mosaic:
            drawMosaic(annotation, baseImage: baseImage)

        case .counter:
            drawCounter(annotation)

        case .image:
            drawImage(annotation)

        case .text:
            drawText(annotation)

        case .watermark:
            drawWatermark(annotation)

        case .select:
            break
        }
    }

    // MARK: - M3 tools

    private static func drawMosaic(_ annotation: Annotation, baseImage: CGImage?) {
        guard let baseImage,
              let first = annotation.points.first,
              let context = NSGraphicsContext.current?.cgContext else { return }

        let strokeWidth = max(16, annotation.style.lineWidth)
        let path = CGMutablePath()
        path.move(to: first)
        for point in annotation.points.dropFirst() {
            path.addLine(to: point)
        }

        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let affected = path.boundingBoxOfPath
            .insetBy(dx: -strokeWidth, dy: -strokeWidth)
            .intersection(imageBounds)
        guard affected.width >= 1, affected.height >= 1 else { return }
        guard let filtered = filteredMosaic(
            baseImage,
            rect: affected,
            algorithm: annotation.mosaicAlgorithm ?? "crystal"
        ) else { return }

        context.saveGState()
        context.addPath(path)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        NSImage(cgImage: filtered, size: affected.size).draw(in: affected)
        context.restoreGState()
    }

    private static func filteredMosaic(_ image: CGImage, rect: CGRect, algorithm: String) -> CGImage? {
        let source = CIImage(cgImage: image)
        let height = CGFloat(image.height)
        let ciRect = CGRect(
            x: rect.minX,
            y: height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let cropped = source.cropped(to: ciRect)

        let filterName: String
        let key: String
        let value: Double
        switch algorithm {
        case "gaussian":
            filterName = "CIGaussianBlur"
            key = kCIInputRadiusKey
            value = 14
        case "hex":
            filterName = "CIHexagonalPixellate"
            key = kCIInputScaleKey
            value = 14
        default:
            filterName = "CIPixellate"
            key = kCIInputScaleKey
            value = 12
        }

        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(cropped, forKey: kCIInputImageKey)
        filter.setValue(value, forKey: key)
        guard let output = filter.outputImage?.cropped(to: ciRect) else { return nil }
        return ciContext.createCGImage(output, from: ciRect)
    }

    private static func drawCounter(_ annotation: Annotation) {
        let radius = annotation.counterRadius
        let rect = CGRect(
            x: annotation.start.x - radius,
            y: annotation.start.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        annotation.style.color.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let number = "\(annotation.number ?? 1)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius * 1.05, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = (number as NSString).size(withAttributes: attributes)
        (number as NSString).draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private static func drawImage(_ annotation: Annotation) {
        guard let data = annotation.imageData, let image = NSImage(data: data) else { return }
        let rect = boundsRect(annotation)
        guard rect.width > 1, rect.height > 1, image.size.width > 0, image.size.height > 0 else { return }

        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: drawRect)
    }

    private static func drawText(_ annotation: Annotation) {
        guard let text = annotation.text, !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .medium)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.style.color,
        ]
        if annotation.style.lineWidth > 0 {
            attributes[.strokeWidth] = -annotation.style.lineWidth
            attributes[.strokeColor] = NSColor.black
        }

        let lines = text.components(separatedBy: "\n")
        let lineHeight = font.ascender - font.descender + font.leading
        let totalWidth = annotation.textSize.width

        for (index, line) in lines.enumerated() {
            let size = (line as NSString).size(withAttributes: attributes)
            var x = annotation.start.x
            switch annotation.textAlignment ?? "left" {
            case "center":
                x += (totalWidth - size.width) / 2
            case "right":
                x += totalWidth - size.width
            default:
                break
            }
            (line as NSString).draw(
                at: CGPoint(x: x, y: annotation.start.y + CGFloat(index) * lineHeight),
                withAttributes: attributes
            )
        }
    }

    private static func drawWatermark(_ annotation: Annotation) {
        guard let text = annotation.text, !text.isEmpty,
              let context = NSGraphicsContext.current?.cgContext else { return }

        let width = max(annotation.end.x, 1)
        let height = max(annotation.end.y, 1)
        let font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.style.color.withAlphaComponent(0.18),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let stepX = max(80, textSize.width + annotation.style.fontSize * 4)
        let stepY = max(60, textSize.height + annotation.style.fontSize * 5)

        context.saveGState()
        context.translateBy(x: width / 2, y: height / 2)
        context.rotate(by: -30 * .pi / 180)
        context.translateBy(x: -width / 2, y: -height / 2)

        var y = -height
        while y < height * 2 {
            var x = -width
            while x < width * 2 {
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
                x += stepX
            }
            y += stepY
        }
        context.restoreGState()
    }

    // MARK: - Primitives

    private static func boundsRect(_ annotation: Annotation) -> CGRect {
        CGRect(
            x: min(annotation.start.x, annotation.end.x),
            y: min(annotation.start.y, annotation.end.y),
            width: abs(annotation.end.x - annotation.start.x),
            height: abs(annotation.end.y - annotation.start.y)
        ).insetBy(dx: 0.5, dy: 0.5)
    }

    private static func strokeLine(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func strokeFreehand(_ points: [CGPoint], color: NSColor, width: CGFloat) {
        guard let first = points.first else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: first)
        if points.count == 1 {
            path.line(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
        } else {
            for point in points.dropFirst() {
                path.line(to: point)
            }
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func fillArrowHead(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, lineWidth * 4)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )

        color.setFill()
        let path = NSBezierPath()
        path.move(to: end)
        path.line(to: left)
        path.line(to: right)
        path.close()
        path.fill()
    }
}
