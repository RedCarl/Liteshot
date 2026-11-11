import AppKit

@MainActor
final class HistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let shared = HistoryWindowController()

    private let collectionView = NSCollectionView()
    private let countLabel = NSTextField(labelWithString: "")
    private var selectedItem: HistoryItem?
    private var copyButton: NSButton!
    private var openButton: NSButton!
    private var revealButton: NSButton!

    private var store: HistoryStore { HistoryStore.shared }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("截图历史", "Capture History")
        window.minSize = NSSize(width: 560, height: 380)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(countLabel)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 180, height: 150)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(HistoryItemView.self, forItemWithIdentifier: HistoryItemView.identifier)
        collectionView.backgroundColors = [.clear]
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)

        let scroll = NSScrollView()
        scroll.documentView = collectionView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        copyButton = NSButton(title: L10n.t("复制", "Copy"), target: self, action: #selector(copySelected))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command]
        copyButton.isEnabled = false

        openButton = NSButton(title: L10n.t("打开", "Open"), target: self, action: #selector(openSelected))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        openButton.isEnabled = false

        revealButton = NSButton(title: L10n.t("在 Finder 中显示", "Reveal in Finder"), target: self, action: #selector(revealSelected))
        revealButton.bezelStyle = .rounded
        revealButton.isEnabled = false

        let clearButton = NSButton(title: L10n.t("清空", "Clear"), target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded

        let closeButton = NSButton(title: L10n.t("关闭", "Close"), target: self, action: #selector(closePanel))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "w"
        closeButton.keyEquivalentModifierMask = [.command]

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [copyButton, openButton, revealButton, spacer, clearButton, closeButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            countLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10),

            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    func show() {
        store.reload()
        collectionView.reloadData()
        updateCount()
        clearSelection()

        if let window, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let size = window.frame.size
            window.setFrameOrigin(
                CGPoint(
                    x: screen.frame.midX - size.width / 2,
                    y: screen.frame.midY - size.height / 2
                )
            )
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func updateCount() {
        countLabel.stringValue = store.items.isEmpty
            ? L10n.t("还没有截图历史", "No captures yet")
            : L10n.t("最近", "Recent") + " \(store.items.count) " + L10n.t("张截图 · 保存在", "captures · saved in") + " \(store.directory.path)"
    }

    private func clearSelection() {
        selectedItem = nil
        copyButton.isEnabled = false
        openButton.isEnabled = false
        revealButton.isEnabled = false
    }

    // MARK: - Collection view

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        store.items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: HistoryItemView.identifier, for: indexPath)
        guard let view = item as? HistoryItemView else { return item }
        let entry = store.items[indexPath.item]
        view.configure(item: entry, thumbnail: store.thumbnail(for: entry))
        return view
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, store.items.indices.contains(indexPath.item) else {
            clearSelection()
            return
        }
        selectedItem = store.items[indexPath.item]
        let enabled = selectedItem != nil
        copyButton.isEnabled = enabled
        openButton.isEnabled = enabled
        revealButton.isEnabled = enabled
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        clearSelection()
    }

    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              store.items.indices.contains(indexPath.item) else { return }
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        selectedItem = store.items[indexPath.item]
        openSelected()
    }

    // MARK: - Actions

    @objc private func copySelected() {
        guard let selectedItem, let image = store.image(for: selectedItem) else { return }
        ClipboardService.copy(image: image)
        NSSound(named: "Glass")?.play()
    }

    @objc private func openSelected() {
        guard let selectedItem, let image = store.image(for: selectedItem) else { return }
        EditorWindowController.open(image: image)
    }

    @objc private func revealSelected() {
        guard let selectedItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedItem.url])
    }

    @objc private func clearAll() {
        guard !store.items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("清空截图历史？", "Clear capture history?")
        alert.informativeText = L10n.t("会删除", "This deletes") + " \(store.items.count) " + L10n.t("个历史文件，无法恢复。", "history files. This cannot be undone.")
        alert.addButton(withTitle: L10n.t("清空", "Clear"))
        alert.addButton(withTitle: L10n.t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.clear()
        collectionView.reloadData()
        updateCount()
        clearSelection()
    }

    @objc private func closePanel() {
        window?.performClose(nil)
    }
}

@MainActor
final class HistoryItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryItemView")

    private let thumbView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.borderColor = NSColor.controlAccentColor.cgColor

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(thumbView)

        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            thumbView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            thumbView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            thumbView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            thumbView.heightAnchor.constraint(equalToConstant: 108),

            label.topAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -6),
        ])

        view = container
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 2 : 0
        }
    }

    func configure(item: HistoryItem, thumbnail: NSImage?) {
        thumbView.image = thumbnail
        label.stringValue = "\(item.displayDate)  \(item.width)×\(item.height)"
    }
}
