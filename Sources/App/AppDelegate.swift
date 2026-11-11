import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var historyCursor = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        ActiveAppTracker.shared.start()
        setupMainMenu()
        setupStatusItem()
        setUpHotKeys()
        handleDebugArguments()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        editItem.title = L10n.t("编辑", "Edit")
        let editMenu = NSMenu(title: L10n.t("编辑", "Edit"))
        editMenu.addItem(withTitle: L10n.t("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.t("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("剪切", "Cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("拷贝", "Copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("粘贴", "Paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("全选", "Select All"), action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Liteshot")
            button.image?.isTemplate = true
            button.toolTip = L10n.t("Liteshot · 开始截图 ⌃⌘A", "Liteshot · Start Capture ⌃⌘A")
        }

        let menu = NSMenu()

        menu.addItem(menuItem(
            title: L10n.t("开始截图", "Start Capture"),
            action: #selector(captureAdaptive),
            key: "a",
            modifiers: [.control, .command]
        ))
        menu.addItem(menuItem(title: L10n.t("截图复制", "Capture and Copy"), action: #selector(captureCopy)))

        menu.addItem(menuItem(title: L10n.t("滚动截图", "Scrolling Capture"), action: #selector(captureScroll)))

        let moreItem = NSMenuItem(title: L10n.t("更多截图", "More Capture Modes"), action: nil, keyEquivalent: "")
        let moreMenu = NSMenu(title: L10n.t("更多截图", "More Capture Modes"))
        moreMenu.addItem(menuItem(title: L10n.t("全屏截图", "Full Screen"), action: #selector(captureFullScreen)))
        moreMenu.addItem(menuItem(title: L10n.t("截取活动窗口", "Capture Active Window"), action: #selector(captureActiveWindow)))
        moreMenu.addItem(menuItem(title: L10n.t("截取上一次区域", "Capture Last Area"), action: #selector(captureLastArea)))
        moreMenu.addItem(menuItem(title: L10n.t("截取上一次区域并保存", "Capture Last Area and Save"), action: #selector(captureLastAreaAndSave)))
        moreMenu.addItem(menuItem(title: L10n.t("截取上一次区域并复制", "Capture Last Area and Copy"), action: #selector(captureLastAreaAndCopy)))
        let delayItem = NSMenuItem(title: L10n.t("延迟截图", "Delayed Capture"), action: nil, keyEquivalent: "")
        let delayMenu = NSMenu(title: L10n.t("延迟截图", "Delayed Capture"))
        delayMenu.addItem(menuItem(title: L10n.t("3 秒", "3 seconds"), action: #selector(captureDelayed3)))
        delayMenu.addItem(menuItem(title: L10n.t("5 秒", "5 seconds"), action: #selector(captureDelayed5)))
        delayMenu.addItem(menuItem(title: L10n.t("10 秒", "10 seconds"), action: #selector(captureDelayed10)))
        delayItem.submenu = delayMenu
        moreMenu.addItem(delayItem)
        moreMenu.addItem(menuItem(title: L10n.t("跨屏区域截图", "Cross-Display Region"), action: #selector(captureCrossScreen)))
        moreMenu.addItem(.separator())
        moreMenu.addItem(menuItem(title: L10n.t("上一张截图", "Previous Screenshot"), action: #selector(openPreviousScreenshot)))
        moreMenu.addItem(menuItem(title: L10n.t("下一张截图", "Next Screenshot"), action: #selector(openNextScreenshot)))
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)
        // 保留 OCR / 二维码为快捷动作。
        menu.addItem(menuItem(title: L10n.t("截图 OCR", "Text OCR"), action: #selector(captureOCR)))
        menu.addItem(menuItem(title: L10n.t("静默 OCR", "Silent OCR"), action: #selector(captureSilentOCR)))
        menu.addItem(menuItem(title: L10n.t("显示 OCR 窗口", "Show OCR Window"), action: #selector(showOCRWindow)))
        let newlineItem = menuItem(
            title: L10n.t("保留 OCR 文字换行", "Preserve OCR Line Breaks"),
            action: #selector(toggleOCRNewlines)
        )
        newlineItem.state = AppSettings.shared.ocrPreserveNewlines ? .on : .off
        menu.addItem(newlineItem)

        let appendItem = menuItem(
            title: L10n.t("增量添加到剪贴板", "Append OCR to Clipboard"),
            action: #selector(toggleOCRAppend)
        )
        appendItem.state = AppSettings.shared.ocrAppendToClipboard ? .on : .off
        menu.addItem(appendItem)
        menu.addItem(menuItem(title: L10n.t("截图二维码", "QR / Barcode"), action: #selector(captureQR)))

        menu.addItem(.separator())
        menu.addItem(menuItem(title: L10n.t("贴图（从剪贴板）", "Pin from Clipboard"), action: #selector(pinFromClipboard)))
        menu.addItem(menuItem(title: L10n.t("隐藏/显示所有贴图", "Hide/Show All Pins"), action: #selector(togglePins)))
        menu.addItem(menuItem(title: L10n.t("截图历史", "Capture History"), action: #selector(openHistory)))

        menu.addItem(.separator())

        let settingsItem = menuItem(title: L10n.t("设置…", "Settings…"), action: #selector(openSettings), key: ",", modifiers: [.command])
        menu.addItem(settingsItem)
        menu.addItem(menuItem(title: L10n.t("屏幕录制权限…", "Screen Recording Permission…"), action: #selector(openScreenRecordingSettings)))

        menu.addItem(.separator())
        menu.addItem(menuItem(title: L10n.t("检查更新…", "Check for Updates…"), action: #selector(checkForUpdates)))
        menu.addItem(menuItem(title: L10n.t("关于 Liteshot", "About Liteshot"), action: #selector(openAbout)))
        menu.addItem(NSMenuItem(title: L10n.t("退出 Liteshot", "Quit Liteshot"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func setUpHotKeys() {
        let center = HotKeyCenter.shared
        center.setHandler(id: 1) { CaptureCoordinator.shared.begin(.region) }
        center.setHandler(id: 2) { CaptureCoordinator.shared.begin(.fullScreen) }
        center.setHandler(id: 3) { CaptureCoordinator.shared.begin(.window) }
        refreshHotKeys()
    }

    func refreshLocalization() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        setupStatusItem()
    }

    func refreshHotKeys() {
        let center = HotKeyCenter.shared
        let settings = AppSettings.shared
        center.unregisterAll()
        center.register(
            id: 1,
            keyCode: settings.regionShortcut.keyCode,
            modifiers: settings.regionShortcut.modifiers
        )

    }

    @objc private func captureAdaptive() {
        CaptureCoordinator.shared.begin(.adaptive)
    }

    @objc private func captureCopy() {
        CaptureCoordinator.shared.begin(.adaptiveCopy)
    }

    @objc private func captureSilentOCR() {
        CaptureCoordinator.shared.begin(.ocrSilent)
    }

    @objc private func showOCRWindow() {
        OCRResultWindowController.shared.showLast()
    }

    @objc private func toggleOCRAppend() {
        AppSettings.shared.ocrAppendToClipboard.toggle()
        if let item = statusItem?.menu?.items.first(where: { $0.action == #selector(toggleOCRAppend) }) {
            item.state = AppSettings.shared.ocrAppendToClipboard ? .on : .off
        }
    }

    @objc private func toggleOCRNewlines() {
        let settings = AppSettings.shared
        settings.ocrPreserveNewlines.toggle()
        if let item = (NSApp.delegate as? AppDelegate)?.statusItem?.menu?.items.first(where: {
            $0.action == #selector(toggleOCRNewlines)
        }) {
            item.state = settings.ocrPreserveNewlines ? .on : .off
        }
    }

    @objc private func openPreviousScreenshot() {
        openHistoryScreenshot(offset: 1)
    }

    @objc private func openNextScreenshot() {
        openHistoryScreenshot(offset: -1)
    }

    private func openHistoryScreenshot(offset: Int) {
        let items = HistoryStore.shared.items
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        historyCursor = min(max(historyCursor + offset, 0), items.count - 1)
        let item = items[historyCursor]
        guard let image = NSImage(contentsOf: item.url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSSound.beep()
            return
        }
        EditorWindowController.open(image: cgImage)
    }

    @objc private func historyPreviousDebug() {
        openHistoryScreenshot(offset: 1)
    }

    @objc private func captureRegion() {
        CaptureCoordinator.shared.begin(.region)
    }

    @objc private func captureWindow() {
        CaptureCoordinator.shared.begin(.window)
    }

    @objc private func captureFullScreen() {
        CaptureCoordinator.shared.begin(.fullScreen)
    }

    @objc private func captureActiveWindow() {
        CaptureCoordinator.shared.begin(.activeWindow)
    }

    @objc private func captureLastArea() {
        CaptureCoordinator.shared.begin(.lastArea)
    }

    @objc private func captureLastAreaAndSave() {
        CaptureCoordinator.shared.begin(.lastAreaSave)
    }

    @objc private func captureLastAreaAndCopy() {
        CaptureCoordinator.shared.begin(.lastAreaCopy)
    }

    @objc private func captureDelayed() {
        CaptureCoordinator.shared.begin(.delayed)
    }

    @objc private func captureDelayed3() {
        CaptureCoordinator.shared.beginDelayed(seconds: 3)
    }

    @objc private func captureDelayed5() {
        CaptureCoordinator.shared.beginDelayed(seconds: 5)
    }

    @objc private func captureDelayed10() {
        CaptureCoordinator.shared.beginDelayed(seconds: 10)
    }

    @objc private func captureScroll() {
        CaptureCoordinator.shared.begin(.scroll)
    }

    @objc private func captureScrollHorizontal() {
        CaptureCoordinator.shared.begin(.scrollHorizontal)
    }

    @objc private func capturePanorama() {
        CaptureCoordinator.shared.begin(.panorama)
    }

    @objc private func captureCrossScreen() {
        CaptureCoordinator.shared.begin(.crossScreen)
    }

    @objc private func captureOCR() {
        CaptureCoordinator.shared.begin(.ocr)
    }

    @objc private func captureQR() {
        CaptureCoordinator.shared.begin(.qr)
    }

    @objc private func pinFromClipboard() {
        if !PinManager.shared.pinFromPasteboard() {
            let alert = NSAlert()
            alert.messageText = L10n.t("剪贴板里没有图片", "No image in the clipboard")
            alert.informativeText = L10n.t("先复制一张图片，再试一次。", "Copy an image first, then try again.")
            alert.addButton(withTitle: L10n.t("好", "OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.check()
    }

    @objc private func openAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func openHistory() {
        HistoryWindowController.shared.show()
    }

    @objc private func togglePins() {
        if PinManager.shared.areHidden {
            PinManager.shared.showAll()
        } else {
            PinManager.shared.hideAll()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openScreenRecordingSettings() {
        CaptureCoordinator.shared.showPermissionGuide()
    }

    // MARK: - Debug hooks

    private static func makeDemoPinImage() -> CGImage? {
        let width = 640
        let height = 400
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.10, green: 0.35, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 40, y: 60, width: 240, height: 240))
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.2, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: 340, y: 90, width: 220, height: 220))
        return context.makeImage()
    }

    private func handleDebugArguments() {
        #if DEBUG
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindowController.shared.show()
            }
        }

        if CommandLine.arguments.contains("--check-updates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                UpdateChecker.shared.check()
            }
        }

        if CommandLine.arguments.contains("--history-prev") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.openHistoryScreenshot(offset: 1)
            }
        }

        if CommandLine.arguments.contains("--show-ocr") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                OCRResultWindowController.shared.showLast()
            }
        }

        if CommandLine.arguments.contains("--open-about") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                AboutWindowController.shared.show()
            }
        }

        if CommandLine.arguments.contains("--open-history") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                HistoryWindowController.shared.show()
            }
        }

        if CommandLine.arguments.contains("--history-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                for _ in 0..<3 {
                    if let image = Self.makeDemoPinImage() {
                        HistoryStore.shared.record(image)
                    }
                }
                HistoryWindowController.shared.show()
            }
        }

        if CommandLine.arguments.contains("--pin-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let image = Self.makeDemoPinImage() {
                    PinManager.shared.pin(image)
                }
            }
        }

        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--capture=") }) else {
            return
        }
        let value = String(argument.dropFirst("--capture=".count))
        let mode: CaptureMode?
        var delayOverride: Int?
        switch value {
        case "region": mode = .region
        case "window": mode = .window
        case "full": mode = .fullScreen
        case "active": mode = .activeWindow
        case "last": mode = .lastArea
        case "delayed": mode = .delayed
        case "delayed3": mode = .delayed; delayOverride = 3
        case "delayed5": mode = .delayed; delayOverride = 5
        case "delayed10": mode = .delayed; delayOverride = 10
        case "adaptive": mode = .adaptive
        case "copy": mode = .adaptiveCopy
        case "ocrsilent": mode = .ocrSilent
        case "lastsave": mode = .lastAreaSave
        case "lastcopy": mode = .lastAreaCopy
        case "scroll": mode = .scroll
        case "scrollh": mode = .scrollHorizontal
        case "panorama": mode = .panorama
        case "cross": mode = .crossScreen
        case "ocr": mode = .ocr
        case "qr": mode = .qr
        default: mode = nil
        }
        guard let mode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            CaptureCoordinator.shared.begin(mode, delayOverride: delayOverride)
        }
        #endif
    }
}
