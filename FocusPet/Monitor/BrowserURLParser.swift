import Foundation
import ApplicationServices
import AppKit

enum Browser: String, CaseIterable {
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case arc = "company.thebrowser.Browser"
    case firefox = "org.mozilla.firefox"
    case brave = "com.brave.Browser"
    case edge = "com.microsoft.edgemac"

    var bundleID: String { rawValue }

    var displayName: String {
        appleScriptName ?? "Firefox"
    }

    var appleScriptName: String? {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave Browser"
        case .edge: return "Microsoft Edge"
        case .firefox: return nil  // no AppleScript support
        }
    }
}

enum BrowserURLParser {
    // AppleScript path: Automation permission keyed by bundle ID — survives binary updates.
    // AX path: Accessibility permission keyed by code signature — resets on rebuild.
    @MainActor
    static func extractHost(appPID: pid_t, browser: Browser) -> String? {
        if let url = appleScriptURL(for: browser) {
            return host(from: url)
        }
        if let url = axURL(appPID: appPID, browser: browser) {
            return host(from: url)
        }
        return nil
    }

    // MARK: - AppleScript (primary)

    @MainActor private static var compiledScripts: [Browser: NSAppleScript] = [:]

    @MainActor
    static func appleScriptURL(for browser: Browser) -> String? {
        guard let script = compiledScript(for: browser) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let urlString = result.stringValue, !urlString.isEmpty else { return nil }
        return urlString
    }

    // Compiled once per browser. The timeout keeps a hung browser from freezing the app's main
    // thread (the Apple Event default is two minutes).
    @MainActor
    private static func compiledScript(for browser: Browser) -> NSAppleScript? {
        if let cached = compiledScripts[browser] { return cached }
        guard let appName = browser.appleScriptName else { return nil }
        let tab = browser == .safari ? "current tab" : "active tab"
        let source = """
        with timeout of 2 seconds
            tell application "\(appName)" to if (count of windows) > 0 then get URL of \(tab) of front window
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        compiledScripts[browser] = script
        return script
    }

    // MARK: - AX tree walk (fallback when Automation not yet approved)

    static func axURL(appPID: pid_t, browser: Browser) -> String? {
        guard let window = frontWindow(appPID: appPID) else { return nil }
        return urlFromWindow(window, browser: browser)
    }

    static func frontWindow(appPID: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(appPID)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var ref: AnyObject?
            if AXUIElementCopyAttributeValue(axApp, attribute as CFString, &ref) == .success,
               let w = ref, CFGetTypeID(w) == AXUIElementGetTypeID() {
                return (w as! AXUIElement)
            }
        }
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
        return (ref as? [AXUIElement])?.first
    }

    private static func urlFromWindow(_ window: AXUIElement, browser: Browser) -> String? {
        switch browser {
        case .safari:
            var docRef: AnyObject?
            AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &docRef)
            if let url = docRef as? String, url.hasPrefix("http") { return url }
        default:
            break
        }
        return findAddressBar(in: window, depth: 0)
    }

    private static func findAddressBar(in element: AXUIElement, depth: Int) -> String? {
        guard depth <= 12 else { return nil }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        if role == kAXTextFieldRole as String || role == "AXComboBox" {
            var descRef: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            let desc = (descRef as? String ?? "").lowercased()
            if desc.contains("address") || desc.contains("location") ||
               (desc.contains("search") && desc.contains("enter")) {
                var valRef: AnyObject?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef)
                if let str = valRef as? String, !str.isEmpty { return str }
            }
        }

        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findAddressBar(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - Shared helpers

    /// Host for a URL or bare domain, lowercased with any leading "www." removed.
    static func host(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: full), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func looksLikeDomain(_ s: String) -> Bool {
        let pattern = #"^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z]{2,}){1,3}(/.*)?$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
