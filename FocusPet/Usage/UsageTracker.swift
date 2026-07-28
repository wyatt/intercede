import Foundation
import Combine

struct SiteConfig: Codable, Identifiable {
    var id: String { host }
    var host: String
    var dailyBudgetSeconds: Double  // seconds per day

    static let defaults: [SiteConfig] = [
        SiteConfig(host: "youtube.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "instagram.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "x.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "twitter.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "reddit.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "tiktok.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "facebook.com", dailyBudgetSeconds: 15 * 60),
    ]
}

@MainActor
final class UsageTracker: ObservableObject {
    @Published var todayUsage: DailyUsage
    @Published var siteConfigs: [SiteConfig]

    private let store = UsageStore()
    private let siteConfigsKey = "siteConfigs"
    private var breachCooldowns: [String: Date] = [:]
    private let breachCooldownInterval: TimeInterval = 5 * 60

    let budgetBreached = PassthroughSubject<String, Never>()

    init() {
        todayUsage = store.load(for: Date())

        if let data = UserDefaults.standard.data(forKey: siteConfigsKey),
           let configs = try? JSONDecoder().decode([SiteConfig].self, from: data) {
            siteConfigs = configs
        } else {
            siteConfigs = SiteConfig.defaults
        }
    }

    func record(host: String, elapsed: TimeInterval) {
        let today = todayDateKey()
        if todayUsage.date != today {
            store.save(todayUsage)
            todayUsage = store.load(for: Date())
        }

        guard siteConfigs.contains(where: { matches(host: host, config: $0) }) else { return }

        let normalizedHost = normalize(host: host)
        todayUsage.seconds[normalizedHost, default: 0] += elapsed
        store.save(todayUsage)

        checkBudget(host: normalizedHost)
    }

    func seconds(for host: String) -> Double {
        todayUsage.seconds[normalize(host: host)] ?? 0
    }

    func budget(for host: String) -> Double? {
        siteConfigs.first { matches(host: host, config: $0) }?.dailyBudgetSeconds
    }

    func saveSiteConfigs() {
        guard let data = try? JSONEncoder().encode(siteConfigs) else { return }
        UserDefaults.standard.set(data, forKey: siteConfigsKey)
    }

    private func checkBudget(host: String) {
        guard let config = siteConfigs.first(where: { matches(host: host, config: $0) }) else { return }
        let used = todayUsage.seconds[host] ?? 0
        guard used >= config.dailyBudgetSeconds else { return }

        // Throttle: don't fire breach again within cooldown window
        if let lastBreach = breachCooldowns[host], Date().timeIntervalSince(lastBreach) < breachCooldownInterval {
            return
        }
        breachCooldowns[host] = Date()
        budgetBreached.send(host)
    }

    private func normalize(host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    private func matches(host: String, config: SiteConfig) -> Bool {
        let normalized = normalize(host: host)
        let configHost = normalize(host: config.host)
        return normalized == configHost || normalized.hasSuffix(".\(configHost)")
    }

    private func todayDateKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
