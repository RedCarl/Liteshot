import AppKit

struct GitHubRelease: Decodable {
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

    var zipAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
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

    func check(manual: Bool = true) {
        guard !isChecking else { return }
        isChecking = true

        Task { @MainActor in
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                if Self.isNewer(release.version, than: currentVersion) {
                    UpdateWindowController.show(release: release, currentVersion: currentVersion)
                } else if manual {
                    presentInfo(
                        title: L10n.t("已是最新版本", "You're Up to Date"),
                        message: L10n.t("当前版本 \(currentVersion)。", "You are running Liteshot \(currentVersion).")
                    )
                }
            } catch {
                if manual {
                    presentInfo(
                        title: L10n.t("检查更新失败", "Update Check Failed"),
                        message: error.localizedDescription
                    )
                }
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

enum UpdateError: LocalizedError {
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
