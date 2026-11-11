import AppKit
import CoreGraphics

enum LastAreaStore {
    private static func key(_ displayID: CGDirectDisplayID) -> String {
        "capture.lastArea.\(displayID)"
    }

    /// rect 使用图片像素坐标（左上原点）。
    static func save(_ rect: CGRect, displayID: CGDirectDisplayID) {
        UserDefaults.standard.set(NSStringFromRect(rect), forKey: key(displayID))
    }

    static func load(displayID: CGDirectDisplayID) -> CGRect? {
        guard let string = UserDefaults.standard.string(forKey: key(displayID)) else { return nil }
        let rect = NSRectFromString(string)
        return rect.width >= 1 && rect.height >= 1 ? rect : nil
    }
}
