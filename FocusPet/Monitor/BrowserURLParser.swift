import Foundation

enum Browser: String, CaseIterable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case arc = "company.thebrowser.Browser"
    case firefox = "org.mozilla.firefox"
    case brave = "com.brave.Browser"
    case edge = "com.microsoft.edgemac"

    var bundleID: String { rawValue }
}

struct BrowserURLParser {
    // Safari exposes "Page Title — example.com" or just the URL in some configs.
    // Chrome/Arc expose page title only in window title.
    // We check title for bare domain patterns first, then heuristic known-site matching.
    static func extractHost(from windowTitle: String, browser: Browser) -> String? {
        // Try AppleScript-based URL extraction first (most reliable)
        if let url = appleScriptURL(for: browser) {
            return host(from: url)
        }
        // Fallback: parse title
        return parseHostFromTitle(windowTitle, browser: browser)
    }

    // AppleScript URL fetch — synchronous, ~5ms, acceptable for 2s poll interval
    static func appleScriptURL(for browser: Browser) -> String? {
        let script: String
        switch browser {
        case .safari:
            script = #"tell application "Safari" to if (count of windows) > 0 then get URL of current tab of front window"#
        case .chrome:
            script = #"tell application "Google Chrome" to if (count of windows) > 0 then get URL of active tab of front window"#
        case .arc:
            script = #"tell application "Arc" to if (count of windows) > 0 then get URL of active tab of front window"#
        case .brave:
            script = #"tell application "Brave Browser" to if (count of windows) > 0 then get URL of active tab of front window"#
        case .edge:
            script = #"tell application "Microsoft Edge" to if (count of windows) > 0 then get URL of active tab of front window"#
        case .firefox:
            // Firefox doesn't support AppleScript tab URL — fallback to title parsing
            return nil
        }

        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let urlString = result?.stringValue else { return nil }
        return urlString
    }

    static func parseHostFromTitle(_ title: String, browser: Browser) -> String? {
        // Safari often shows "Page Title - example.com" pattern
        if browser == .safari {
            let parts = title.components(separatedBy: " - ")
            if let last = parts.last, looksLikeDomain(last.trimmingCharacters(in: .whitespaces)) {
                return last.trimmingCharacters(in: .whitespaces)
            }
        }

        // Try to find a bare domain anywhere in title
        let words = title.components(separatedBy: .whitespaces)
        for word in words {
            if looksLikeDomain(word) { return word }
        }
        return nil
    }

    static func looksLikeDomain(_ s: String) -> Bool {
        let pattern = #"^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z]{2,}){1,3}$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func host(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        // Strip www. prefix for consistent matching
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
