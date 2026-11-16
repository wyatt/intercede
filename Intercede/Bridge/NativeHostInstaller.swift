import Foundation

/// Registers IntercedeBridge as a Native Messaging host with each installed Chromium browser, so the
/// Intercede extension can reach the app. Runs on every launch; rewrites a manifest only when its
/// contents change (e.g. the app moved).
enum NativeHostInstaller {
    static let hostName = "com.intercede.bridge"
    /// Registered by builds from when the app was called FocusPet; removed on sight.
    static let legacyHostName = "com.focuspet.bridge"
    /// Derived from the public `key` pinned in Extension/manifest.json.
    static let extensionID = "bminoilbndphincaaooginfkcjamaadc"

    /// Browser profile roots (relative to ~/Library/Application Support). A browser counts as
    /// installed when its root exists.
    static let browserRoots = [
        "Google/Chrome",
        "Google/Chrome Beta",
        "Google/Chrome Canary",
        "Chromium",
        "BraveSoftware/Brave-Browser",
        "Microsoft Edge",
        "Arc/User Data",  // unverified whether Arc honours this; harmless if not
    ]

    struct Result: Equatable {
        var written: [String] = []
        var unchanged: [String] = []
    }

    @discardableResult
    static func install(
        helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/IntercedeBridge"),
        appSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> Result {
        var result = Result()
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            Log.bridge.error("native host: helper missing at \(helperURL.path, privacy: .public)")
            return result
        }
        let manifest = manifestData(helperPath: helperURL.path)
        for root in browserRoots {
            let browserDir = appSupport.appendingPathComponent(root)
            guard FileManager.default.fileExists(atPath: browserDir.path) else { continue }
            let hostsDir = browserDir.appendingPathComponent("NativeMessagingHosts")
            let file = hostsDir.appendingPathComponent("\(hostName).json")
            try? FileManager.default.removeItem(at: hostsDir.appendingPathComponent("\(legacyHostName).json"))
            if (try? Data(contentsOf: file)) == manifest {
                result.unchanged.append(root)
                continue
            }
            do {
                try FileManager.default.createDirectory(at: hostsDir, withIntermediateDirectories: true)
                try manifest.write(to: file, options: .atomic)
                result.written.append(root)
                Log.bridge.info("native host: registered with \(root, privacy: .public)")
            } catch {
                Log.bridge.error("native host: failed for \(root, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }

    static func manifestData(helperPath: String) -> Data {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Intercede browser bridge",
            "path": helperPath,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        return try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
