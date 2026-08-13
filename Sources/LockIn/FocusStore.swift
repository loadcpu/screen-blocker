import Foundation

private struct FocusEntry: Codable {
    let date: String
    let duration: TimeInterval
    // when the session actually ran; optional so lines written before these
    // fields existed still decode
    let start: Date?
    let end: Date?
}

final class FocusStore {
    static let shared = FocusStore()
    private let queue = DispatchQueue(label: "FocusStore", qos: .utility)
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {}

    private var baseDir: URL {
        let dir = FileManager.lockinDir.appendingPathComponent("focus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func record(duration: TimeInterval, start: Date? = nil, end: Date? = nil) {
        guard duration > 0 else { return }
        let dateStr = fmt.string(from: Date())
        let entry = FocusEntry(date: dateStr, duration: duration, start: start, end: end)
        queue.async {
            guard let data = try? JSONEncoder().encode(entry),
                  let line = String(data: data, encoding: .utf8) else { return }
            let url = self.baseDir.appendingPathComponent("\(dateStr).jsonl")
            let text = line + "\n"
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(Data(text.utf8))
                try? fh.close()
            } else {
                try? text.write(to: url, atomically: false, encoding: .utf8)
            }
        }
    }

    func focusTimeToday() -> TimeInterval {
        read(for: Date())
    }

    func focusTotal(for date: Date) -> TimeInterval {
        read(for: date)
    }

    func focusTotal(forDays days: Int) -> TimeInterval {
        let cal = Calendar.current
        return (0..<days).reduce(0.0) { total, offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: Date()) else { return total }
            return total + read(for: d)
        }
    }

    func currentStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        var date = cal.startOfDay(for: Date())
        if read(for: date) == 0 {
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = prev
        }
        while read(for: date) > 0 {
            streak += 1
            guard streak < 366, let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    func longestStreak() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) else { return 0 }
        let cal = Calendar.current
        let dates: [Date] = files
            .compactMap { url -> Date? in
                let name = url.deletingPathExtension().lastPathComponent
                guard let d = fmt.date(from: name), read(for: d) > 0 else { return nil }
                return cal.startOfDay(for: d)
            }
            .sorted()
        guard !dates.isEmpty else { return 0 }
        var longest = 1, current = 1
        for i in 1..<dates.count {
            let diff = cal.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 0
            current = diff == 1 ? current + 1 : 1
            longest = max(longest, current)
        }
        return longest
    }

    func focusData(forLastDays days: Int) -> [Date: TimeInterval] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Date: TimeInterval] = [:]
        for i in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            result[d] = read(for: d)
        }
        return result
    }

    private func read(for date: Date) -> TimeInterval {
        let url = baseDir.appendingPathComponent("\(fmt.string(from: date)).jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return content.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> FocusEntry? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(FocusEntry.self, from: data)
            }
            .reduce(0) { $0 + $1.duration }
    }
}
