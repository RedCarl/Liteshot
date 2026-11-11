import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case displayNotFound
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return L10n.t("没有找到对应的显示器。", "Display not found.")
        case .captureFailed(let message):
            return L10n.t("截屏失败：", "Capture failed: ") + message
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    var pixelSize: CGSize {
        CGSize(
            width: (frame.width * backingScaleFactor).rounded(),
            height: (frame.height * backingScaleFactor).rounded()
        )
    }
}

struct ScreenCaptureService {
    /// 抓取指定显示器的整帧。参数全部是 Sendable 值，避免把 NSScreen 送进后台执行器。
    static func capture(
        displayID: CGDirectDisplayID,
        pixelWidth: Int,
        pixelHeight: Int,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = showsCursor

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
