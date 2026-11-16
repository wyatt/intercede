import Foundation

// Manages the user's selected pet. Only pets whose sprite sheet is bundled are offered; St. Alphonsus
// is the default and the fallback.
@MainActor
final class PetLibrary: ObservableObject {
    @Published var selectedPetSlug: String {
        didSet { defaults.set(selectedPetSlug, forKey: "selectedPetSlug") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "selectedPetSlug")
        // A saved pet that's gone (e.g. a removed Petdex pet) falls back to St. Alphonsus.
        let available = Self.availablePets
        self.selectedPetSlug = available.contains { $0.slug == saved } ? saved! : Pet.stAlphonsus.slug
    }

    static var availablePets: [Pet] { Pet.roster.filter { SpriteSheet.bundled($0.sheetName) != nil } }
    var availablePets: [Pet] { Self.availablePets }

    /// The pet that will appear, with its art.
    var current: (pet: Pet, sheet: SpriteSheet?) {
        let pet = availablePets.first { $0.slug == selectedPetSlug } ?? Pet.stAlphonsus
        return (pet, SpriteSheet.bundled(pet.sheetName))
    }
}
