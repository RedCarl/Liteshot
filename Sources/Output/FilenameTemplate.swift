import Foundation

enum FilenameTemplate {
    /// 支持的 token；按长度从长到短替换，避免 `{yy}` 命中 `{yyyy}` 的内部。
    nonisolated(unsafe) private static let replacements: [(token: String, value: (DateComponents, Date) -> String)] = [
        ("{yyyy}", { comps, _ in String(format: "%04d", comps.year ?? 0) }),
        ("{yy}", { comps, _ in String(format: "%02d", (comps.year ?? 0) % 100) }),
        ("{MM}", { comps, _ in String(format: "%02d", comps.month ?? 0) }),
        ("{dd}", { comps, _ in String(format: "%02d", comps.day ?? 0) }),
        ("{HH}", { comps, _ in String(format: "%02d", comps.hour ?? 0) }),
        ("{mm}", { comps, _ in String(format: "%02d", comps.minute ?? 0) }),
        ("{ss}", { comps, _ in String(format: "%02d", comps.second ?? 0) }),
        ("{SSS}", { comps, _ in String(format: "%03d", (comps.nanosecond ?? 0) / 1_000_000) }),
        ("{EEEE}", { _, date in String(format: "%@", weekday(date, template: "EEEE")) }),
        ("{EEE}", { _, date in String(format: "%@", weekday(date, template: "EEE")) }),
        ("{a}", { _, date in ampm(date) }),
        ("{rand}", { _, _ in randomLetters(count: 4) }),
        ("{seq}", { _, _ in String(SequenceCounter.next()) }),
    ]

    static func render(_ template: String, date: Date = Date()) -> String {
        var result = template
        let calendar = Calendar.current
        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday],
            from: date
        )
        for item in replacements {
            guard result.contains(item.token) else { continue }
            result = result.replacingOccurrences(of: item.token, with: item.value(comps, date))
        }
        return result
    }

    private static func weekday(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = template
        return formatter.string(from: date)
    }

    private static func ampm(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    private static func randomLetters(count: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return String((0..<count).compactMap { _ in letters.randomElement() })
    }
}

enum SequenceCounter {
    private static let key = "output.filenameSequence"

    static func next() -> Int {
        let defaults = UserDefaults.standard
        let value = defaults.integer(forKey: key) + 1
        defaults.set(value, forKey: key)
        return value
    }
}
