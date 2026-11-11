import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CoreImage

enum SelfTest {
    static func run() async -> Int32 {
        guard ScreenPermission.isGranted else {
            print("SELFTEST: 未授权屏幕录制（已触发系统请求，授权后重跑）")
            _ = ScreenPermission.request()
            return 2
        }

        guard let screen = screenUnderMouse() else {
            print("SELFTEST: 没有可用屏幕")
            return 3
        }

        let displayID = screen.displayID
        let pixelSize = screen.pixelSize
        let scale = screen.backingScaleFactor

        do {
            let image = try await ScreenCaptureService.capture(
                displayID: displayID,
                pixelWidth: Int(pixelSize.width),
                pixelHeight: Int(pixelSize.height)
            )
            print("SELFTEST: 采集成功 \(image.width)x\(image.height) @\(scale)x")

            guard let png = ImageEncoding.pngData(from: image) else {
                print("SELFTEST: PNG 编码失败")
                return 4
            }

            let url = URL(fileURLWithPath: "/tmp/liteshot-selftest.png")
            try png.write(to: url)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)

            print("SELFTEST: 已写入 \(url.path)（\(png.count) bytes），并写入剪贴板")
            return 0
        } catch {
            print("SELFTEST: 失败 - \(error.localizedDescription)")
            return 1
        }
    }

    static func runSave() async -> Int32 {
        guard ScreenPermission.isGranted else {
            print("SELFTEST-SAVE: 未授权屏幕录制")
            return 2
        }
        guard let screen = screenUnderMouse() else {
            print("SELFTEST-SAVE: 没有可用屏幕")
            return 3
        }

        print("SELFTEST-SAVE: 模板预览 ->", FilenameTemplate.render("Liteshot-{yyyy}{MM}{dd}-{HH}{mm}{ss}-{SSS}-{EEE}-{a}-{rand}-{seq}"))

        do {
            let image = try await ScreenCaptureService.capture(
                displayID: screen.displayID,
                pixelWidth: Int(screen.pixelSize.width),
                pixelHeight: Int(screen.pixelSize.height)
            )
            let directory = URL(fileURLWithPath: "/tmp/liteshot-save-test", isDirectory: true)
            let url = try SaveService.save(
                image: image,
                to: directory,
                format: .png,
                quality: 0.9,
                template: "selftest-{yyyy}{MM}{dd}-{HH}{mm}{ss}-{seq}"
            )
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            print("SELFTEST-SAVE: 已保存 \(url.path)（\(size) bytes）")
            return 0
        } catch {
            print("SELFTEST-SAVE: 失败 - \(error.localizedDescription)")
            return 1
        }
    }



    private static func makeSwatchImage() -> CGImage? {
        let width = 320
        let height = 200
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.10, green: 0.45, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 30, y: 30, width: 120, height: 120))
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.2, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: 170, y: 40, width: 120, height: 120))
        return context.makeImage()
    }






    @MainActor
    static func runShortcutTest() -> Int32 {
        var passed = true
        if HotkeyShortcut.regionDefault.displayString != "⌃⌘A" {
            print("SELFTEST-SHORTCUT: 默认显示错误 \(HotkeyShortcut.regionDefault.displayString)")
            passed = false
        }
        let modifiers = HotkeyShortcut.carbonModifiers(from: [.control, .command])
        if modifiers != UInt32(controlKey | cmdKey) {
            print("SELFTEST-SHORTCUT: 修饰键转换错误 \(modifiers)")
            passed = false
        }
        if HotkeyShortcut.keyName(for: UInt32(kVK_ANSI_K)) != "K" {
            print("SELFTEST-SHORTCUT: 键名映射错误")
            passed = false
        }
        print("SELFTEST-SHORTCUT: \(passed ? "PASS" : "FAIL")（显示/修饰键/键名）")
        return passed ? 0 : 1
    }

    @MainActor
    static func runPixelSamplerTest() -> Int32 {
        func makeSolid(_ color: CGColor) -> CGImage? {
            guard let context = CGContext(
                data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            return context.makeImage()
        }

        let samples: [(CGColor, String)] = [
            (CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), "#FF0000"),
            (CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), "#00FF00"),
            (CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), "#0000FF"),
        ]

        for (color, expected) in samples {
            guard let image = makeSolid(color), let sampler = PixelSampler(image: image),
                  let sampled = sampler.color(atX: 20, y: 20) else {
                print("SELFTEST-PIXEL: 取样失败")
                return 1
            }
            guard sampled.hexString == expected else {
                print("SELFTEST-PIXEL: 颜色不符，期望 \(expected) 实际 \(sampled.hexString)")
                return 1
            }
        }

        print("SELFTEST-PIXEL: PASS（红/绿/蓝取样准确）")
        return 0
    }


    @MainActor
    static func runScrollStitcherHorizontal() -> Int32 {
        let frameWidth = 400
        let pageWidth = 1200
        let frameHeight = 300

        guard let page = makeScrollPage(width: pageWidth, height: frameHeight) else {
            print("SELFTEST-SCROLLH: 生成测试页失败")
            return 1
        }

        let stitcher = ScrollStitcher(width: frameWidth, height: frameHeight, axis: .horizontal)
        var offset = 0
        while offset + frameWidth <= pageWidth {
            guard let frame = page.cropping(to: CGRect(x: offset, y: 0, width: frameWidth, height: frameHeight)) else {
                print("SELFTEST-SCROLLH: 裁剪帧失败")
                return 1
            }
            stitcher.add(frame)
            offset += 100
        }

        guard let output = stitcher.makeImage(), let png = ImageEncoding.pngData(from: output) else {
            print("SELFTEST-SCROLLH: 拼接失败")
            return 1
        }

        let url = URL(fileURLWithPath: "/tmp/liteshot-scrollh-test.png")
        try? png.write(to: url)

        let ok = abs(output.width - pageWidth) <= 10 && output.height == frameHeight
        print("SELFTEST-SCROLLH: \(ok ? "PASS" : "FAIL") 输出 \(output.width)x\(output.height)（期望 \(pageWidth)x\(frameHeight)）")
        return ok ? 0 : 2
    }


    @MainActor
    static func runPanoramaStitcher() -> Int32 {
        let pageWidth = 800
        let pageHeight = 700
        let frameWidth = 400
        let frameHeight = 300
        let origins = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 100),
            CGPoint(x: 200, y: 100),
            CGPoint(x: 400, y: 100),
        ]

        guard let page = makeScrollPage(width: pageWidth, height: pageHeight) else {
            print("SELFTEST-PANORAMA: 生成测试页失败")
            return 1
        }

        let stitcher = PanoramaStitcher(width: frameWidth, height: frameHeight)
        for origin in origins {
            guard let frame = page.cropping(to: CGRect(
                x: origin.x, y: origin.y, width: CGFloat(frameWidth), height: CGFloat(frameHeight)
            )) else {
                print("SELFTEST-PANORAMA: 裁剪帧失败")
                return 1
            }
            stitcher.add(frame)
        }

        guard let output = stitcher.makeImage(), let png = ImageEncoding.pngData(from: output) else {
            print("SELFTEST-PANORAMA: 拼接失败")
            return 1
        }
        try? png.write(to: URL(fileURLWithPath: "/tmp/liteshot-panorama-test.png"))

        let ok = abs(output.width - 800) <= 10 && abs(output.height - 400) <= 10
        print("SELFTEST-PANORAMA: \(ok ? "PASS" : "FAIL") 输出 \(output.width)x\(output.height)（期望 ~800x400）")
        return ok ? 0 : 2
    }

    @MainActor
    static func runHistoryTest() -> Int32 {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("liteshot-history-test-\(UUID().uuidString)", isDirectory: true)
        let store = HistoryStore(directory: directory, maxCount: 3)

        guard let image = makeSwatchImage() else {
            print("SELFTEST-HISTORY: 生成测试图失败")
            return 1
        }

        store.record(image)
        store.record(image)
        store.record(image)
        guard store.items.count == 3, store.items.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
            print("SELFTEST-HISTORY: 记录失败")
            return 1
        }
        guard store.image(for: store.items[0]) != nil else {
            print("SELFTEST-HISTORY: 读取失败")
            return 1
        }

        store.record(image)
        guard store.items.count == 3 else {
            print("SELFTEST-HISTORY: 上限裁剪失败（\(store.items.count)）")
            return 1
        }

        store.clear()
        guard store.items.isEmpty else {
            print("SELFTEST-HISTORY: 清空失败")
            return 1
        }
        try? FileManager.default.removeItem(at: directory)

        print("SELFTEST-HISTORY: PASS（记录/读取/上限/清空）")
        return 0
    }

    @MainActor
    static func runOCRTest() -> Int32 {
        let size = NSSize(width: 1200, height: 700)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let sample = "Liteshot OCR Test 12345"
        (sample as NSString).draw(
            at: NSPoint(x: 70, y: 430),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 64, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
        )

        if let qr = makeQRCode("https://example.com/liteshot") {
            NSImage(cgImage: qr, size: NSSize(width: qr.width, height: qr.height))
                .draw(in: NSRect(x: 780, y: 80, width: 300, height: 300))
        }
        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("SELFTEST-OCR: 生成测试图失败")
            return 1
        }

        if let png = ImageEncoding.pngData(from: cgImage) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/liteshot-ocr-test.png"))
        }

        do {
            let text = try OCRService.recognizeText(in: cgImage)
            let payloads = try OCRService.recognizeBarcodes(in: cgImage)

            let textOK = text.contains("Liteshot")
            let qrOK = payloads.contains("https://example.com/liteshot")
            print("SELFTEST-OCR: \(textOK ? "PASS" : "FAIL") 文字识别 -> \(text.replacingOccurrences(of: "\n", with: " / "))")
            print("SELFTEST-OCR: \(qrOK ? "PASS" : "FAIL") 二维码 -> \(payloads.joined(separator: " | "))")
            return textOK && qrOK ? 0 : 2
        } catch {
            print("SELFTEST-OCR: 失败 - \(error.localizedDescription)")
            return 1
        }
    }

    private static func makeQRCode(_ string: String) -> CGImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(scaled, from: scaled.extent)
    }

    @MainActor
    static func runScrollStitcher() -> Int32 {
        let width = 400
        let pageHeight = 1200
        let frameHeight = 300

        guard let page = makeScrollPage(width: width, height: pageHeight) else {
            print("SELFTEST-SCROLL: 生成测试页失败")
            return 1
        }

        var stitchedHeight = 0
        let stitcher = ScrollStitcher(width: width, height: frameHeight)
        stitcher.onUpdate = { stitchedHeight = $0 }

        var offset = 0
        while offset + frameHeight <= pageHeight {
            guard let frame = page.cropping(to: CGRect(x: 0, y: offset, width: width, height: frameHeight)) else {
                print("SELFTEST-SCROLL: 裁剪帧失败")
                return 1
            }
            stitcher.add(frame)
            offset += 60
        }

        guard let output = stitcher.makeImage(),
              let png = ImageEncoding.pngData(from: output) else {
            print("SELFTEST-SCROLL: 拼接失败")
            return 1
        }

        let url = URL(fileURLWithPath: "/tmp/liteshot-scroll-test.png")
        try? png.write(to: url)

        let expected = pageHeight
        let ok = abs(output.height - expected) <= 10 && output.width == width
        print("SELFTEST-SCROLL: \(ok ? "PASS" : "FAIL") 输出 \(output.width)x\(output.height)（期望 \(width)x\(expected)），\(png.count) bytes")
        print("SELFTEST-SCROLL: \(url.path)")
        return ok ? 0 : 2
    }

    private static func makeScrollPage(width: Int, height: Int) -> CGImage? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        var state: UInt32 = 0x1234_5678
        func nextByte() -> UInt8 {
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 16)
        }
        for index in stride(from: 0, to: data.count, by: 4) {
            data[index] = nextByte()
            data[index + 1] = nextByte()
            data[index + 2] = nextByte()
            data[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    @MainActor
    static func runDocument() -> Int32 {
        let document = EditorDocument()
        let style = ToolStyle(colorHex: "#FF3B30", lineWidth: 4, fontSize: 24)
        let rect = Annotation(
            tool: .rectangle,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 100, y: 80),
            style: style
        )
        var text = Annotation(
            tool: .text,
            start: CGPoint(x: 20, y: 120),
            end: CGPoint(x: 20, y: 120),
            style: style
        )
        text.text = "hello"

        document.add(rect)
        document.add(text)
        guard document.annotations.count == 2 else { print("SELFTEST-DOC: add failed"); return 1 }

        document.undo()
        guard document.annotations.count == 1 else { print("SELFTEST-DOC: undo failed"); return 1 }

        document.redo()
        guard document.annotations.count == 2 else { print("SELFTEST-DOC: redo failed"); return 1 }

        document.sendBackward(id: text.id)
        guard document.annotations.first?.id == text.id else { print("SELFTEST-DOC: sendBackward failed"); return 1 }

        document.bringForward(id: text.id)
        guard document.annotations.last?.id == text.id else { print("SELFTEST-DOC: bringForward failed"); return 1 }

        document.remove(id: text.id)
        guard document.annotations.count == 1 else { print("SELFTEST-DOC: remove failed"); return 1 }
        document.undo()
        guard document.annotations.count == 2 else { print("SELFTEST-DOC: undo remove failed"); return 1 }

        print("SELFTEST-DOC: PASS（add/undo/redo/layer/remove 全部通过）")
        return 0
    }

    static func runEditorRender() async -> Int32 {
        guard ScreenPermission.isGranted else {
            print("SELFTEST-EDITOR: 未授权屏幕录制")
            return 2
        }
        guard let screen = screenUnderMouse() else {
            print("SELFTEST-EDITOR: 没有可用屏幕")
            return 3
        }

        do {
            let image = try await ScreenCaptureService.capture(
                displayID: screen.displayID,
                pixelWidth: Int(screen.pixelSize.width),
                pixelHeight: Int(screen.pixelSize.height)
            )
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)

            let red = ToolStyle(colorHex: "#FF3B30", lineWidth: 10, fontSize: 72)
            let blue = ToolStyle(colorHex: "#0A84FF", lineWidth: 8, fontSize: 72)
            let yellow = ToolStyle(colorHex: "#FFD60A", lineWidth: 36, fontSize: 72)
            let white = ToolStyle(colorHex: "#FFFFFF", lineWidth: 3, fontSize: 96)

            var annotations: [Annotation] = [
                Annotation(
                    tool: .rectangle,
                    start: CGPoint(x: width * 0.08, y: height * 0.12),
                    end: CGPoint(x: width * 0.32, y: height * 0.34),
                    style: red
                ),
                Annotation(
                    tool: .ellipse,
                    start: CGPoint(x: width * 0.36, y: height * 0.52),
                    end: CGPoint(x: width * 0.58, y: height * 0.78),
                    style: blue
                ),
                Annotation(
                    tool: .arrow,
                    start: CGPoint(x: width * 0.62, y: height * 0.30),
                    end: CGPoint(x: width * 0.82, y: height * 0.14),
                    style: red
                ),
                Annotation(
                    tool: .line,
                    start: CGPoint(x: width * 0.10, y: height * 0.84),
                    end: CGPoint(x: width * 0.42, y: height * 0.84),
                    style: white
                ),
                Annotation(
                    tool: .regionHighlight,
                    start: CGPoint(x: width * 0.44, y: height * 0.62),
                    end: CGPoint(x: width * 0.60, y: height * 0.72),
                    style: yellow
                ),
            ]

            var pencil = Annotation(
                tool: .pencil,
                start: CGPoint(x: width * 0.64, y: height * 0.82),
                end: CGPoint(x: width * 0.86, y: height * 0.82),
                style: blue
            )
            pencil.points = stride(from: 0.0, through: 1.0, by: 0.05).map { t in
                CGPoint(x: width * CGFloat(0.64 + 0.22 * t), y: height * CGFloat(0.82 + 0.05 * sin(t * .pi * 2)))
            }
            annotations.append(pencil)

            var highlight = Annotation(
                tool: .highlight,
                start: CGPoint(x: width * 0.64, y: height * 0.88),
                end: CGPoint(x: width * 0.90, y: height * 0.88),
                style: yellow
            )
            highlight.points = stride(from: 0.0, through: 1.0, by: 0.05).map { t in
                CGPoint(x: width * CGFloat(0.64 + 0.26 * t), y: height * 0.88)
            }
            annotations.append(highlight)

            var text = Annotation(
                tool: .text,
                start: CGPoint(x: width * 0.08, y: height * 0.05),
                end: CGPoint(x: width * 0.08, y: height * 0.05),
                style: white
            )
            text.text = "Liteshot 标注渲染测试"
            annotations.append(text)

            var mosaic = Annotation(
                tool: .mosaic,
                start: CGPoint(x: width * 0.08, y: height * 0.30),
                end: CGPoint(x: width * 0.40, y: height * 0.30),
                style: ToolStyle(colorHex: "#000000", lineWidth: 36, fontSize: 24)
            )
            mosaic.mosaicAlgorithm = "crystal"
            mosaic.points = stride(from: 0.0, through: 1.0, by: 0.05).map { t in
                CGPoint(x: width * CGFloat(0.08 + 0.32 * t), y: height * 0.30)
            }
            annotations.append(mosaic)

            var counter1 = Annotation(tool: .counter, start: CGPoint(x: width * 0.70, y: height * 0.45), end: CGPoint(x: width * 0.70, y: height * 0.45), style: red)
            counter1.number = 1
            annotations.append(counter1)
            var counter2 = Annotation(tool: .counter, start: CGPoint(x: width * 0.78, y: height * 0.55), end: CGPoint(x: width * 0.78, y: height * 0.55), style: blue)
            counter2.number = 2
            annotations.append(counter2)

            var multiline = Annotation(
                tool: .text,
                start: CGPoint(x: width * 0.62, y: height * 0.05),
                end: CGPoint(x: width * 0.62, y: height * 0.05),
                style: ToolStyle(colorHex: "#FFFFFF", lineWidth: 4, fontSize: 56)
            )
            multiline.text = "多行文字\n第二行\n带描边"
            multiline.textAlignment = "center"
            annotations.append(multiline)

            var watermark = Annotation(
                tool: .watermark,
                start: .zero,
                end: CGPoint(x: width, y: height),
                style: ToolStyle(colorHex: "#FFFFFF", lineWidth: 0, fontSize: 42)
            )
            watermark.text = "Liteshot"
            annotations.append(watermark)

            if let swatch = makeSwatchImage() {
                var inserted = Annotation(
                    tool: .image,
                    start: CGPoint(x: width * 0.62, y: height * 0.60),
                    end: CGPoint(x: width * 0.78, y: height * 0.72),
                    style: white
                )
                inserted.imageData = ImageEncoding.pngData(from: swatch)
                annotations.append(inserted)
            }

            guard let rendered = EditorRenderer.render(image: image, annotations: annotations),
                  let png = ImageEncoding.pngData(from: rendered) else {
                print("SELFTEST-EDITOR: 渲染失败")
                return 4
            }

            let url = URL(fileURLWithPath: "/tmp/liteshot-editor-render.png")
            try png.write(to: url)
            print("SELFTEST-EDITOR: 渲染成功 \(rendered.width)x\(rendered.height)，\(annotations.count) 个元素，\(png.count) bytes")
            print("SELFTEST-EDITOR: \(url.path)")

            let exportOptions = ExportOptions(scale: 0.5, cornerRadius: 32, shadow: true, transparent: true)
            if let exported = EditorRenderer.render(image: image, annotations: annotations, options: exportOptions),
               let exportPNG = ImageEncoding.pngData(from: exported) {
                let exportURL = URL(fileURLWithPath: "/tmp/liteshot-export-test.png")
                try exportPNG.write(to: exportURL)
                print("SELFTEST-EDITOR: 导出效果 \(exported.width)x\(exported.height)（0.5x + 圆角 + 阴影 + 透明）")
                print("SELFTEST-EDITOR: \(exportURL.path)")
            } else {
                print("SELFTEST-EDITOR: 导出效果渲染失败")
            }
            return 0
        } catch {
            print("SELFTEST-EDITOR: 失败 - \(error.localizedDescription)")
            return 1
        }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
