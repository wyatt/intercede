import Foundation

struct DailyUsage: Codable {
    var date: String  // "YYYY-MM-DD"
    var seconds: [String: Double]  // host -> total seconds

    init(date: String) {
        self.date = date
        self.seconds = [:]
    }
}

final class UsageStore {
    private let directory: URL
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("FocusPet")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(for date: Date) -> DailyUsage {
        let key = formatter.string(from: date)
        let file = directory.appendingPathComponent("usage-\(key).json")
        guard let data = try? Data(contentsOf: file),
              let usage = try? JSONDecoder().decode(DailyUsage.self, from: data) else {
            return DailyUsage(date: key)
        }
        return usage
    }

    func save(_ usage: DailyUsage) {
        let file = directory.appendingPathComponent("usage-\(usage.date).json")
        guard let data = try? JSONEncoder().encode(usage) else { return }
        try? data.write(to: file, options: .atomic)
    }

    func loadAll() -> [DailyUsage] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("usage-") }
            .compactMap { url -> DailyUsage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(DailyUsage.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }
}
