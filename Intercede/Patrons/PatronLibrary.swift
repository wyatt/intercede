import Foundation

// Manages the user's selected patron. Only patrons whose sprite sheet is bundled are offered; St. Alphonsus
// is the default and the fallback.
@MainActor
final class PatronLibrary: ObservableObject {
    @Published var selectedPatronSlug: String {
        didSet { defaults.set(selectedPatronSlug, forKey: "selectedPatronSlug") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "selectedPatronSlug")
        // A saved patron that's gone (e.g. a removed Petdex patron) falls back to St. Alphonsus.
        let available = Self.availablePatrons
        self.selectedPatronSlug = available.contains { $0.slug == saved } ? saved! : Patron.stAlphonsus.slug
    }

    static var availablePatrons: [Patron] { Patron.roster.filter { SpriteSheet.bundled($0.sheetName) != nil } }
    var availablePatrons: [Patron] { Self.availablePatrons }

    /// The patron that will appear, with its art.
    var current: (patron: Patron, sheet: SpriteSheet?) {
        let patron = availablePatrons.first { $0.slug == selectedPatronSlug } ?? Patron.stAlphonsus
        return (patron, SpriteSheet.bundled(patron.sheetName))
    }
}
