import AppKit
import Combine

enum ImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var uti: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var saveDirectoryPath: String {
        didSet { store.set(saveDirectoryPath, forKey: Keys.saveDirectory) }
    }

    /// 沙盒下用户自选目录只在当次运行有效，必须存安全作用域书签才能在重启后继续写入。
    @Published var saveDirectoryBookmark: Data? {
        didSet { store.set(saveDirectoryBookmark, forKey: Keys.saveDirectoryBookmark) }
    }

    @Published var format: ImageFormat {
        didSet { store.set(format.rawValue, forKey: Keys.format) }
    }

    @Published var jpegQuality: Double {
        didSet { store.set(jpegQuality, forKey: Keys.jpegQuality) }
    }

    @Published var autoSave: Bool {
        didSet { store.set(autoSave, forKey: Keys.autoSave) }
    }

    @Published var copyToClipboard: Bool {
        didSet { store.set(copyToClipboard, forKey: Keys.copyToClipboard) }
    }

    @Published var revealInFinder: Bool {
        didSet { store.set(revealInFinder, forKey: Keys.revealInFinder) }
    }

    @Published var delaySeconds: Int {
        didSet { store.set(delaySeconds, forKey: Keys.delaySeconds) }
    }

    @Published var includeCursor: Bool {
        didSet { store.set(includeCursor, forKey: Keys.includeCursor) }
    }

    @Published var showMagnifier: Bool {
        didSet { store.set(showMagnifier, forKey: Keys.showMagnifier) }
    }

    @Published var exportShadowBlur: Double {
        didSet { store.set(exportShadowBlur, forKey: Keys.exportShadowBlur) }
    }

    @Published var exportShadowOpacity: Double {
        didSet { store.set(exportShadowOpacity, forKey: Keys.exportShadowOpacity) }
    }

    @Published var maskOpacity: Double {
        didSet { store.set(maskOpacity, forKey: Keys.maskOpacity) }
    }

    @Published var sizeLabelAtTop: Bool {
        didSet { store.set(sizeLabelAtTop, forKey: Keys.sizeLabelAtTop) }
    }

    @Published var maskColorHex: String {
        didSet { store.set(maskColorHex, forKey: Keys.maskColorHex) }
    }

    @Published var exportShadowColorHex: String {
        didSet { store.set(exportShadowColorHex, forKey: Keys.exportShadowColorHex) }
    }

    @Published var highlightColorHex: String {
        didSet { store.set(highlightColorHex, forKey: Keys.highlightColorHex) }
    }

    @Published var ocrAppendToClipboard: Bool {
        didSet { store.set(ocrAppendToClipboard, forKey: Keys.ocrAppendToClipboard) }
    }

    @Published var ocrPreserveNewlines: Bool {
        didSet { store.set(ocrPreserveNewlines, forKey: Keys.ocrPreserveNewlines) }
    }

    @Published var snapToEdges: Bool {
        didSet { store.set(snapToEdges, forKey: Keys.snapToEdges) }
    }

    @Published var language: AppLanguage {
        didSet { store.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var regionShortcut: HotkeyShortcut {
        didSet { saveShortcut(regionShortcut, key: Keys.regionShortcut) }
    }

    @Published var fullScreenShortcut: HotkeyShortcut {
        didSet { saveShortcut(fullScreenShortcut, key: Keys.fullScreenShortcut) }
    }

    @Published var windowShortcut: HotkeyShortcut {
        didSet { saveShortcut(windowShortcut, key: Keys.windowShortcut) }
    }

    @Published var filenameTemplate: String {
        didSet { store.set(filenameTemplate, forKey: Keys.filenameTemplate) }
    }

    @Published var exportScale1x: Bool {
        didSet { store.set(exportScale1x, forKey: Keys.exportScale1x) }
    }

    @Published var exportCornerRadius: Int {
        didSet { store.set(exportCornerRadius, forKey: Keys.exportCornerRadius) }
    }

    @Published var exportShadow: Bool {
        didSet { store.set(exportShadow, forKey: Keys.exportShadow) }
    }

    @Published var exportTransparent: Bool {
        didSet { store.set(exportTransparent, forKey: Keys.exportTransparent) }
    }

    private let store = UserDefaults.standard

    private enum Keys {
        static let saveDirectory = "settings.saveDirectory"
        static let saveDirectoryBookmark = "settings.saveDirectoryBookmark"
        static let format = "settings.format"
        static let jpegQuality = "settings.jpegQuality"
        static let autoSave = "settings.autoSave"
        static let copyToClipboard = "settings.copyToClipboard"
        static let revealInFinder = "settings.revealInFinder"
        static let delaySeconds = "settings.delaySeconds"
        static let includeCursor = "settings.includeCursor"
        static let showMagnifier = "settings.showMagnifier"
        static let snapToEdges = "settings.snapToEdges"
        static let ocrPreserveNewlines = "settings.ocrPreserveNewlines"
        static let ocrAppendToClipboard = "settings.ocrAppendToClipboard"
        static let maskOpacity = "settings.maskOpacity"
        static let exportShadowBlur = "settings.exportShadowBlur"
        static let exportShadowOpacity = "settings.exportShadowOpacity"
        static let highlightColorHex = "settings.highlightColorHex"
        static let maskColorHex = "settings.maskColorHex"
        static let exportShadowColorHex = "settings.exportShadowColorHex"
        static let sizeLabelAtTop = "settings.sizeLabelAtTop"
        static let language = L10n.languageKey
        static let regionShortcut = "settings.shortcut.region"
        static let fullScreenShortcut = "settings.shortcut.fullscreen"
        static let windowShortcut = "settings.shortcut.window"
        static let filenameTemplate = "settings.filenameTemplate"
        static let exportScale1x = "settings.exportScale1x"
        static let exportCornerRadius = "settings.exportCornerRadius"
        static let exportShadow = "settings.exportShadow"
        static let exportTransparent = "settings.exportTransparent"
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedBookmark = defaults.data(forKey: Keys.saveDirectoryBookmark)
        let storedPath = defaults.string(forKey: Keys.saveDirectory)
        // 沙盒下以前记下的路径可能已经写不进去（换签名、换机器、权限收紧），启动时自愈一次；
        // 有书签时以书签为准，不去碰用户自己选的目录。
        if let storedPath,
           storedBookmark != nil || Self.canWrite(into: URL(fileURLWithPath: storedPath, isDirectory: true)) {
            saveDirectoryPath = storedPath
        } else {
            saveDirectoryPath = Self.defaultSaveDirectory.path
        }
        saveDirectoryBookmark = storedBookmark
        format = ImageFormat(rawValue: defaults.string(forKey: Keys.format) ?? "") ?? .png
        jpegQuality = defaults.object(forKey: Keys.jpegQuality) as? Double ?? 0.9
        autoSave = defaults.bool(forKey: Keys.autoSave)
        copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        revealInFinder = defaults.bool(forKey: Keys.revealInFinder)
        delaySeconds = defaults.object(forKey: Keys.delaySeconds) as? Int ?? 5
        includeCursor = defaults.bool(forKey: Keys.includeCursor)
        showMagnifier = defaults.object(forKey: Keys.showMagnifier) as? Bool ?? true
        snapToEdges = defaults.object(forKey: Keys.snapToEdges) as? Bool ?? true
        ocrPreserveNewlines = defaults.object(forKey: Keys.ocrPreserveNewlines) as? Bool ?? true
        ocrAppendToClipboard = defaults.object(forKey: Keys.ocrAppendToClipboard) as? Bool ?? false
        maskOpacity = defaults.object(forKey: Keys.maskOpacity) as? Double ?? 0.45
        exportShadowBlur = defaults.object(forKey: Keys.exportShadowBlur) as? Double ?? 18
        exportShadowOpacity = defaults.object(forKey: Keys.exportShadowOpacity) as? Double ?? 0.45
        highlightColorHex = defaults.string(forKey: Keys.highlightColorHex) ?? "#0A84FF"
        maskColorHex = defaults.string(forKey: Keys.maskColorHex) ?? "#000000"
        exportShadowColorHex = defaults.string(forKey: Keys.exportShadowColorHex) ?? "#000000"
        sizeLabelAtTop = defaults.object(forKey: Keys.sizeLabelAtTop) as? Bool ?? false
        language = AppLanguage(rawValue: defaults.string(forKey: L10n.languageKey) ?? "") ?? .system
        regionShortcut = Self.loadShortcut(
            key: Keys.regionShortcut,
            default: .regionDefault,
            defaults: defaults
        )
        fullScreenShortcut = Self.loadShortcut(
            key: Keys.fullScreenShortcut,
            default: .fullScreenDefault,
            defaults: defaults
        )
        windowShortcut = Self.loadShortcut(
            key: Keys.windowShortcut,
            default: .windowDefault,
            defaults: defaults
        )
        filenameTemplate = defaults.string(forKey: Keys.filenameTemplate)
            ?? "Liteshot-{yyyy}{MM}{dd}-{HH}{mm}{ss}-{seq}"
        exportScale1x = defaults.bool(forKey: Keys.exportScale1x)
        exportCornerRadius = defaults.integer(forKey: Keys.exportCornerRadius)
        exportShadow = defaults.bool(forKey: Keys.exportShadow)
        exportTransparent = defaults.bool(forKey: Keys.exportTransparent)
    }

    private func saveShortcut(_ shortcut: HotkeyShortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            store.set(data, forKey: key)
        }
    }

    private static func loadShortcut(
        key: String,
        default fallback: HotkeyShortcut,
        defaults: UserDefaults
    ) -> HotkeyShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) else {
            return fallback
        }
        return shortcut
    }

    var saveDirectory: URL {
        if let bookmark = saveDirectoryBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }
        return URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }

    /// 沙盒里并非所有标准目录都放行（实测图片文件夹不可写、下载文件夹可写），
    /// 所以按「真能写进去」挑默认目录，挑不到再退回下载文件夹，避免首屏截图保存失败。
    static var defaultSaveDirectory: URL {
        let candidates: [FileManager.SearchPathDirectory] = [.picturesDirectory, .downloadsDirectory]
        for directory in candidates {
            guard let base = FileManager.default.urls(for: directory, in: .userDomainMask).first else { continue }
            let target = base.appendingPathComponent("Liteshot", isDirectory: true)
            if canWrite(into: target) { return target }
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return downloads.appendingPathComponent("Liteshot", isDirectory: true)
    }

    private static func canWrite(into directory: URL) -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appendingPathComponent(".liteshot-write-check")
            try Data().write(to: probe)
            try? manager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
            saveDirectoryBookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }
}
