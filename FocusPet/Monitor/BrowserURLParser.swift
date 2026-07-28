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

struct BrowserURLParser {
    // AppleScript path: Automation permission keyed by bundle ID — survives binary updates.
    // AX path: Accessibility permission keyed by code signature — resets on rebuild.
    static func extractHost(appPID: pid_t, browser: Browser) -> String? {
        if let url = appleScriptURL(for: browser) {
            return host(from: url)
        }
        if let url = axURL(appPID: appPID, browser: browser) {
            return host(from: url.hasPrefix("http") ? url : "https://\(url)")
        }
        return nil
    }

    // MARK: - AppleScript (primary)

    static func appleScriptURL(for browser: Browser) -> String? {
        guard let appName = browser.appleScriptName else { return nil }
        let script: String
        switch browser {
        case .safari:
            script = "tell application \"\(appName)\" to if (count of windows) > 0 then get URL of current tab of front window"
        default:
            script = "tell application \"\(appName)\" to if (count of windows) > 0 then get URL of active tab of front window"
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let urlString = result?.stringValue, !urlString.isEmpty else { return nil }
        return urlString
    }

    // MARK: - AX tree walk (fallback when Automation not yet approved)

    static func axURL(appPID: pid_t, browser: Browser) -> String? {
        guard let window = frontWindow(appPID: appPID) else { return nil }
        return urlFromWindow(window, browser: browser)
    }

    static func frontWindow(appPID: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(appPID)
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref)
        if let w = ref { return (w as! AXUIElement) }
        AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &ref)
        if let w = ref { return (w as! AXUIElement) }
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
        if let windows = ref as? [AXUIElement], let first = windows.first { return first }
        return nil
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

    static func host(from urlString: String) -> String? {
        let full = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let url = URL(string: full), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func looksLikeDomain(_ s: String) -> Bool {
        let pattern = #"^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z]{2,}){1,3}(/.*)?$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Diagnostics

    static func rawAddressBarValue(appPID: pid_t) -> String? {
        guard let window = frontWindow(appPID: appPID) else { return "no-window" }
        return findAddressBar(in: window, depth: 0)
    }

    static func dumpAXTree(appPID: pid_t) -> String {
        guard let window = frontWindow(appPID: appPID) else { return "no window found (pid \(appPID))" }
        var lines: [String] = []
        dumpElement(window, depth: 0, maxDepth: 8, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private static func dumpElement(_ el: AXUIElement, depth: Int, maxDepth: Int, lines: inout [String]) {
        guard depth <= maxDepth else { return }
        let indent = String(repeating: "  ", count: depth)
        var roleRef: AnyObject?; AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        var valRef: AnyObject?; AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valRef)
        var descRef: AnyObject?; AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
        let role = (roleRef as? String) ?? "?"
        let val = (valRef as? String).map { v in v.count > 60 ? String(v.prefix(60)) + "…" : v } ?? ""
        let desc = (descRef as? String) ?? ""
        lines.append("\(indent)[\(role)] desc=\(desc) val=\(val)")
        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return }
        for child in children { dumpElement(child, depth: depth + 1, maxDepth: maxDepth, lines: &lines) }
    }
}
