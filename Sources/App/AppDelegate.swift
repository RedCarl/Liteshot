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

        // 只做非侵入式检查；没有权限时显示专用权限窗口，不主动拉系统 TCC 弹窗。
        if !ScreenPermission.isGranted,
           !UserDefaults.standard.bool(forKey: "settings.permissionSuppressOnLaunch") {
            PermissionWindowController.shared.show()
        }
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
            let shortcut = AppSettings.shared.regionShortcut.displayString
            button.toolTip = L10n.t("Liteshot · 开始截图 ", "Liteshot · Start Capture ") + shortcut
        }

        // 截图相关的模式与动作全部收进悬浮工具条；菜单只保留入口和 App 级操作。
        let menu = NSMenu()

        let captureShortcut = AppSettings.shared.regionShortcut
        menu.addItem(menuItem(
            title: L10n.t("开始截图", "Start Capture"),
            action: #selector(captureAdaptive),
            key: captureShortcut.menuKeyEquivalent,
            modifiers: captureShortcut.menuModifiers,
            symbol: "camera.viewfinder"
        ))
        menu.addItem(menuItem(
            title: L10n.t("截图历史", "Capture History"),
            action: #selector(openHistory),
            symbol: "clock.arrow.circlepath"
        ))
        menu.addItem(menuItem(
            title: L10n.t("贴图（从剪贴板）", "Pin from Clipboard"),
            action: #selector(pinFromClipboard),
            symbol: "pin"
        ))
        menu.addItem(menuItem(
            title: L10n.t("隐藏/显示所有贴图", "Hide/Show All Pins"),
            action: #selector(togglePins),
            symbol: "pin.slash"
        ))

        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: L10n.t("设置…", "Settings…"),
            action: #selector(openSettings),
            key: ",",
            modifiers: [.command],
            symbol: "gearshape"
        ))

        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: L10n.t("检查更新…", "Check for Updates…"),
            action: #selector(checkForUpdates),
            symbol: "arrow.triangle.2.circlepath"
        ))
        menu.addItem(menuItem(
            title: L10n.t("关于 Liteshot", "About Liteshot"),
            action: #selector(openAbout),
            symbol: "info.circle"
        ))
        let quitItem = NSMenuItem(
            title: L10n.t("退出 Liteshot", "Quit Liteshot"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = menuImage("power")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func menuItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        if let symbol {
            item.image = menuImage(symbol)
        }
        return item
    }

    private func menuImage(_ symbol: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func setUpHotKeys() {
        let center = HotKeyCenter.shared
        center.setHandler(id: 1) { CaptureCoordinator.shared.begin(.adaptive) }
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

    @objc private func showPreviousOCR() {
        OCRResultWindowController.shared.showPreviousResult()
    }

    @objc private func showNextOCR() {
        OCRResultWindowController.shared.showNextResult()
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
        if CommandLine.arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.statusItem?.button?.performClick(nil)
            }
        }

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

        if CommandLine.arguments.contains("--ocr-queue-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                OCRResultWindowController.shared.show(title: "OCR Demo", text: "FIRST RESULT")
                OCRResultWindowController.shared.show(title: "OCR Demo", text: "SECOND RESULT")
                OCRResultWindowController.shared.showPreviousResult()
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
                if CommandLine.arguments.contains("--pin-save-demo") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        PinManager.shared.saveFrontmost()
                    }
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
