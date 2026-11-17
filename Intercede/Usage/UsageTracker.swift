import Foundation
import Combine

struct SiteConfig: Codable, Identifiable, Equatable {
    var id: String { host }
    var host: String
    var dailyBudgetSeconds: Double  // seconds per day

    static let defaults: [SiteConfig] = [
        SiteConfig(host: "youtube.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "instagram.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "x.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "reddit.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "tiktok.com", dailyBudgetSeconds: 15 * 60),
        SiteConfig(host: "facebook.com", dailyBudgetSeconds: 15 * 60),
    ]
}

@MainActor
final class UsageTracker: ObservableObject {
    @Published var todayUsage: DailyUsage
    // Persisted on every change, including in-place edits from Settings bindings.
    @Published var siteConfigs: [SiteConfig] {
        didSet { saveSiteConfigs() }
    }

    private let store: UsageStore
    private let defaults: UserDefaults
    private let siteConfigsKey = "siteConfigs"
    private var breachCooldowns: [String: Date] = [:]
    private let breachCooldownInterval: TimeInterval = 5 * 60

    let budgetBreached = PassthroughSubject<String, Never>()

    init(store: UsageStore = UsageStore(), defaults: UserDefaults = .standard, now: Date = Date()) {
        self.store = store
        self.defaults = defaults
        todayUsage = store.load(for: now)

        if let data = defaults.data(forKey: siteConfigsKey),
           let configs = try? JSONDecoder().decode([SiteConfig].self, from: data) {
            siteConfigs = configs
        } else {
            siteConfigs = SiteConfig.defaults
        }
    }

    func record(host: String, elapsed: TimeInterval, now: Date = Date()) {
        let today = DailyUsage.key(for: now)
        if todayUsage.date != today {
            store.save(todayUsage)
            todayUsage = store.load(for: now)
            breachCooldowns = [:]
        }

        // Usage is keyed by the configured site, so old.reddit.com and reddit.com share one budget.
        guard elapsed > 0, let config = config(for: host) else { return }
        let key = Self.normalize(host: config.host)
        todayUsage.seconds[key, default: 0] += elapsed
        store.save(todayUsage)

        checkBudget(key: key, budget: config.dailyBudgetSeconds, now: now)
    }

    func seconds(for host: String) -> Double {
        let key = config(for: host).map { Self.normalize(host: $0.host) } ?? Self.normalize(host: host)
        return todayUsage.seconds[key] ?? 0
    }

    func budget(for host: String) -> Double? {
        config(for: host)?.dailyBudgetSeconds
    }

    /// Adds a site from user input (bare host or full URL). Returns false if invalid or duplicate.
    @discardableResult
    func addSite(_ input: String, budgetSeconds: Double = 15 * 60) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = BrowserURLParser.host(from: trimmed), host.contains("."),
              !siteConfigs.contains(where: { Self.normalize(host: $0.host) == host }) else { return false }
        siteConfigs.append(SiteConfig(host: host, dailyBudgetSeconds: budgetSeconds))
        return true
    }

    /// Stops tracking a site. Today's recorded time for it is kept in the usage history.
    func removeSite(_ host: String) {
        siteConfigs.removeAll { Self.normalize(host: $0.host) == Self.normalize(host: host) }
    }

    func saveSiteConfigs() {
        guard let data = try? JSONEncoder().encode(siteConfigs) else { return }
        defaults.set(data, forKey: siteConfigsKey)
    }

    private func checkBudget(key: String, budget: Double, now: Date) {
        let used = todayUsage.seconds[key] ?? 0
        guard used >= budget else { return }

        // Throttle: don't fire breach again within cooldown window
        if let lastBreach = breachCooldowns[key], now.timeIntervalSince(lastBreach) < breachCooldownInterval {
            return
        }
        breachCooldowns[key] = now
        budgetBreached.send(key)
    }

    /// The most specific configured site matching `host` (exact or parent domain).
    private func config(for host: String) -> SiteConfig? {
        let normalized = Self.normalize(host: host)
        return siteConfigs
            .filter {
                let configHost = Self.normalize(host: $0.host)
                return normalized == configHost || normalized.hasSuffix(".\(configHost)")
            }
            .max { $0.host.count < $1.host.count }
    }

    static func normalize(host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}
