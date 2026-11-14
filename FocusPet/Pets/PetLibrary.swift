import Foundation
import Combine

// Manages the user's selected pet. St. Alphonsus is bundled and is the default, and he stands in
// whenever a Petdex pet's sprite isn't downloaded yet or can't be decoded, so a nudge always has art.
@MainActor
final class PetLibrary: ObservableObject {
    @Published var selectedPetSlug: String {
        didSet { defaults.set(selectedPetSlug, forKey: "selectedPetSlug") }
    }

    private let petdexClient: PetdexClient
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var petdexSheet: (slug: String, sheet: SpriteSheet)?

    init(petdexClient: PetdexClient, defaults: UserDefaults = .standard) {
        self.petdexClient = petdexClient
        self.defaults = defaults
        let saved = defaults.string(forKey: "selectedPetSlug")
        // Pets that are no longer in the roster fall back to St. Alphonsus.
        self.selectedPetSlug = Pet.roster.contains { $0.slug == saved } ? saved! : Pet.stAlphonsus.slug
        // A finished download changes which pet can appear.
        petdexClient.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var availablePets: [Pet] { Pet.roster }

    /// The pet that will actually appear right now, with its art.
    var current: (pet: Pet, sheet: SpriteSheet?) {
        let selected = Pet.roster.first { $0.slug == selectedPetSlug } ?? Pet.stAlphonsus
        guard case .petdex(let url) = selected.art else { return (selected, SpriteSheet.bishop) }
        if let cached = petdexSheet, cached.slug == selected.slug { return (selected, cached.sheet) }
        guard let image = petdexClient.spriteImage(slug: selected.slug, url: url),
              let sheet = SpriteSheet.petdex(image) else {
            return (Pet.stAlphonsus, SpriteSheet.bishop)
        }
        petdexSheet = (selected.slug, sheet)
        return (selected, sheet)
    }
}
