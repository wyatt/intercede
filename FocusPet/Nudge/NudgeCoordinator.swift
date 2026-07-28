import AppKit
import Combine

@MainActor
final class NudgeCoordinator {
    private let usageTracker: UsageTracker
    private let speechService = SpeechBubbleService()
    private var petLibrary: PetLibrary?
    private var cancellables = Set<AnyCancellable>()
    private var activeOverlay: SpriteOverlayWindow?

    init(usageTracker: UsageTracker) {
        self.usageTracker = usageTracker
        let petdex = PetdexClient()
        self.petLibrary = PetLibrary(petdexClient: petdex)
        petdex.fetchCatalog()

        usageTracker.budgetBreached
            .receive(on: RunLoop.main)
            .sink { [weak self] host in
                self?.handleBreach(host: host)
            }
            .store(in: &cancellables)

        usageTracker.$todayUsage
            .sink { [weak self] usage in
                self?.checkPreFetch(usage: usage)
            }
            .store(in: &cancellables)
    }

    func triggerTest() {
        handleBreach(host: "test.nudge")
    }

    private func handleBreach(host: String) {
        guard activeOverlay == nil || !activeOverlay!.isVisible else { return }

        let budget = usageTracker.budget(for: host) ?? 0
        let used = usageTracker.seconds(for: host)
        let secondsOver = used - budget

        Task {
            let message = await speechService.nudgeMessage(host: host, secondsOver: secondsOver)
            let screen = NSScreen.main ?? NSScreen.screens.first!
            let window = SpriteOverlayWindow(
                message: message,
                petImage: petLibrary?.currentSpriteImage,
                screen: screen
            )
            activeOverlay = window
            window.show()
        }
    }

    private func checkPreFetch(usage: DailyUsage) {
        for config in usageTracker.siteConfigs {
            let used = usage.seconds[config.host] ?? 0
            let threshold = config.dailyBudgetSeconds * 0.8
            if used >= threshold && used < config.dailyBudgetSeconds {
                Task {
                    _ = await speechService.nudgeMessage(
                        host: config.host,
                        secondsOver: config.dailyBudgetSeconds - used
                    )
                }
            }
        }
    }
}
