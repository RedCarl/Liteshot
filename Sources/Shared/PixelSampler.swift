import AppKit
import CoreGraphics

/// 把 CGImage 解码成 RGBA8 缓冲，支持按像素快速取色。
struct PixelSampler {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSImage(cgImage: image, size: NSSize(width: width, height: height))
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        guard let raw = context.data else { return nil }
        let pointer = raw.assumingMemoryBound(to: UInt8.self)
        self.width = width
        self.height = height
        self.data = Array(UnsafeBufferPointer(start: pointer, count: width * height * 4))
    }

    func color(atX x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = (y * width + x) * 4
        let alpha = data[index + 3]
        guard alpha > 0 else { return nil }
        let alphaFraction = CGFloat(alpha) / 255
        return NSColor(
            srgbRed: CGFloat(data[index]) / 255 / alphaFraction,
            green: CGFloat(data[index + 1]) / 255 / alphaFraction,
            blue: CGFloat(data[index + 2]) / 255 / alphaFraction,
            alpha: 1
        )
    }
}
