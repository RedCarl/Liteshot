import AppKit

/// 全景拼接：分别检测水平/垂直位移，把每帧放到二维画布的累计偏移上，最后按包围盒裁剪。
@MainActor
final class PanoramaStitcher: ScrollStitching {
    let width: Int
    let height: Int
    let maxDimension: Int

    private var placements: [(image: CGImage, origin: CGPoint)] = []
    private var bounds: CGRect = .zero
    private var offset: CGPoint = .zero
    private var previousVerticalGray: [UInt8]?
    private var previousHorizontalGray: [UInt8]?
    private var previousFullGray: [UInt8]?
    private var didWarnMax = false

    var onUpdate: ((Int) -> Void)?
    var onWarning: ((String) -> Void)?

    var baseLength: Int { max(width, height) }
    var stitchedLength: Int { Int(max(bounds.width, bounds.height)) }
    var isFull: Bool { bounds.width >= CGFloat(maxDimension) || bounds.height >= CGFloat(maxDimension) }

    init(width: Int, height: Int, maxDimension: Int = 20_000) {
        self.width = width
        self.height = height
        self.maxDimension = maxDimension
    }

    func add(_ image: CGImage) {
        guard !isFull else { return }
        guard image.width == width, image.height == height else { return }

        guard let previousVerticalGray,
              let previousHorizontalGray,
              let previousFullGray else {
            placements = [(image, .zero)]
            bounds = CGRect(x: 0, y: 0, width: width, height: height)
            self.previousVerticalGray = verticalGrayBuffer(for: image)
            self.previousHorizontalGray = horizontalGrayBuffer(for: image)
            self.previousFullGray = fullGrayBuffer(for: image)
            onUpdate?(stitchedLength)
            return
        }

        guard let currentVerticalGray = verticalGrayBuffer(for: image),
              let currentHorizontalGray = horizontalGrayBuffer(for: image),
              let currentFullGray = fullGrayBuffer(for: image) else {
            return
        }

        let vertical = verticalShift(
            previous: previousVerticalGray,
            current: currentVerticalGray,
            previousFull: previousFullGray,
            currentFull: currentFullGray
        )
        let horizontal = horizontalShift(
            previous: previousHorizontalGray,
            current: currentHorizontalGray,
            previousFull: previousFullGray,
            currentFull: currentFullGray
        )

        var dx = 0
        var dy = 0
        if let vertical, let horizontal {
            if horizontal >= 6 && vertical >= 6 {
                dx = horizontal
                dy = vertical
            } else if vertical >= horizontal {
                dy = vertical
            } else {
                dx = horizontal
            }
        } else if let vertical {
            dy = vertical
        } else if let horizontal {
            dx = horizontal
        } else {
            return
        }

        guard dx > 2 || dy > 2 else { return }
        guard dx < width - 10, dy < height - 10 else {
            onWarning?(L10n.t("滚动过快，可能漏内容", "Scrolled too fast; content may be missing"))
            return
        }

        let newOffset = CGPoint(x: offset.x + CGFloat(dx), y: offset.y + CGFloat(dy))
        let newRect = CGRect(x: newOffset.x, y: newOffset.y, width: CGFloat(width), height: CGFloat(height))
        let newBounds = bounds.union(newRect)

        guard newBounds.width <= CGFloat(maxDimension), newBounds.height <= CGFloat(maxDimension) else {
            if !didWarnMax {
                didWarnMax = true
                onWarning?(L10n.t("已达最大画布尺寸", "Reached the maximum canvas size"))
            }
            return
        }

        offset = newOffset
        bounds = newBounds
        placements.append((image, newOffset))
        self.previousVerticalGray = currentVerticalGray
        self.previousHorizontalGray = currentHorizontalGray
        self.previousFullGray = currentFullGray
        onUpdate?(stitchedLength)
    }

    func makeImage() -> CGImage? {
        let outputWidth = Int(bounds.width.rounded())
        let outputHeight = Int(bounds.height.rounded())
        guard outputWidth > 0, outputHeight > 0,
              outputWidth <= maxDimension, outputHeight <= maxDimension else { return nil }

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
        context.translateBy(x: 0, y: CGFloat(outputHeight))
        context.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for placement in placements {
            let rect = CGRect(
                x: placement.origin.x - bounds.minX,
                y: placement.origin.y - bounds.minY,
                width: CGFloat(width),
                height: CGFloat(height)
            )
            NSImage(cgImage: placement.image, size: NSSize(width: width, height: height)).draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: - Shift detection

    private var verticalGrayWidth: Int { 400 }
    private var verticalGrayHeight: Int { max(1, Int(CGFloat(height) * 400 / CGFloat(width))) }
    private var horizontalGrayHeight: Int { 300 }
    private var horizontalGrayWidth: Int { max(1, Int(CGFloat(width) * 300 / CGFloat(height))) }

    private func verticalShift(
        previous: [UInt8],
        current: [UInt8],
        previousFull: [UInt8],
        currentFull: [UInt8]
    ) -> Int? {
        let grayWidth = verticalGrayWidth
        let grayHeight = verticalGrayHeight
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
                    sum += abs(Int(previous[prevRow + x]) - Int(current[curRow + x]))
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
        let shift = Int((CGFloat(bestShift) * CGFloat(height) / CGFloat(grayHeight)).rounded())
        guard shift > 0, shift < height - 10 else { return nil }

        return refine(full: previousFull, currentFull: currentFull, coarse: shift, axis: .vertical) ?? shift
    }

    private func horizontalShift(
        previous: [UInt8],
        current: [UInt8],
        previousFull: [UInt8],
        currentFull: [UInt8]
    ) -> Int? {
        let grayWidth = horizontalGrayWidth
        let grayHeight = horizontalGrayHeight
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
                let row = y * grayWidth
                for x in 0..<strip {
                    sum += abs(Int(previous[row + shift + x]) - Int(current[row + x]))
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
        let shift = Int((CGFloat(bestShift) * CGFloat(width) / CGFloat(grayWidth)).rounded())
        guard shift > 0, shift < width - 10 else { return nil }
        return refine(full: previousFull, currentFull: currentFull, coarse: shift, axis: .horizontal) ?? shift
    }

    private enum RefineAxis { case vertical, horizontal }

    private func refine(full: [UInt8], currentFull: [UInt8], coarse: Int, axis: RefineAxis) -> Int? {
        let strip = min(32, (axis == .vertical ? height : width) / 4)
        guard strip > 4 else { return coarse }
        let limit = axis == .vertical ? height : width
        let lower = max(1, coarse - 6)
        let upper = min(limit - strip - 1, coarse + 6)
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
                        sum += abs(Int(full[prevRow + x]) - Int(currentFull[curRow + x]))
                    }
                }
                let score = Double(sum) / Double(columns * strip)
                if score < bestScore { bestScore = score; best = shift }
            }
        case .horizontal:
            let y0 = height * 2 / 100
            let y1 = height * 70 / 100
            let rows = y1 - y0
            for shift in lower...upper {
                var sum = 0
                for y in y0..<y1 {
                    let row = y * width
                    for x in 0..<strip {
                        sum += abs(Int(full[row + shift + x]) - Int(currentFull[row + x]))
                    }
                }
                let score = Double(sum) / Double(rows * strip)
                if score < bestScore { bestScore = score; best = shift }
            }
        }
        return best
    }

    private func verticalGrayBuffer(for image: CGImage) -> [UInt8]? {
        grayBuffer(for: image, targetWidth: verticalGrayWidth, targetHeight: verticalGrayHeight)
    }

    private func horizontalGrayBuffer(for image: CGImage) -> [UInt8]? {
        grayBuffer(for: image, targetWidth: horizontalGrayWidth, targetHeight: horizontalGrayHeight)
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
