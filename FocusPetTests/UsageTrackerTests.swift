import XCTest
import Combine
import CoreGraphics
@testable import FocusPet

@MainActor
final class UsageTrackerTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusPetTests-\(UUID().uuidString)")
        suiteName = "FocusPetTests-\(UUID().uuidString)"
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

    func testBundledBishopLoadsWithAllAnimations() throws {
        let sheet = try XCTUnwrap(SpriteSheet.bishop, "bishop.png missing from app bundle or malformed")
        XCTAssertEqual(sheet.frameSize, CGSize(width: 176, height: 200))
        for animation in PetAnimation.allCases {
            let clip = sheet.clip(animation)
            for i in 0..<clip.frames {
                XCTAssertNotNil(sheet.frame(animation, elapsed: Double(i) / clip.fps))
            }
        }
    }

    func testBishopFramesAreNotBlank() throws {
        // Guards against a mis-specified frame count pointing at an empty grid cell.
        let sheet = try XCTUnwrap(SpriteSheet.bishop)
        for animation in PetAnimation.allCases {
            let clip = sheet.clip(animation)
            let last = sheet.frame(animation, elapsed: Double(clip.frames - 1) / clip.fps + 0.001)
            XCTAssertGreaterThan(opaquePixelCount(last), 1000, "\(animation) last frame is blank")
        }
    }

    func testRejectsClipOutsideGrid() {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        var clips = Dictionary(uniqueKeysWithValues: PetAnimation.allCases.map { ($0, SpriteClip(row: 0, frames: 2, fps: 8, loops: true)) })
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

final class PetTests: XCTestCase {
    func testRosterIsStAlphonsusPlusFiveCuratedPets() {
        XCTAssertEqual(Pet.roster.count, 6)
        XCTAssertEqual(Pet.roster.first?.name, "St. Alphonsus Liguori")
        XCTAssertEqual(Pet.stAlphonsus.catchphrase, "This is not Liguorian!")
        XCTAssertEqual(Set(Pet.roster.map(\.slug)).count, Pet.roster.count, "slugs must be unique")
    }

    func testEveryPetHasACatchphraseAndPhrases() {
        for pet in Pet.roster {
            XCTAssertFalse(pet.catchphrase.isEmpty, pet.name)
            XCTAssertGreaterThan(pet.phrases.count, 5, pet.name)
            for phrase in pet.phrases {
                XCTAssertLessThan(phrase.count, 120, "\(pet.name): too long for the bubble: \(phrase)")
            }
        }
    }

    func testPhrasesInterpolateHost() {
        for pet in Pet.roster {
            for _ in 0..<40 {
                XCTAssertFalse(pet.randomPhrase(host: "youtube.com").contains("%@"), pet.name)
            }
        }
    }
}

@MainActor
final class NudgeSceneTests: XCTestCase {
    func testHitAreaFollowsSpriteNotLayoutOrigin() {
        let scene = NudgeScene(message: "hi", sheet: SpriteSheet.bishop)
        // Starts offstage to the left: the window's bottom-left corner must not be clickable.
        XCTAssertEqual(scene.hitRects.count, 1)
        XCTAssertFalse(scene.hitRects.contains { $0.contains(CGPoint(x: 40, y: 40)) })
        XCTAssertEqual(scene.hitRects[0].maxX, -20, accuracy: 0.5)
        XCTAssertEqual(scene.hitRects[0].minY, scene.bottomInset)
    }

    func testNothingClickableOnceExiting() {
        let scene = NudgeScene(message: "hi", sheet: SpriteSheet.bishop)
        scene.exit()
        XCTAssertTrue(scene.hitRects.isEmpty)
    }
}

@MainActor
final class PetLibraryTests: XCTestCase {
    func testBuiltInPetIsStAlphonsusWithCatchphrase() {
        let suite = "FocusPetTests-\(UUID().uuidString)"
        let library = PetLibrary(petdexClient: PetdexClient(), defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(library.selectedPetSlug, Pet.stAlphonsus.slug)
        XCTAssertEqual(library.current.pet.catchphrase, "This is not Liguorian!")
        XCTAssertTrue(library.current.sheet === SpriteSheet.bishop)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testUnknownSavedPetFallsBackToStAlphonsus() {
        let suite = "FocusPetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("some-removed-petdex-pet", forKey: "selectedPetSlug")
        let library = PetLibrary(petdexClient: PetdexClient(), defaults: defaults)
        XCTAssertEqual(library.selectedPetSlug, Pet.stAlphonsus.slug)
        defaults.removePersistentDomain(forName: suite)
    }
}
