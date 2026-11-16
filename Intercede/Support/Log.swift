import os

// View with: log stream --predicate 'subsystem == "com.intercede.app"' --level debug
enum Log {
    static let overlay = Logger(subsystem: "com.intercede.app", category: "overlay")
    static let bridge = Logger(subsystem: "com.intercede.app", category: "bridge")
    static let monitor = Logger(subsystem: "com.intercede.app", category: "monitor")
}
