import AppKit
import ImageIO
import UniformTypeIdentifiers

enum SaveError: LocalizedError {
    case encodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return L10n.t("图片编码失败。", "Image encoding failed.")
        case .writeFailed(let message):
            return L10n.t("保存失败：", "Save failed: ") + message
        }
    }
}

enum SaveService {
    static func save(
        image: CGImage,
        to directory: URL,
        format: ImageFormat,
        quality: Double,
        template: String,
        date: Date = Date()
    ) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw SaveError.writeFailed(error.localizedDescription)
        }

        let url = uniqueURL(
            in: directory,
            template: template,
            format: format,
            date: date
        )

        guard let data = encode(image, format: format, quality: quality) else {
            throw SaveError.encodingFailed
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SaveError.writeFailed(error.localizedDescription)
        }
        return url
    }

    static func encode(_ image: CGImage, format: ImageFormat, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.uti as CFString,
            1,
            nil
        ) else {
            return nil
        }

        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality))
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func uniqueURL(in directory: URL, template: String, format: ImageFormat, date: Date) -> URL {
        var name = FilenameTemplate.render(template, date: date)
        name = sanitize(name)
        if name.isEmpty {
            name = FilenameTemplate.render("Liteshot-{yyyy}{MM}{dd}-{HH}{mm}{ss}", date: date)
        }
        if !name.lowercased().hasSuffix("." + format.fileExtension) {
            name += "." + format.fileExtension
        }

        let stem = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(stem)-\(index).\(format.fileExtension)"
            candidate = directory.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClipboardService {
    static func copy(image: CGImage) {
        let pasteboard = NSPasteboard.general
        let item = NSPasteboardItem()

        if let png = ImageEncoding.pngData(from: image) {
            item.setData(png, forType: .png)
        }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if let tiff = nsImage.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
