import Foundation
import AppKit

struct PetEntry: Codable, Identifiable, Hashable {
    var id: String { slug }
    var slug: String
    var name: String
    var spriteURL: String
}

@MainActor
final class PetdexClient: ObservableObject {
    @Published var pets: [PetEntry] = []
    @Published var isLoading = false

    private let cacheDir: URL
    private let catalogURL = URL(string: "https://petdex.dev/api/pets")!

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("FocusPet/Sprites")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadCachedCatalog()
    }

    func fetchCatalog() {
        isLoading = true
        let url = catalogURL
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
        let cached = cacheDir.appendingPathComponent("\(pet.slug).png")
        if let img = NSImage(contentsOf: cached) { return img }
        downloadSprite(for: pet)
        return nil
    }

    private func downloadSprite(for pet: PetEntry) {
        guard let url = URL(string: pet.spriteURL) else { return }
        let dest = cacheDir.appendingPathComponent("\(pet.slug).png")
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
        if let pets = try? JSONDecoder().decode([PetEntry].self, from: data) { return pets }
        if let wrapped = try? JSONDecoder().decode([String: [PetEntry]].self, from: data),
           let pets = wrapped["pets"] ?? wrapped["data"] ?? wrapped["results"] { return pets }
        if let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return raw.compactMap { dict -> PetEntry? in
                guard let slug = dict["slug"] as? String ?? dict["id"] as? String,
                      let name = dict["name"] as? String,
                      let spriteURL = dict["spriteUrl"] as? String
                                   ?? dict["sprite_url"] as? String
                                   ?? dict["image"] as? String
                                   ?? dict["url"] as? String else { return nil }
                return PetEntry(slug: slug, name: name, spriteURL: spriteURL)
            }
        }
        return nil
    }
}
