import Foundation

struct DailyUsage: Codable, Equatable {
    var date: String  // "YYYY-MM-DD"
    var seconds: [String: Double]  // configured host -> total seconds

    init(date: String) {
        self.date = date
        self.seconds = [:]
    }

    // Fixed Gregorian/POSIX so file names don't depend on the user's calendar or locale.
    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

final class UsageStore {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("FocusPet")
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func load(for date: Date) -> DailyUsage {
        let key = DailyUsage.key(for: date)
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
