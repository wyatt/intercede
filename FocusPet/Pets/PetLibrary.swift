import Foundation
import AppKit

// Manages the user's selected pet and bundled fallback sprites
@MainActor
final class PetLibrary: ObservableObject {
    @Published var selectedPetSlug: String {
        didSet { UserDefaults.standard.set(selectedPetSlug, forKey: "selectedPetSlug") }
    }

    private let petdexClient: PetdexClient

    init(petdexClient: PetdexClient) {
        self.petdexClient = petdexClient
        self.selectedPetSlug = UserDefaults.standard.string(forKey: "selectedPetSlug") ?? "theveller"
    }

    var currentPet: PetEntry? {
        petdexClient.pets.first { $0.slug == selectedPetSlug }
            ?? petdexClient.pets.first
    }

    var currentSpriteImage: NSImage? {
        if let pet = currentPet {
            return petdexClient.spriteImage(for: pet)
        }
        return bundledFallback()
    }

    private func bundledFallback() -> NSImage? {
        // Returns a simple 16x16 pixel-art placeholder drawn programmatically
        let size = NSSize(width: 32, height: 32)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 8, y: 8, width: 16, height: 16).fill()
        NSColor.black.setFill()
        NSRect(x: 10, y: 18, width: 3, height: 3).fill()
        NSRect(x: 19, y: 18, width: 3, height: 3).fill()
        NSRect(x: 12, y: 12, width: 8, height: 2).fill()
        img.unlockFocus()
        return img
    }
}
