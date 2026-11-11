import AppKit

// 自检模式：直接采集一帧、写剪贴板并退出，用于验证 TCC 权限与采集链路。
if CommandLine.arguments.contains("--selftest") {
    Task {
        let code = await SelfTest.run()
        exit(code)
    }
    dispatchMain()
}

// 自检快捷键：显示/修饰键转换/键名。
if CommandLine.arguments.contains("--selftest-shortcut") {
    let code = MainActor.assumeIsolated { SelfTest.runShortcutTest() }
    exit(code)
}

// 自检取色：纯色图 → PixelSampler 取样。
if CommandLine.arguments.contains("--selftest-pixel") {
    let code = MainActor.assumeIsolated { SelfTest.runPixelSamplerTest() }
    exit(code)
}

// 自检截图历史：临时目录 → 记录/读取/裁剪/清空。
if CommandLine.arguments.contains("--selftest-history") {
    let code = MainActor.assumeIsolated { SelfTest.runHistoryTest() }
    exit(code)
}

// 自检 OCR / 二维码：生成文字与二维码图片 → Vision 识别。
if CommandLine.arguments.contains("--selftest-ocr") {
    let code = MainActor.assumeIsolated { SelfTest.runOCRTest() }
    exit(code)
}

// 自检全景拼接。
if CommandLine.arguments.contains("--selftest-panorama") {
    let code = MainActor.assumeIsolated { SelfTest.runPanoramaStitcher() }
    exit(code)
}

// 自检横向滚动拼接。
if CommandLine.arguments.contains("--selftest-scrollh") {
    let code = MainActor.assumeIsolated { SelfTest.runScrollStitcherHorizontal() }
    exit(code)
}

// 自检竖向滚动拼接：合成帧 → 拼接 → 输出 PNG。
if CommandLine.arguments.contains("--selftest-scroll") {
    let code = MainActor.assumeIsolated { SelfTest.runScrollStitcher() }
    exit(code)
}

// 自检文档模型：撤销/重做/图层顺序。
if CommandLine.arguments.contains("--selftest-document") {
    exit(SelfTest.runDocument())
}

// 自检标注渲染：采集 → 叠加所有工具 → 输出 PNG。
if CommandLine.arguments.contains("--selftest-editor") {
    Task {
        let code = await SelfTest.runEditorRender()
        exit(code)
    }
    dispatchMain()
}

// 自检保存链路：采集 → 命名模板 → 写文件。
if CommandLine.arguments.contains("--selftest-save") {
    Task {
        let code = await SelfTest.runSave()
        exit(code)
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--permission") || CommandLine.arguments.contains("--permission-file") {
    let text = """
    app: \(Bundle.main.bundleURL.path)
    bundle: \(Bundle.main.bundleIdentifier ?? "nil")
    preflight: \(ScreenPermission.isGranted)
    """
    print(text)
    if CommandLine.arguments.contains("--permission-file") {
        try? text.write(toFile: "/tmp/liteshot-permission.txt", atomically: true, encoding: .utf8)
    }
    exit(ScreenPermission.isGranted ? 0 : 2)
}

if CommandLine.arguments.contains("--print-lang") {
    print("bundle:", Bundle.main.bundleIdentifier ?? "nil")
    print("stored:", UserDefaults.standard.string(forKey: L10n.languageKey) ?? "nil")
    print("english:", L10n.isEnglish)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
