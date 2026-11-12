import AppKit
import SwiftUI

@MainActor
final class UpdateModel: ObservableObject {
    let release: GitHubRelease
    let currentVersion: String

    @Published var downloading = false
    @Published var downloadedURL: URL?
    @Published var errorMessage: String?

    var close: () -> Void = {}

    init(release: GitHubRelease, currentVersion: String) {
        self.release = release
        self.currentVersion = currentVersion
    }

    var notes: String {
        let text = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L10n.t("这个版本没有写更新说明。", "No release notes for this version.") : text
    }

    func download() {
        guard !downloading else { return }
        guard let asset = release.zipAsset else {
            errorMessage = L10n.t("这个版本没有可下载的 zip 包。", "This release has no downloadable zip asset.")
            return
        }

        downloading = true
        errorMessage = nil
        let direct = asset.downloadURL
        let mirror = URL(string: "https://gh-proxy.com/" + direct.absoluteString)

        Task { @MainActor in
            defer { downloading = false }
            var temporaryURL: URL?
            if let mirror {
                temporaryURL = try? await Self.fetch(mirror)
            }
            if temporaryURL == nil {
                temporaryURL = try? await Self.fetch(direct)
            }
            guard let temporaryURL else {
                errorMessage = L10n.t("下载失败，请稍后重试。", "Download failed. Please try again.")
                return
            }

            let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            var destination = directory.appendingPathComponent(asset.name)
            if FileManager.default.fileExists(atPath: destination.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                let base = (asset.name as NSString).deletingPathExtension
                let ext = (asset.name as NSString).pathExtension
                destination = directory.appendingPathComponent("\(base)-\(stamp).\(ext)")
            }

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                downloadedURL = destination
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func fetch(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Liteshot/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.invalidResponse
        }
        return temporary
    }
}

struct UpdateView: View {
    @ObservedObject var model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("发现新版本 ", "New version available: ") + model.release.version)
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.t("当前版本 ", "You are on ") + model.currentVersion)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(model.notes)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 190)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if model.downloadedURL != nil {
                Text(L10n.t(
                    "已下载到 Downloads。解压后把 Liteshot.app 拖进「应用程序」即可完成更新。",
                    "Downloaded to Downloads. Unzip it and replace Liteshot.app in Applications."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(L10n.t("查看发布页", "Release Page")) {
                    NSWorkspace.shared.open(model.release.htmlURL)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))

                Spacer()

                if model.downloading {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("正在下载…", "Downloading…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let url = model.downloadedURL {
                    Button(L10n.t("在 Finder 中显示", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button(L10n.t("完成", "Done")) {
                        model.close()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.t("稍后", "Later")) {
                        model.close()
                    }
                    Button(L10n.t("下载更新", "Download Update")) {
                        model.download()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    private static var current: UpdateWindowController?

    private let model: UpdateModel

    static func show(release: GitHubRelease, currentVersion: String) {
        if let current, current.window?.isVisible == true {
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = UpdateWindowController(release: release, currentVersion: currentVersion)
        current = controller
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init(release: GitHubRelease, currentVersion: String) {
        model = UpdateModel(release: release, currentVersion: currentVersion)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("软件更新", "Software Update")
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self

        let hosting = NSHostingController(rootView: UpdateView(model: model))
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 560, height: 430))
        model.close = { [weak self] in
            self?.window?.close()
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            window.setFrameOrigin(CGPoint(
                x: screen.frame.midX - window.frame.width / 2,
                y: screen.frame.midY - window.frame.height / 2
            ))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if Self.current === self {
            Self.current = nil
        }
    }
}
