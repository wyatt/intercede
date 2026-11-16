import XCTest
import Combine
import CoreGraphics
@testable import Intercede

@MainActor
final class UsageTrackerTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("IntercedeTests-\(UUID().uuidString)")
        suiteName = "IntercedeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeTracker(_ configs: [SiteConfig], now: Date = Date()) -> UsageTracker {
        let tracker = UsageTracker(store: UsageStore(directory: dir), defaults: defaults, now: now)
        tracker.siteConfigs = configs
        return tracker
    }

    func testBasicAccumulation() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)])
        tracker.record(host: "youtube.com", elapsed: 2)
        tracker.record(host: "youtube.com", elapsed: 2)
        XCTAssertEqual(tracker.seconds(for: "youtube.com"), 4.0, accuracy: 0.001)
    }

    func testWWWNormalization() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)])
        tracker.record(host: "www.youtube.com", elapsed: 2)
        XCTAssertEqual(tracker.seconds(for: "youtube.com"), 2.0, accuracy: 0.001)
    }

    func testSubdomainsShareTheSiteBudget() {
        let tracker = makeTracker([SiteConfig(host: "reddit.com", dailyBudgetSeconds: 3600)])
        tracker.record(host: "old.reddit.com", elapsed: 2)
        tracker.record(host: "reddit.com", elapsed: 3)
        XCTAssertEqual(tracker.seconds(for: "reddit.com"), 5.0, accuracy: 0.001)
        XCTAssertEqual(tracker.seconds(for: "old.reddit.com"), 5.0, accuracy: 0.001)
    }

    func testMostSpecificConfigWins() {
        let tracker = makeTracker([
            SiteConfig(host: "google.com", dailyBudgetSeconds: 3600),
            SiteConfig(host: "news.google.com", dailyBudgetSeconds: 60),
        ])
        tracker.record(host: "news.google.com", elapsed: 5)
        XCTAssertEqual(tracker.seconds(for: "news.google.com"), 5.0, accuracy: 0.001)
        XCTAssertEqual(tracker.seconds(for: "google.com"), 0.0)
    }

    func testLookalikeDomainNotMatched() {
        let tracker = makeTracker([SiteConfig(host: "x.com", dailyBudgetSeconds: 3600)])
        tracker.record(host: "box.com", elapsed: 2)
        XCTAssertEqual(tracker.seconds(for: "x.com"), 0.0)
    }

    func testUntrackedSiteIgnored() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)])
        tracker.record(host: "github.com", elapsed: 2)
        XCTAssertEqual(tracker.seconds(for: "github.com"), 0.0)
        XCTAssertTrue(tracker.todayUsage.seconds.isEmpty)
    }

    func testBudgetBreachFiresWithConfiguredHost() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 2)])
        var breached: [String] = []
        let c = tracker.budgetBreached.sink { breached.append($0) }
        tracker.record(host: "m.youtube.com", elapsed: 2)
        XCTAssertEqual(breached, ["youtube.com"])
        _ = c
    }

    func testBudgetBreachCooldown() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 2)])
        var count = 0
        let c = tracker.budgetBreached.sink { _ in count += 1 }
        let t0 = Date()
        tracker.record(host: "youtube.com", elapsed: 2, now: t0)
        tracker.record(host: "youtube.com", elapsed: 2, now: t0.addingTimeInterval(60))
        XCTAssertEqual(count, 1, "Should only breach once within cooldown window")
        tracker.record(host: "youtube.com", elapsed: 2, now: t0.addingTimeInterval(301))
        XCTAssertEqual(count, 2, "Should breach again after cooldown")
        _ = c
    }

    func testDayRolloverStartsFresh() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)], now: day1)
        tracker.record(host: "youtube.com", elapsed: 10, now: day1)
        tracker.record(host: "youtube.com", elapsed: 3, now: day2)
        XCTAssertEqual(tracker.todayUsage.date, DailyUsage.key(for: day2))
        XCTAssertEqual(tracker.seconds(for: "youtube.com"), 3.0, accuracy: 0.001)
        XCTAssertEqual(UsageStore(directory: dir).load(for: day1).seconds["youtube.com"], 10)
    }

    func testUsagePersistsAcrossInstances() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)])
        tracker.record(host: "youtube.com", elapsed: 7)
        let reloaded = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 3600)])
        XCTAssertEqual(reloaded.seconds(for: "youtube.com"), 7.0, accuracy: 0.001)
    }

    func testBudgetEditsPersist() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 900)])
        tracker.siteConfigs[0].dailyBudgetSeconds = 1200  // what the Settings stepper does
        let reloaded = UsageTracker(store: UsageStore(directory: dir), defaults: defaults)
        XCTAssertEqual(reloaded.siteConfigs, [SiteConfig(host: "youtube.com", dailyBudgetSeconds: 1200)])
    }

    func testAddSiteNormalizesAndRejectsDuplicates() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 900)])
        XCTAssertTrue(tracker.addSite("https://www.Twitch.tv/somestreamer"))
        XCTAssertEqual(tracker.siteConfigs.last?.host, "twitch.tv")
        XCTAssertFalse(tracker.addSite("twitch.tv"))
        XCTAssertFalse(tracker.addSite("www.youtube.com"))
        XCTAssertFalse(tracker.addSite("not a site"))
        XCTAssertFalse(tracker.addSite("localhost"))
    }

    func testRemoveSiteStopsTrackingAndPersists() {
        let tracker = makeTracker([SiteConfig(host: "youtube.com", dailyBudgetSeconds: 900),
                                   SiteConfig(host: "reddit.com", dailyBudgetSeconds: 900)])
        tracker.removeSite("www.YouTube.com")
        XCTAssertEqual(tracker.siteConfigs.map(\.host), ["reddit.com"])
        tracker.record(host: "youtube.com", elapsed: 5)
        XCTAssertEqual(tracker.seconds(for: "youtube.com"), 0.0)
        let reloaded = UsageTracker(store: UsageStore(directory: dir), defaults: defaults)
        XCTAssertEqual(reloaded.siteConfigs.map(\.host), ["reddit.com"])
    }

    func testDateKeyIsGregorianRegardlessOfLocale() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 UTC
        XCTAssertTrue(DailyUsage.key(for: date).hasPrefix("2023-11-1"))
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
        XCTAssertEqual(BrowserURLParser.host(from: "YouTube.com/watch"), "youtube.com")
        XCTAssertEqual(BrowserURLParser.host(from: "httpbin.org/get"), "httpbin.org")
        XCTAssertNil(BrowserURLParser.host(from: "not a url"))
        XCTAssertNil(BrowserURLParser.host(from: ""))
    }
}

final class SpriteSheetTests: XCTestCase {

    func testLoopingClipWraps() {
        let clip = SpriteClip(row: 0, frames: 6, fps: 10, loops: true)
        XCTAssertEqual(clip.frameIndex(elapsed: 0), 0)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.55), 5)
        XCTAssertEqual(clip.frameIndex(elapsed: 0.65), 0)
    }

    func testOneShotClipHoldsLastFrame() {
        let clip = SpriteClip(row: 0, frames: 4, fps: 8, loops: false)
        XCTAssertEqual(clip.frameIndex(elapsed: 10), 3)
        XCTAssertEqual(clip.frameIndex(elapsed: -1), 0)
    }

    func testEverySaintHasBundledArtInTheStandardLayout() throws {
        for patron in Patron.roster {
            let sheet = try XCTUnwrap(SpriteSheet.bundled(patron.sheetName), "\(patron.sheetName).png missing from app bundle or malformed")
            XCTAssertEqual(sheet.frameSize, CGSize(width: 176, height: 208), patron.name)
        }
    }

    func testEverySaintsFramesAreNotBlank() throws {
        // Every frame of every clip has a figure in it — guards against a wrong frame count pointing
        // at an empty cell, or background removal eating a figure.
        for patron in Patron.roster {
            let sheet = try XCTUnwrap(SpriteSheet.bundled(patron.sheetName))
            for animation in PatronAnimation.allCases {
                let clip = sheet.clip(animation)
                for i in 0..<clip.frames {
                    let frame = sheet.frame(animation, elapsed: (Double(i) + 0.5) / clip.fps)
                    XCTAssertGreaterThan(opaquePixelCount(frame), 1000, "\(patron.name) \(animation) frame \(i) is blank")
                }
            }
        }
    }

    func testRejectsClipOutsideGrid() {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        var clips = Dictionary(uniqueKeysWithValues: PatronAnimation.allCases.map { ($0, SpriteClip(row: 0, frames: 2, fps: 8, loops: true)) })
        XCTAssertNotNil(SpriteSheet(image: image, cols: 2, rows: 1, clips: clips))
        clips[.talk] = SpriteClip(row: 3, frames: 2, fps: 8, loops: true)
        XCTAssertNil(SpriteSheet(image: image, cols: 2, rows: 1, clips: clips))
    }

    private func opaquePixelCount(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 3, to: buf.count, by: 4).filter { buf[$0] > 128 }.count
    }
}

final class PatronTests: XCTestCase {
    func testRosterIsStAlphonsusPlusFiveCuratedPets() {
        XCTAssertEqual(Patron.roster.map(\.name), ["St. Alphonsus Liguori", "St. Isidore of Seville",
                                                "St. Clare of Assisi", "St. Benedict", "St. Thomas Aquinas"])
        XCTAssertEqual(Patron.stAlphonsus.catchphrase, "This is not Liguorian!")
        XCTAssertEqual(Set(Patron.roster.map(\.slug)).count, Patron.roster.count, "slugs must be unique")
    }

    func testEveryPetHasACatchphraseAndPhrases() {
        for patron in Patron.roster {
            XCTAssertFalse(patron.catchphrase.isEmpty, patron.name)
            XCTAssertGreaterThan(patron.phrases.count, 5, patron.name)
            for phrase in patron.phrases {
                XCTAssertLessThan(phrase.count, 120, "\(patron.name): too long for the bubble: \(phrase)")
            }
        }
    }

    func testPhraseWithoutHostNeverNamesASite() {
        for patron in Patron.roster {
            XCTAssertTrue(patron.phrases.contains { !$0.contains("%@") }, "\(patron.name) needs a site-free phrase")
            for _ in 0..<40 {
                XCTAssertFalse(patron.randomPhrase(host: nil).contains("%@"), patron.name)
            }
        }
    }

    func testPhrasesInterpolateHost() {
        for patron in Patron.roster {
            for _ in 0..<40 {
                XCTAssertFalse(patron.randomPhrase(host: "youtube.com").contains("%@"), patron.name)
            }
        }
    }
}

@MainActor
final class NudgeSceneTests: XCTestCase {
    func testHitAreaFollowsSpriteNotLayoutOrigin() {
        let scene = NudgeScene(message: "hi", sheet: SpriteSheet.liguori)
        // Starts offstage to the left: the window's bottom-left corner must not be clickable.
        XCTAssertEqual(scene.hitRects.count, 1)
        XCTAssertFalse(scene.hitRects.contains { $0.contains(CGPoint(x: 40, y: 40)) })
        XCTAssertEqual(scene.hitRects[0].maxX, -20, accuracy: 0.5)
        XCTAssertEqual(scene.hitRects[0].minY, scene.bottomInset)
    }

    func testSweepsThePageWithoutBeingTapped() async throws {
        let scene = NudgeScene(message: "hi", sheet: SpriteSheet.liguori)
        var phases: [PatronAnimation] = []
        scene.onPhase = { phases.append($0) }
        var finished = false
        scene.enter { finished = true }
        // walk 1.6 + idle 0.6 + alert ~0.7 + speak 1.5 + dismiss ~0.8 + settle ~0.6 ≈ 5.8s
        try await Task.sleep(for: .seconds(6.3))
        XCTAssertEqual(phases, [.walkIn, .idle, .alert, .talk, .dismiss, .settle, .idle])
        XCTAssertFalse(finished, "he waits for a tap (or auto-dismiss) after sweeping")
        scene.abort(reason: "test over")
    }

    func testNothingClickableOnceExiting() {
        let scene = NudgeScene(message: "hi", sheet: SpriteSheet.liguori)
        scene.exit()
        XCTAssertTrue(scene.hitRects.isEmpty)
    }
}

@MainActor
final class PatronLibraryTests: XCTestCase {
    func testBuiltInPetIsStAlphonsusWithCatchphrase() {
        let suite = "IntercedeTests-\(UUID().uuidString)"
        let library = PatronLibrary(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(library.selectedPatronSlug, Patron.stAlphonsus.slug)
        XCTAssertEqual(library.current.patron.catchphrase, "This is not Liguorian!")
        XCTAssertTrue(library.current.sheet === SpriteSheet.liguori)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testOnlyPetsWithBundledArtAreOffered() {
        let library = PatronLibrary(defaults: UserDefaults(suiteName: "IntercedeTests-\(UUID().uuidString)")!)
        XCTAssertEqual(library.availablePatrons.first?.slug, Patron.stAlphonsus.slug)
        for patron in library.availablePatrons {
            XCTAssertNotNil(SpriteSheet.bundled(patron.sheetName), patron.name)
        }
    }

    func testUnknownSavedPetFallsBackToStAlphonsus() {
        let suite = "IntercedeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("some-removed-petdex-patron", forKey: "selectedPatronSlug")
        let library = PatronLibrary(defaults: defaults)
        XCTAssertEqual(library.selectedPatronSlug, Patron.stAlphonsus.slug)
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
final class BrowserBridgeTests: XCTestCase {
    func testTakeLinesSplitsAndKeepsPartialRemainder() {
        var buffer = Data("{\"a\":1}\n\n{\"b\":2}\n{\"c\":".utf8)
        let lines = BrowserBridge.takeLines(from: &buffer)
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "{\"c\":")
    }

    func testInstallerRegistersOnlyInstalledBrowsersAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fp-hosts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support")
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Google/Chrome"), withIntermediateDirectories: true)
        let helper = root.appendingPathComponent("IntercedeBridge")
        FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])

        let first = NativeHostInstaller.install(helperURL: helper, appSupport: support)
        XCTAssertEqual(first.written, ["Google/Chrome"])
        let file = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts/com.intercede.bridge.json")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(json["path"] as? String, helper.path)
        XCTAssertEqual(json["allowed_origins"] as? [String], ["chrome-extension://bminoilbndphincaaooginfkcjamaadc/"])

        let second = NativeHostInstaller.install(helperURL: helper, appSupport: support)
        XCTAssertEqual(second, NativeHostInstaller.Result(written: [], unchanged: ["Google/Chrome"]))
    }

    func testSocketRoundTrip() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("fpb-\(UUID().uuidString.prefix(8)).sock").path
        let bridge = BrowserBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8); raw.copyBytes(from: bytes); raw[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
        XCTAssertTrue(connected)

        let hello = Data(#"{"v":1,"type":"hello","browser":"Google Chrome"}"#.utf8 + [0x0A])
        _ = hello.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(bridge.connectedBrowsers, ["Google Chrome"])

        bridge.send(["type": "hold", "nudgeId": "n1", "host": "youtube.com"])
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &chunk, chunk.count)
        let reply = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(chunk[0..<max(n, 0)].dropLast())) as? [String: Any])
        XCTAssertEqual(reply["type"] as? String, "hold")
        XCTAssertEqual(reply["v"] as? Int, 1)
        XCTAssertEqual(reply["host"] as? String, "youtube.com")
    }
}

@MainActor
final class LegacyMigrationTests: XCTestCase {
    func testCarriesOverSitesAndSelectionFromFocusPet() throws {
        let oldName = "IntercedeTests-old-\(UUID().uuidString)", newName = "IntercedeTests-new-\(UUID().uuidString)"
        let old = try XCTUnwrap(UserDefaults(suiteName: oldName)), new = try XCTUnwrap(UserDefaults(suiteName: newName))
        defer { old.removePersistentDomain(forName: oldName); new.removePersistentDomain(forName: newName) }
        old.set(Data("[]".utf8), forKey: "siteConfigs")
        old.set("bishop", forKey: "selectedPetSlug")

        LegacyMigration.migrateDefaults(from: old, to: new)
        XCTAssertEqual(new.data(forKey: "siteConfigs"), Data("[]".utf8))
        XCTAssertEqual(new.string(forKey: "selectedPatronSlug"), "liguori")

        // Never overwrites settings the new app already has.
        new.set("clare", forKey: "selectedPatronSlug")
        LegacyMigration.migrateDefaults(from: old, to: new)
        XCTAssertEqual(new.string(forKey: "selectedPatronSlug"), "clare")
    }

    func testMovesDataFolderOnlyIfNewOneIsAbsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("FocusPet"), new = root.appendingPathComponent("Intercede")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("usage-2026-11-16.json"))

        LegacyMigration.migrateDataFolder(from: old, to: new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("usage-2026-11-16.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))

        // A second run with both present leaves the new folder alone.
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        LegacyMigration.migrateDataFolder(from: old, to: new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }
}
