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

    @Published var openEditorAfterCapture: Bool {
        didSet { store.set(openEditorAfterCapture, forKey: Keys.openEditorAfterCapture) }
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
        static let format = "settings.format"
        static let jpegQuality = "settings.jpegQuality"
        static let autoSave = "settings.autoSave"
        static let copyToClipboard = "settings.copyToClipboard"
        static let openEditorAfterCapture = "settings.openEditorAfterCapture"
        static let revealInFinder = "settings.revealInFinder"
        static let delaySeconds = "settings.delaySeconds"
        static let includeCursor = "settings.includeCursor"
        static let showMagnifier = "settings.showMagnifier"
        static let snapToEdges = "settings.snapToEdges"
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
        saveDirectoryPath = defaults.string(forKey: Keys.saveDirectory) ?? Self.defaultSaveDirectory.path
        format = ImageFormat(rawValue: defaults.string(forKey: Keys.format) ?? "") ?? .png
        jpegQuality = defaults.object(forKey: Keys.jpegQuality) as? Double ?? 0.9
        autoSave = defaults.bool(forKey: Keys.autoSave)
        copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        openEditorAfterCapture = defaults.object(forKey: Keys.openEditorAfterCapture) as? Bool ?? true
        revealInFinder = defaults.bool(forKey: Keys.revealInFinder)
        delaySeconds = defaults.object(forKey: Keys.delaySeconds) as? Int ?? 5
        includeCursor = defaults.bool(forKey: Keys.includeCursor)
        showMagnifier = defaults.object(forKey: Keys.showMagnifier) as? Bool ?? true
        snapToEdges = defaults.object(forKey: Keys.snapToEdges) as? Bool ?? true
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
        URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }

    static var defaultSaveDirectory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("Liteshot", isDirectory: true)
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
        }
    }
}
