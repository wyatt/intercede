import Foundation
import AppKit

/// Downloads and caches Petdex sprite sheets for the pets in `Pet.roster`.
@MainActor
final class PetdexClient: ObservableObject {
    private let cacheDir: URL
    private var downloading: Set<String> = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("FocusPet/Sprites")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Returns the cached sheet, or nil and starts a download (at most one per pet).
    func spriteImage(slug: String, url: URL) -> CGImage? {
        for ext in ["webp", "png"] {
            let cached = cacheDir.appendingPathComponent("\(slug).\(ext)")
            if let img = SpriteSheet.loadCGImage(cached) { return img }
        }
        download(slug: slug, url: url)
        return nil
    }

    private func download(slug: String, url: URL) {
        guard !downloading.contains(slug) else { return }
        let ext = url.pathExtension.isEmpty ? "webp" : url.pathExtension.lowercased()
        let dest = cacheDir.appendingPathComponent("\(slug).\(ext)")
        downloading.insert(slug)
        Task {
            defer { downloading.remove(slug) }
            // Only cache bytes that decode as an image — never an HTML error page.
            guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20)),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  NSImage(data: data) != nil else { return }
            try? data.write(to: dest, options: .atomic)
            objectWillChange.send()
        }
    }
}
