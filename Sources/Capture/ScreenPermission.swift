import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 先看 preflight；若系统尚未刷新状态，再用一次真实的 SCShareableContent 探测。
    static func probe() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    static var appPath: String {
        Bundle.main.bundleURL.path
    }

    /// TCC 变更通常需要重启进程才生效；先安排一个延迟启动，再退出当前实例。
    static func relaunchApp() {
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "--", path]
        do {
            try process.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }
}
