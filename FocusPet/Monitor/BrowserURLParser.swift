import Foundation
import ApplicationServices

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
    // Primary: read URL from browser's accessibility tree (uses Accessibility permission only)
    static func extractHost(appPID: pid_t, browser: Browser) -> String? {
        let axApp = AXUIElementCreateApplication(appPID)

        var windowRef: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard let window = windowRef as! AXUIElement? else { return nil }

        if let urlString = urlFromWindow(window, browser: browser),
           let host = host(from: urlString.hasPrefix("http") ? urlString : "https://\(urlString)") {
            return host
        }
        return nil
    }

    private static func urlFromWindow(_ window: AXUIElement, browser: Browser) -> String? {
        switch browser {
        case .safari:
            // Safari exposes AXDocument = current URL on the window
            var docRef: AnyObject?
            AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &docRef)
            if let url = docRef as? String, url.hasPrefix("http") { return url }

        case .chrome, .arc, .brave, .edge:
            // Chrome-family: address bar is an AXTextField in the toolbar (depth ≤ 6)
            if let url = findURLTextField(in: window, depth: 0, maxDepth: 6) { return url }

        case .firefox:
            // Firefox address bar accessible via AXTextField search
            if let url = findURLTextField(in: window, depth: 0, maxDepth: 6) { return url }
        }
        return nil
    }

    // Walk the AX tree looking for a text field whose value looks like a URL or domain
    private static func findURLTextField(in element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth <= maxDepth else { return nil }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)

        if (roleRef as? String) == kAXTextFieldRole as String {
            var valRef: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef)
            if let str = valRef as? String, looksLikeURL(str) { return str }
        }

        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findURLTextField(in: child, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    static func looksLikeURL(_ s: String) -> Bool {
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return true }
        return looksLikeDomain(s)
    }

    static func looksLikeDomain(_ s: String) -> Bool {
        let pattern = #"^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z]{2,}){1,3}(/.*)?$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func host(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
