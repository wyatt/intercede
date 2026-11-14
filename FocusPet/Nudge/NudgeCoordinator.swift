import AppKit
import Combine

@MainActor
final class NudgeCoordinator {
    private let usageTracker: UsageTracker
    private let petLibrary: PetLibrary
    private let browserBridge: BrowserBridge
    private var cancellables = Set<AnyCancellable>()
    private var activeOverlay: SpriteOverlayWindow?
    // True from show until the pet has walked off, so breaches can't stack overlays.
    private var isPresenting = false

    init(usageTracker: UsageTracker, petLibrary: PetLibrary, browserBridge: BrowserBridge) {
        self.usageTracker = usageTracker
        self.petLibrary = petLibrary
        self.browserBridge = browserBridge

        usageTracker.budgetBreached
            .receive(on: RunLoop.main)
            .sink { [weak self] host in
                self?.handleBreach(host: host)
            }
            .store(in: &cancellables)
    }

    /// Always shows a fresh nudge, replacing any that's already up.
    func triggerTest() {
        activeOverlay?.abort(reason: "replaced by Test Nudge")
        handleBreach(host: nil)
    }

    /// `host` is the site over budget, or nil for a test nudge (which may target any page).
    private func handleBreach(host: String?) {
        guard !isPresenting else {
            Log.overlay.info("breach for \(host ?? "test", privacy: .public) ignored: nudge already presenting")
            return
        }
        guard let screen = Self.screenUnderMouse() else { return }
        isPresenting = true

        let (pet, sheet) = petLibrary.current
        let phrase = pet.randomPhrase(host: host)
        let window = SpriteOverlayWindow(
            headline: pet.catchphrase,
            message: phrase,
            sheet: sheet,
            screen: screen
        )

        // Keep the browser page in step with the pet: it holds when his hand rises and dissolves
        // on his sweep. If the nudge ends without a sweep, the hold is released.
        var nudge: [String: Any] = ["nudgeId": UUID().uuidString, "test": host == nil]
        if let host { nudge["host"] = host }
        var dissolved = false
        window.onPhase = { [weak self, weak window] phase in
            guard let self else { return }
            switch phase {
            case .alert:
                self.browserBridge.send(nudge.merging(["type": "hold"]) { $1 })
            case .dismiss:
                dissolved = true
                self.browserBridge.send(nudge.merging([
                    "type": "dissolve",
                    "durationMs": Int((window?.sweepDuration ?? 1.2) * 1000),
                    "petName": pet.name,
                    "catchphrase": pet.catchphrase,
                    "phrase": phrase,
                ]) { $1 })
            default:
                break
            }
        }

        activeOverlay = window
        window.show { [weak self] in
            if !dissolved { self?.browserBridge.send(nudge.merging(["type": "release"]) { $1 }) }
            self?.activeOverlay = nil
            self?.isPresenting = false
        }
    }

    /// The screen the user is looking at, which isn't necessarily `NSScreen.main` for an accessory app.
    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
