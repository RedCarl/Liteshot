import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case ellipse
    case arrow
    case line
    case pencil
    case highlight
    case regionHighlight
    case mosaic
    case counter
    case text
    case watermark
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return L10n.t("选择", "Select")
        case .rectangle: return L10n.t("矩形", "Rectangle")
        case .ellipse: return L10n.t("椭圆", "Ellipse")
        case .arrow: return L10n.t("箭头", "Arrow")
        case .line: return L10n.t("直线", "Line")
        case .pencil: return L10n.t("画笔", "Pencil")
        case .highlight: return L10n.t("高亮", "Highlighter")
        case .regionHighlight: return L10n.t("区域高亮", "Highlight Area")
        case .mosaic: return L10n.t("马赛克", "Mosaic")
        case .counter: return L10n.t("序号", "Counter")
        case .text: return L10n.t("文字", "Text")
        case .watermark: return L10n.t("水印", "Watermark")
        case .image: return L10n.t("图片", "Image")
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .highlight: return "highlighter"
        case .regionHighlight: return "rectangle.dashed"
        case .mosaic: return "checkerboard.rectangle"
        case .counter: return "1.circle"
        case .text: return "character"
        case .watermark: return "signature"
        case .image: return "photo"
        }
    }

    var isDrawingTool: Bool { self != .select && self != .image }
}

struct ToolStyle: Codable, Equatable {
    var colorHex: String
    var lineWidth: Double
    var fontSize: Double

    var color: NSColor {
        NSColor(hex: colorHex) ?? .systemRed
    }
}

struct Annotation: Identifiable, Equatable {
    var id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var text: String?
    var style: ToolStyle
    var number: Int?
    var imageData: Data?
    var mosaicAlgorithm: String?
    var textAlignment: String?

    var isFreehand: Bool { tool == .pencil || tool == .highlight || tool == .mosaic }

    /// 图片像素坐标（左上原点），已按线宽外扩，供命中测试用。
    var bounds: CGRect {
        switch tool {
        case .pencil, .highlight, .mosaic:
            guard let first = points.first else { return .zero }
            var rect = CGRect(origin: first, size: .zero)
            for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
            let padding = max(4, style.lineWidth)
            return rect.insetBy(dx: -padding, dy: -padding)
        case .text, .watermark:
            let size = textSize
            return CGRect(origin: start, size: size).insetBy(dx: -4, dy: -4)
        case .counter:
            let radius = counterRadius
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        case .image:
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        default:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            return rect.insetBy(dx: -max(4, style.lineWidth), dy: -max(4, style.lineWidth))
        }
    }

    var counterRadius: CGFloat {
        max(14, style.fontSize * 0.85)
    }

    var textSize: CGSize {
        guard let text, !text.isEmpty else { return .zero }
        let font = NSFont.systemFont(ofSize: style.fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text.components(separatedBy: "\n")
        let widths = lines.map { ($0 as NSString).size(withAttributes: attributes).width }
        let lineHeight = font.ascender - font.descender + font.leading
        return CGSize(
            width: ceil(widths.max() ?? 0),
            height: ceil(lineHeight * CGFloat(lines.count))
        )
    }

    /// 把元素平移 (dx, dy) 个图片像素。
    mutating func translate(dx: CGFloat, dy: CGFloat) {
        start.x += dx
        start.y += dy
        end.x += dx
        end.y += dy
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }
}

enum ToolStyleStore {
    private static let keyPrefix = "editor.style."

    static func `default`(for tool: AnnotationTool) -> ToolStyle {
        switch tool {
        case .highlight:
            return ToolStyle(colorHex: "#FFD60A", lineWidth: 14, fontSize: 24)
        case .regionHighlight:
            return ToolStyle(colorHex: "#FFD60A", lineWidth: 2, fontSize: 24)
        case .mosaic:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 24, fontSize: 24)
        case .counter:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 3, fontSize: 28)
        case .image:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 3, fontSize: 24)
        case .pencil:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 4, fontSize: 24)
        case .text:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 0, fontSize: 28)
        case .select:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 3, fontSize: 28)
        default:
            return ToolStyle(colorHex: "#FF3B30", lineWidth: 4, fontSize: 24)
        }
    }

    static func style(for tool: AnnotationTool) -> ToolStyle {
        guard let data = UserDefaults.standard.data(forKey: keyPrefix + tool.rawValue),
              let style = try? JSONDecoder().decode(ToolStyle.self, from: data) else {
            return `default`(for: tool)
        }
        return style
    }

    static func save(_ style: ToolStyle, for tool: AnnotationTool) {
        guard let data = try? JSONEncoder().encode(style) else { return }
        UserDefaults.standard.set(data, forKey: keyPrefix + tool.rawValue)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF3B30" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
