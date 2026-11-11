import Carbon.HIToolbox
import Foundation

/// 全局快捷键（Carbon RegisterEventHotKey）。
/// Carbon 热键不需要辅助功能权限；回调发生在主线程的 RunLoop 上。
final class HotKeyCenter: @unchecked Sendable {
    static let shared = HotKeyCenter()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    @MainActor private var handlers: [UInt32: @MainActor () -> Void] = [:]

    private init() {}

    @MainActor
    func setHandler(id: UInt32, handler: @escaping @MainActor () -> Void) {
        handlers[id] = handler
    }

    @MainActor
    private func fire(id: UInt32) {
        handlers[id]?()
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        installEventHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: OSType(0x4C54_5348), id: id) // 'LTSH'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("Liteshot: RegisterEventHotKey(id: %u) failed (%d)", id, status)
            return false
        }
        if let existing = hotKeyRefs[id] {
            UnregisterEventHotKey(existing)
        }
        hotKeyRefs[id] = ref
        return true
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            // Carbon 事件回调在主线程；直接同步派发，避免闭包跨执行器。
            MainActor.assumeIsolated {
                center.fire(id: hotKeyID.id)
            }
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            NSLog("Liteshot: InstallEventHandler failed (%d)", status)
        }
    }
}
