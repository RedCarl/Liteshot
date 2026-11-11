import AppKit

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private var isChecking = false

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true

        Task { @MainActor in
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                if Self.isNewer(release.version, than: currentVersion) {
                    presentUpdate(release)
                } else {
                    presentUpToDate()
                }
            } catch UpdateError.noReleases {
                presentInfo(
                    title: L10n.t("暂无发布版本", "No Releases Yet"),
                    message: L10n.t("GitHub 上还没有正式发布。", "There are no published releases on GitHub yet.")
                )
            } catch {
                presentInfo(
                    title: L10n.t("检查更新失败", "Update Check Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    static func isNewer(_ remote: String, than current: String) -> Bool {
        remote.compare(current, options: .numeric) == .orderedDescending
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/RedCarl/Liteshot/releases/latest") else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Liteshot/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        if http.statusCode == 404 {
            throw UpdateError.noReleases
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func presentUpdate(_ release: GitHubRelease) {
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = notes.count > 1200 ? String(notes.prefix(1200)) + "…" : notes

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.t("发现新版本 ", "New version available: ") + release.version
        alert.informativeText = preview.isEmpty
            ? L10n.t("当前版本 \(currentVersion)，可下载最新版本。", "You are on \(currentVersion). A newer version is available.")
            : L10n.t("当前版本 \(currentVersion)。\n\n", "You are on \(currentVersion).\n\n") + preview
        alert.addButton(withTitle: L10n.t("下载", "Download"))
        alert.addButton(withTitle: L10n.t("稍后", "Later"))

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func presentUpToDate() {
        presentInfo(
            title: L10n.t("已是最新版本", "You're Up to Date"),
            message: L10n.t("当前版本 \(currentVersion)。", "You are running Liteshot \(currentVersion).")
        )
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noReleases
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.t("更新地址无效。", "Invalid update URL.")
        case .invalidResponse:
            return L10n.t("服务器返回了无效响应。", "The server returned an invalid response.")
        case .noReleases:
            return L10n.t("GitHub 上还没有正式发布。", "There are no published releases on GitHub yet.")
        case .httpStatus(let code):
            return L10n.t("GitHub 返回状态码 ", "GitHub returned HTTP ") + "\(code)"
        }
    }
}
