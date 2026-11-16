import Foundation

/// One-time carry-over from when the app was called FocusPet (bundle ID com.focuspet.app). Runs at
/// launch before anything reads settings or usage data; each step is a no-op once done.
enum LegacyMigration {
    static let oldBundleID = "com.focuspet.app"

    static func run() {
        if let old = UserDefaults(suiteName: oldBundleID) {
            migrateDefaults(from: old, to: .standard)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        migrateDataFolder(from: appSupport.appendingPathComponent("FocusPet"),
                          to: appSupport.appendingPathComponent("Intercede"))
    }

    /// Copies tracked sites/budgets and the selected patron, unless the new app already has its own.
    static func migrateDefaults(from old: UserDefaults, to new: UserDefaults) {
        if new.object(forKey: "siteConfigs") == nil, let sites = old.data(forKey: "siteConfigs") {
            new.set(sites, forKey: "siteConfigs")
            Log.overlay.info("migration: copied tracked sites from FocusPet")
        }
        if new.object(forKey: "selectedPatronSlug") == nil, let slug = old.string(forKey: "selectedPetSlug") {
            new.set(slug == "bishop" ? "liguori" : slug, forKey: "selectedPatronSlug")
        }
    }

    /// Moves the usage history folder over, if the new one doesn't exist yet.
    static func migrateDataFolder(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            Log.overlay.info("migration: moved data folder to \(new.path, privacy: .public)")
        } catch {
            Log.overlay.error("migration: couldn't move data folder: \(error.localizedDescription, privacy: .public)")
        }
    }
}
