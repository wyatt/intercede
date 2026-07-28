import Foundation
import AppKit

struct PetEntry: Codable, Identifiable, Hashable {
    var id: String { slug }
    var slug: String
    var name: String
    var spriteURL: String
}

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
        URLSession.shared.dataTask(with: catalogURL) { [weak self] data, _, error in
            guard let self, let data, error == nil else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }
            // Petdex API shape is unknown — attempt common patterns
            if let pets = Self.parsePets(from: data) {
                let catalogFile = self.cacheDir.appendingPathComponent("catalog.json")
                try? data.write(to: catalogFile, options: .atomic)
                DispatchQueue.main.async {
                    self.pets = pets
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    func spriteImage(for pet: PetEntry) -> NSImage? {
        let cached = cacheDir.appendingPathComponent("\(pet.slug).png")
        if let img = NSImage(contentsOf: cached) { return img }
        downloadSprite(for: pet)
        return nil
    }

    private func downloadSprite(for pet: PetEntry) {
        guard let url = URL(string: pet.spriteURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data else { return }
            let dest = self.cacheDir.appendingPathComponent("\(pet.slug).png")
            try? data.write(to: dest, options: .atomic)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }.resume()
    }

    private func loadCachedCatalog() {
        let catalogFile = cacheDir.appendingPathComponent("catalog.json")
        guard let data = try? Data(contentsOf: catalogFile),
              let pets = Self.parsePets(from: data) else { return }
        self.pets = pets
    }

    private static func parsePets(from data: Data) -> [PetEntry]? {
        // Try direct array decode
        if let pets = try? JSONDecoder().decode([PetEntry].self, from: data) { return pets }
        // Try wrapped {"pets": [...]}
        if let wrapped = try? JSONDecoder().decode([String: [PetEntry]].self, from: data),
           let pets = wrapped["pets"] ?? wrapped["data"] ?? wrapped["results"] { return pets }
        // Try array of raw dicts with flexible keys
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
