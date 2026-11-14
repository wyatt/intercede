import os

// View with: log stream --predicate 'subsystem == "com.focuspet.app"' --level debug
enum Log {
    static let overlay = Logger(subsystem: "com.focuspet.app", category: "overlay")
}
