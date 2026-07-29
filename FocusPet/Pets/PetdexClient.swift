import Foundation
import AppKit

struct PetEntry: Codable, Identifiable, Hashable {
    var id: String { slug }
    var slug: String
    var displayName: String
    var spritesheetUrl: String
    var petJsonUrl: String?

    // Sprite sheet constants (Petdex standard: 8 cols × 9 rows, 192×208 px per frame)
    static let cols = 8
    static let rows = 9
    static let frameWidth: CGFloat = 192
    static let frameHeight: CGFloat = 208
}

@MainActor
final class PetdexClient: ObservableObject {
    @Published var pets: [PetEntry] = []
    @Published var isLoading = false

    private let cacheDir: URL
    // Real manifest — redirects to assets.petdex.dev/manifests/petdex-v1.json
    private let manifestURL = URL(string: "https://assets.petdex.dev/manifests/petdex-v1.json")!

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("FocusPet/Sprites")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadCachedCatalog()
    }

    func fetchCatalog() {
        isLoading = true
        let url = manifestURL
        let dir = cacheDir
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let fetched = Self.parsePets(from: data) {
                    let catalogFile = dir.appendingPathComponent("catalog.json")
                    try? data.write(to: catalogFile, options: .atomic)
                    pets = fetched
                }
            } catch {}
            isLoading = false
        }
    }

    func spriteImage(for pet: PetEntry) -> NSImage? {
        let cached = cacheDir.appendingPathComponent("\(pet.slug).webp")
        if let img = NSImage(contentsOf: cached) { return img }
        // Also try .png for legacy cached files
        let cachedPNG = cacheDir.appendingPathComponent("\(pet.slug).png")
        if let img = NSImage(contentsOf: cachedPNG) { return img }
        downloadSprite(for: pet)
        return nil
    }

    private func downloadSprite(for pet: PetEntry) {
        guard let url = URL(string: pet.spritesheetUrl) else { return }
        let ext = url.pathExtension.isEmpty ? "webp" : url.pathExtension
        let dest = cacheDir.appendingPathComponent("\(pet.slug).\(ext)")
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            try? data.write(to: dest, options: .atomic)
            objectWillChange.send()
        }
    }

    private func loadCachedCatalog() {
        let catalogFile = cacheDir.appendingPathComponent("catalog.json")
        guard let data = try? Data(contentsOf: catalogFile),
              let loaded = Self.parsePets(from: data) else { return }
        pets = loaded
    }

    private static func parsePets(from data: Data) -> [PetEntry]? {
        // Manifest wraps entries under "pets" key
        struct Manifest: Codable { var pets: [PetEntry] }
        if let manifest = try? JSONDecoder().decode(Manifest.self, from: data) { return manifest.pets }
        // Direct array fallback
        if let pets = try? JSONDecoder().decode([PetEntry].self, from: data) { return pets }
        return nil
    }
}
