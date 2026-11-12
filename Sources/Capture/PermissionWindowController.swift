import AppKit
import SwiftUI

@MainActor
final class PermissionModel: ObservableObject {
    @Published var granted: Bool = ScreenPermission.isGranted

    var requestPermission: () -> Void = {}
    var openSettings: () -> Void = {}
    var close: () -> Void = {}
    var startCapture: () -> Void = {}

    func refresh() {
        granted = ScreenPermission.isGranted
    }
}

struct PermissionView: View {
    @ObservedObject var model: PermissionModel
    @State private var showHelp = false
    @AppStorage("settings.permissionSuppressOnLaunch") private var suppressOnLaunch = false

    private var title: String {
        model.granted
            ? L10n.t("屏幕录制权限已开启", "Screen Recording Enabled")
            : L10n.t("需要屏幕录制权限", "Screen Recording Permission Required")
    }

    private var subtitle: String {
        L10n.t(
            "开始截图  OCR  滚动截图  贴图  标注...",
            "Capture  OCR  Scrolling  Pin  Annotate..."
        )
    }

    private var actionTitle: String {
        model.granted
            ? L10n.t("开始截图", "Start Capture")
            : L10n.t("授权屏幕截图", "Authorize Screen Recording")
    }

    private var helpText: String {
        L10n.t(
            "Liteshot 需要屏幕录制权限才能截图。点击“授权屏幕截图”只会弹出 macOS 权限对话框，不会同时打开系统设置。\n\n如果之前拒绝过，系统不再弹框，点左下角“打开系统设置”手动勾选 Liteshot 即可。",
            "Liteshot needs screen recording permission to capture the screen. Clicking “Authorize Screen Recording” only shows the macOS permission dialog; it does not open System Settings at the same time.\n\nIf you denied it before and macOS no longer shows the dialog, use “Open System Settings” at the bottom left and enable Liteshot there."
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text(title)
                    .font(.system(size: 24, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(action: {
                        if model.granted {
                            model.startCapture()
                        } else {
                            model.requestPermission()
                        }
                    }) {
                        Text(actionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 210)
                            .padding(.vertical, 8)
                            .background(model.granted ? Color.green : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)

                    Button(action: { showHelp.toggle() }) {
                        Image(systemName: "questionmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.gray.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                        Text(helpText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .frame(width: 380)
                    }

                    if model.granted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            HStack {
                Button(L10n.t("了解更多", "Learn More")) {
                    if let url = URL(string: "https://github.com/RedCarl/Liteshot") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))

                Button(L10n.t("打开系统设置", "Open System Settings")) {
                    model.openSettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))

                Spacer()

                Toggle(L10n.t("授权后下次启动不显示", "Don't show again after authorizing"), isOn: $suppressOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 620, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.refresh()
        }
    }
}

@MainActor
final class PermissionWindowController: NSWindowController {
    static let shared = PermissionWindowController()

    private let model = PermissionModel()
    private var revealTask: Task<Void, Never>?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("屏幕录制权限", "Screen Recording Permission")
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)

        let hosting = NSHostingController(rootView: PermissionView(model: model))
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 620, height: 520))

        model.requestPermission = { [weak self] in
            // 先把自定义引导窗口收起来，让系统授权框到最前面；
            // 之前引导窗口是 floating，会把系统弹窗挡在后面。
            self?.window?.orderOut(nil)
            _ = ScreenPermission.request()
            self?.revealGuideWhenGranted()
        }
        model.openSettings = { [weak self] in
            // 打开系统设置时也先收起引导窗口，避免挡住设置页。
            self?.window?.orderOut(nil)
            ScreenPermission.openSystemSettings()
            self?.revealGuideWhenGranted()
        }
        model.close = { [weak self] in
            self?.window?.close()
        }
        model.startCapture = { [weak self] in
            self?.window?.close()
            CaptureCoordinator.shared.begin(.adaptive)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func revealGuideWhenGranted() {
        revealTask?.cancel()
        revealTask = Task { @MainActor [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if ScreenPermission.isGranted {
                    guard let self else { return }
                    self.model.refresh()
                    NSApp.activate(ignoringOtherApps: true)
                    self.window?.makeKeyAndOrderFront(nil)
                    return
                }
            }
        }
    }

    func show() {
        model.refresh()

        if let window {
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
            if let screen {
                window.setFrameOrigin(CGPoint(
                    x: screen.frame.midX - window.frame.width / 2,
                    y: screen.frame.midY - window.frame.height / 2
                ))
            }
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
