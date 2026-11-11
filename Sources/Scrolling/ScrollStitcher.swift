import AppKit

enum ScrollAxis {
    case vertical
    case horizontal
}

@MainActor
protocol ScrollStitching: AnyObject {
    var stitchedLength: Int { get }
    var baseLength: Int { get }
    var isFull: Bool { get }
    var onUpdate: ((Int) -> Void)? { get set }
    var onWarning: ((String) -> Void)? { get set }
    func add(_ image: CGImage)
    func makeImage() -> CGImage?
}

/// 滚动截图拼接器：支持竖向（追加底部行）与横向（追加右侧列）。
@MainActor
final class ScrollStitcher: ScrollStitching {
    let axis: ScrollAxis
    let width: Int
    let height: Int
    let maxLength: Int

    private let context: CGContext
    private var previousGray: [UInt8]?
    private var previousFullGray: [UInt8]?
    private let grayWidth: Int
    private let grayHeight: Int
    private(set) var stitchedLength = 0
    private var didWarnMax = false

    var onUpdate: ((Int) -> Void)?
    var onWarning: ((String) -> Void)?

    var baseLength: Int {
        axis == .vertical ? height : width
    }

    init(width: Int, height: Int, axis: ScrollAxis = .vertical, maxLength: Int? = nil) {
        self.axis = axis
        self.width = width
        self.height = height
        self.maxLength = maxLength ?? (axis == .vertical ? 12_000 : 20_000)

        switch axis {
        case .vertical:
            grayWidth = 400
            grayHeight = max(1, Int(CGFloat(height) * 400 / CGFloat(width)))
        case .horizontal:
            grayHeight = 300
            grayWidth = max(1, Int(CGFloat(width) * 300 / CGFloat(height)))
        }

        let canvasWidth = axis == .vertical ? width : self.maxLength
        let canvasHeight = axis == .vertical ? self.maxLength : height

        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("无法创建滚动截图画布")
        }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)
        self.context = context
    }

    var isFull: Bool { stitchedLength >= maxLength - 1 }

    func add(_ image: CGImage) {
        guard !isFull else { return }
        guard image.width == width, image.height == height else { return }

        guard let previousGray, let previousFullGray else {
            draw(image, at: 0)
            stitchedLength = baseLength
            self.previousGray = grayBuffer(for: image)
            self.previousFullGray = fullGrayBuffer(for: image)
            onUpdate?(stitchedLength)
            return
        }

        guard let currentGray = grayBuffer(for: image),
              let currentFullGray = fullGrayBuffer(for: image) else {
            return
        }

        let coarse: Int?
        switch axis {
        case .vertical:
            coarse = verticalShift(previousGray: previousGray, currentGray: currentGray)
        case .horizontal:
            coarse = horizontalShift(previousGray: previousGray, currentGray: currentGray)
        }

        guard let coarse else { return }
        let shift = refineShift(
            previousFull: previousFullGray,
            currentFull: currentFullGray,
            coarse: coarse,
            coarseToFullScale: CGFloat(baseLength) / CGFloat(axis == .vertical ? grayHeight : grayWidth)
        )

        guard shift > 2 else { return }
        guard shift < baseLength - 10 else {
            onWarning?(L10n.t("滚动过快，可能漏内容", "Scrolled too fast; content may be missing"))
            return
        }
        if shift > baseLength * 2 / 3 {
            onWarning?(L10n.t("滚动幅度较大，请留意接缝", "Large scroll step; check the seam"))
        }
        guard stitchedLength + shift <= maxLength else {
            if !didWarnMax {
                didWarnMax = true
                onWarning?(L10n.t("已达最大长度", "Reached the maximum length of") + " \(maxLength) px")
            }
            return
        }

        switch axis {
        case .vertical:
            let crop = CGRect(x: 0, y: image.height - shift, width: image.width, height: shift)
            guard let slice = image.cropping(to: crop) else { return }
            draw(slice, at: stitchedLength)
        case .horizontal:
            let crop = CGRect(x: image.width - shift, y: 0, width: shift, height: image.height)
            guard let slice = image.cropping(to: crop) else { return }
            draw(slice, at: stitchedLength)
        }

        stitchedLength += shift
        self.previousGray = currentGray
        self.previousFullGray = currentFullGray
        onUpdate?(stitchedLength)
    }

    func makeImage() -> CGImage? {
        guard stitchedLength > 0, let full = context.makeImage() else { return nil }
        switch axis {
        case .vertical:
            return full.cropping(to: CGRect(x: 0, y: 0, width: width, height: stitchedLength))
        case .horizontal:
            return full.cropping(to: CGRect(x: 0, y: 0, width: stitchedLength, height: height))
        }
    }

    // MARK: - Drawing

    private func draw(_ image: CGImage, at offset: Int) {
        let rect: CGRect
        switch axis {
        case .vertical:
            rect = CGRect(x: 0, y: offset, width: image.width, height: image.height)
        case .horizontal:
            rect = CGRect(x: offset, y: 0, width: image.width, height: image.height)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Shift estimation

    private func verticalShift(previousGray: [UInt8], currentGray: [UInt8]) -> Int? {
        let strip = min(56, grayHeight / 3)
        guard strip > 4, grayHeight > strip + 4 else { return nil }

        let x0 = grayWidth * 2 / 100
        let x1 = grayWidth * 70 / 100
        let columns = x1 - x0
        var bestShift = 0
        var bestScore = Double.greatestFiniteMagnitude
        var secondBest = Double.greatestFiniteMagnitude

        for shift in 0...(grayHeight - strip) {
            var sum = 0
            for y in 0..<strip {
                let prevRow = (shift + y) * grayWidth
                let curRow = y * grayWidth
                for x in x0..<x1 {
                    sum += abs(Int(previousGray[prevRow + x]) - Int(currentGray[curRow + x]))
                }
            }
            let score = Double(sum) / Double(columns * strip)
            if score < bestScore {
                secondBest = bestScore
                bestScore = score
                bestShift = shift
            } else if score < secondBest {
                secondBest = score
            }
        }

        guard bestShift > 0, bestScore <= 16, secondBest - bestScore >= 1.0 else { return nil }
        let scale = CGFloat(height) / CGFloat(grayHeight)
        let shift = Int((CGFloat(bestShift) * scale).rounded())
        guard shift > 0, shift < height - 10 else { return nil }
        return shift
    }

    private func horizontalShift(previousGray: [UInt8], currentGray: [UInt8]) -> Int? {
        let strip = min(56, grayWidth / 3)
        guard strip > 4, grayWidth > strip + 4 else { return nil }

        let y0 = grayHeight * 2 / 100
        let y1 = grayHeight * 70 / 100
        let rows = y1 - y0
        var bestShift = 0
        var bestScore = Double.greatestFiniteMagnitude
        var secondBest = Double.greatestFiniteMagnitude

        for shift in 0...(grayWidth - strip) {
            var sum = 0
            for y in y0..<y1 {
                let prevRow = y * grayWidth
                let curRow = y * grayWidth
                for x in 0..<strip {
                    sum += abs(Int(previousGray[prevRow + shift + x]) - Int(currentGray[curRow + x]))
                }
            }
            let score = Double(sum) / Double(rows * strip)
            if score < bestScore {
                secondBest = bestScore
                bestScore = score
                bestShift = shift
            } else if score < secondBest {
                secondBest = score
            }
        }

        guard bestShift > 0, bestScore <= 16, secondBest - bestScore >= 1.0 else { return nil }
        let scale = CGFloat(width) / CGFloat(grayWidth)
        let shift = Int((CGFloat(bestShift) * scale).rounded())
        guard shift > 0, shift < width - 10 else { return nil }
        return shift
    }

    private func refineShift(
        previousFull: [UInt8],
        currentFull: [UInt8],
        coarse: Int,
        coarseToFullScale: CGFloat
    ) -> Int {
        let strip = min(32, baseLength / 4)
        guard strip > 4 else { return coarse }

        let lower = max(1, coarse - 6)
        let upper = min(baseLength - strip - 1, coarse + 6)
        guard lower <= upper else { return coarse }

        var best = coarse
        var bestScore = Double.greatestFiniteMagnitude

        switch axis {
        case .vertical:
            let x0 = width * 2 / 100
            let x1 = width * 70 / 100
            let columns = x1 - x0
            for shift in lower...upper {
                var sum = 0
                for y in 0..<strip {
                    let prevRow = (shift + y) * width
                    let curRow = y * width
                    for x in x0..<x1 {
                        sum += abs(Int(previousFull[prevRow + x]) - Int(currentFull[curRow + x]))
                    }
                }
                let score = Double(sum) / Double(columns * strip)
                if score < bestScore {
                    bestScore = score
                    best = shift
                }
            }
        case .horizontal:
            let y0 = height * 2 / 100
            let y1 = height * 70 / 100
            let rows = y1 - y0
            for shift in lower...upper {
                var sum = 0
                for y in y0..<y1 {
                    let prevRow = y * width
                    let curRow = y * width
                    for x in 0..<strip {
                        sum += abs(Int(previousFull[prevRow + shift + x]) - Int(currentFull[curRow + x]))
                    }
                }
                let score = Double(sum) / Double(rows * strip)
                if score < bestScore {
                    bestScore = score
                    best = shift
                }
            }
        }

        _ = coarseToFullScale
        return best
    }

    private func grayBuffer(for image: CGImage) -> [UInt8]? {
        grayBuffer(for: image, targetWidth: grayWidth, targetHeight: grayHeight)
    }

    private func fullGrayBuffer(for image: CGImage) -> [UInt8]? {
        grayBuffer(for: image, targetWidth: image.width, targetHeight: image.height)
    }

    private func grayBuffer(for image: CGImage, targetWidth: Int, targetHeight: Int) -> [UInt8]? {
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .low
        context.translateBy(x: 0, y: CGFloat(targetHeight))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSImage(cgImage: image, size: NSSize(width: targetWidth, height: targetHeight))
            .draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = context.data else { return nil }
        let pointer = data.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: targetWidth * targetHeight))
    }
}
