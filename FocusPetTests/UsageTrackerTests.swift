import XCTest
@testable import FocusPet

final class UsageTrackerTests: XCTestCase {

    func testBasicAccumulation() {
        let tracker = UsageTracker()
        tracker.siteConfigs = [SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)]

        tracker.record(host: "youtube.com", at: Date())
        tracker.record(host: "youtube.com", at: Date())

        XCTAssertEqual(tracker.seconds(for: "youtube.com"), 4.0, accuracy: 0.1)
    }

    func testWWWNormalization() {
        let tracker = UsageTracker()
        tracker.siteConfigs = [SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)]

        tracker.record(host: "www.youtube.com", at: Date())
        XCTAssertEqual(tracker.seconds(for: "youtube.com"), 2.0, accuracy: 0.1)
    }

    func testSubdomainMatching() {
        let tracker = UsageTracker()
        tracker.siteConfigs = [SiteConfig(host: "reddit.com", dailyBudgetSeconds: 3600)]

        tracker.record(host: "old.reddit.com", at: Date())
        XCTAssertEqual(tracker.seconds(for: "reddit.com"), 2.0, accuracy: 0.1)
    }

    func testUntrackedSiteIgnored() {
        let tracker = UsageTracker()
        tracker.siteConfigs = [SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)]

        tracker.record(host: "github.com", at: Date())
        XCTAssertEqual(tracker.seconds(for: "github.com"), 0.0)
    }

    func testBudgetBreachFires() {
        let tracker = UsageTracker()
        tracker.siteConfigs = [SiteConfig(host: "youtube.com", dailyBudgetSeconds: 2)]

        var breachedHost: String?
        let cancellable = tracker.budgetBreached.sink { breachedHost = $0 }

        tracker.record(host: "youtube.com", at: Date())
        // 2s >= 2s budget

        XCTAssertEqual(breachedHost, "youtube.com")
        _ = cancellable
    }

    func testBudgetBreachCooldown() {
        let tracker = UsageTracker()
        tracker.siteConfigs = [SiteConfig(host: "youtube.com", dailyBudgetSeconds: 2)]

        var breachCount = 0
        let cancellable = tracker.budgetBreached.sink { _ in breachCount += 1 }

        tracker.record(host: "youtube.com", at: Date())
        tracker.record(host: "youtube.com", at: Date())
        tracker.record(host: "youtube.com", at: Date())

        XCTAssertEqual(breachCount, 1, "Should only breach once within cooldown window")
        _ = cancellable
    }
}

final class BrowserURLParserTests: XCTestCase {

    func testLooksLikeDomain() {
        XCTAssertTrue(BrowserURLParser.looksLikeDomain("youtube.com"))
        XCTAssertTrue(BrowserURLParser.looksLikeDomain("old.reddit.com"))
        XCTAssertTrue(BrowserURLParser.looksLikeDomain("x.com"))
        XCTAssertFalse(BrowserURLParser.looksLikeDomain("Watch Later - YouTube"))
        XCTAssertFalse(BrowserURLParser.looksLikeDomain(""))
        XCTAssertFalse(BrowserURLParser.looksLikeDomain("not a domain"))
    }

    func testHostExtractionFromURL() {
        XCTAssertEqual(BrowserURLParser.host(from: "https://www.youtube.com/watch?v=abc"), "youtube.com")
        XCTAssertEqual(BrowserURLParser.host(from: "https://reddit.com/r/swift"), "reddit.com")
        XCTAssertNil(BrowserURLParser.host(from: "not-a-url"))
    }

    func testSafariTitleParsing() {
        let host = BrowserURLParser.parseHostFromTitle("Watch Later - YouTube - youtube.com", browser: .safari)
        XCTAssertEqual(host, "youtube.com")
    }
}
