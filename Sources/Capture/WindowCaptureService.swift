import AppKit
import CoreGraphics
import ScreenCaptureKit

struct CapturableWindow: Identifiable {
    let id: CGWindowID
    let frame: CGRect          // CG 全局坐标（主屏左上角为原点，y 向下）
    let ownerPID: pid_t
    let ownerName: String
    let title: String

    var displayTitle: String {
        title.isEmpty ? ownerName : "\(ownerName) — \(title)"
    }
}

enum WindowCaptureError: LocalizedError {
    case windowNotFound
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .windowNotFound:
            return L10n.t("窗口不存在或已经关闭。", "The window no longer exists or has closed.")
        case .captureFailed(let message):
            return L10n.t("窗口截取失败：", "Window capture failed: ") + message
        }
    }
}

enum WindowCaptureService {
    /// 按 z 序（前 → 后）返回屏幕上可截取的窗口。
    static func windows(on displayID: CGDirectDisplayID? = nil) -> [CapturableWindow] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let displayBounds = displayID.map { CGDisplayBounds($0) }
        var result: [CapturableWindow] = []

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let windowID = CGWindowID(exactly: number) else { continue }
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != getpid() else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard frame.width >= 24, frame.height >= 24 else { continue }

            if let displayBounds, !frame.intersects(displayBounds) { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""
            result.append(
                CapturableWindow(
                    id: windowID,
                    frame: frame,
                    ownerPID: pid,
                    ownerName: owner,
                    title: title
                )
            )
        }
        return result
    }

    static func capture(
        windowID: CGWindowID,
        pixelWidth: Int,
        pixelHeight: Int,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw WindowCaptureError.captureFailed(error.localizedDescription)
        }

        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw WindowCaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, pixelWidth)
        config.height = max(1, pixelHeight)
        config.showsCursor = showsCursor

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw WindowCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
