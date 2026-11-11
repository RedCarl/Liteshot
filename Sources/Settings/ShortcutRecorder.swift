import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: HotkeyShortcut

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(shortcut: shortcut)
        view.onChange = { value in
            DispatchQueue.main.async {
                if shortcut != value {
                    shortcut = value
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        if nsView.shortcut != shortcut {
            nsView.shortcut = shortcut
        }
    }
}
