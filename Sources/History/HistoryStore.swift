import AppKit
import ImageIO

struct HistoryItem: Identifiable {
    let url: URL
    let date: Date
    let width: Int
    let height: Int

    var id: String { url.lastPathComponent }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    let directory: URL
    private let indexURL: URL
    private let maxCount: Int
    private(set) var items: [HistoryItem] = []

    private struct IndexEntry: Codable {
        let file: String
        let date: Date
        let width: Int
        let height: Int
    }

    init(directory: URL? = nil, maxCount: Int = 50) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            self.directory = base
                .appendingPathComponent("Liteshot", isDirectory: true)
                .appendingPathComponent("History", isDirectory: true)
        }
        self.indexURL = self.directory.appendingPathComponent("index.json")
        self.maxCount = maxCount
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    func record(_ image: CGImage) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "shot-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).png"
        let url = directory.appendingPathComponent(name)

        guard let png = ImageEncoding.pngData(from: image) else { return }
        do {
            try png.write(to: url)
        } catch {
            return
        }

        let item = HistoryItem(
            url: url,
            date: Date(),
            width: image.width,
            height: image.height
        )
        items.insert(item, at: 0)
        trim()
        saveIndex()
    }

    func reload() {
        if let data = try? Data(contentsOf: indexURL),
           let entries = try? JSONDecoder().decode([IndexEntry].self, from: data) {
            items = entries.compactMap { entry in
                let url = directory.appendingPathComponent(entry.file)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return HistoryItem(url: url, date: entry.date, width: entry.width, height: entry.height)
            }
        } else {
            rebuildFromDisk()
        }
        items.sort { $0.date > $1.date }
    }

    func image(for item: HistoryItem) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func thumbnail(for item: HistoryItem, maxPixelSize: Int = 360) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func delete(_ item: HistoryItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
        saveIndex()
    }

    func clear() {
        items.forEach { try? FileManager.default.removeItem(at: $0.url) }
        items.removeAll()
        saveIndex()
    }

    private func trim() {
        while items.count > maxCount {
            let removed = items.removeLast()
            try? FileManager.default.removeItem(at: removed.url)
        }
    }

    private func saveIndex() {
        let entries = items.map {
            IndexEntry(file: $0.url.lastPathComponent, date: $0.date, width: $0.width, height: $0.height)
        }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexURL)
        }
    }

    private func rebuildFromDisk() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        items = urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .compactMap { url in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                    return nil
                }
                let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return HistoryItem(url: url, date: date, width: width, height: height)
            }
            .sorted { $0.date > $1.date }
    }
}
