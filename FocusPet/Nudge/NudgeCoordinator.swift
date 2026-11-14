import AppKit
import Combine

@MainActor
final class NudgeCoordinator {
    private let usageTracker: UsageTracker
    private let petLibrary: PetLibrary
    private var cancellables = Set<AnyCancellable>()
    private var activeOverlay: SpriteOverlayWindow?
    // True from show until the pet has walked off, so breaches can't stack overlays.
    private var isPresenting = false

    init(usageTracker: UsageTracker, petLibrary: PetLibrary) {
        self.usageTracker = usageTracker
        self.petLibrary = petLibrary

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
        handleBreach(host: "test.nudge")
    }

    private func handleBreach(host: String) {
        guard !isPresenting else {
            Log.overlay.info("breach for \(host, privacy: .public) ignored: nudge already presenting")
            return
        }
        guard let screen = Self.screenUnderMouse() else { return }
        isPresenting = true

        let (pet, sheet) = petLibrary.current
        let window = SpriteOverlayWindow(
            headline: pet.catchphrase,
            message: pet.randomPhrase(host: host),
            sheet: sheet,
            screen: screen
        )
        activeOverlay = window
        window.show { [weak self] in
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
