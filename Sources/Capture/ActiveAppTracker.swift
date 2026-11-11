import AppKit

/// 记录最近一个非 Liteshot 的前台 App，供「截取活动窗口」在菜单点击场景下使用。
final class ActiveAppTracker: @unchecked Sendable {
    static let shared = ActiveAppTracker()

    private let lock = NSLock()
    private var pid: pid_t?

    private init() {}

    var lastActivePID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            guard app.processIdentifier != getpid() else { return }
            self?.setPID(app.processIdentifier)
        }
    }

    private func setPID(_ newPID: pid_t) {
        lock.lock()
        pid = newPID
        lock.unlock()
    }
}
