import AppKit
import ImageIO

/// The beats of a nudge, independent of how any particular sheet lays them out.
enum PetAnimation: CaseIterable {
    case walkIn    // walking onto the screen, facing right
    case idle      // standing, breathing
    case alert     // notices you; raises a hand (plays once)
    case talk      // holds the pose while the speech bubble is up
    case dismiss   // waves the distraction away (plays once)
    case settle    // returns to neutral (plays once)
    case walkOut   // walking off the screen, facing left
}

struct SpriteClip {
    let row: Int
    let frames: Int
    let fps: Double
    let loops: Bool

    var duration: TimeInterval { Double(frames) / fps }

    func frameIndex(elapsed: TimeInterval) -> Int {
        let n = max(Int(elapsed * fps), 0)
        return loops ? n % frames : min(n, frames - 1)
    }
}

/// A uniform grid sprite sheet with its frames pre-cropped.
final class SpriteSheet: @unchecked Sendable {  // immutable after init
    let frameSize: CGSize
    private let frames: [[CGImage]]
    private let clips: [PetAnimation: SpriteClip]

    init?(image: CGImage, cols: Int, rows: Int, clips: [PetAnimation: SpriteClip]) {
        let fw = image.width / cols, fh = image.height / rows
        guard fw > 0, fh > 0 else { return nil }
        var frames: [[CGImage]] = []
        for r in 0..<rows {
            var row: [CGImage] = []
            for c in 0..<cols {
                guard let f = image.cropping(to: CGRect(x: c * fw, y: r * fh, width: fw, height: fh)) else { return nil }
                row.append(f)
            }
            frames.append(row)
        }
        // A clip pointing outside the grid would crash at render time; reject the sheet instead.
        guard clips.values.allSatisfy({ $0.row < rows && $0.frames <= cols && $0.frames > 0 }),
              PetAnimation.allCases.allSatisfy({ clips[$0] != nil }) else { return nil }
        self.frameSize = CGSize(width: fw, height: fh)
        self.frames = frames
        self.clips = clips
    }

    func clip(_ animation: PetAnimation) -> SpriteClip { clips[animation]! }

    func frame(_ animation: PetAnimation, elapsed: TimeInterval) -> CGImage {
        let clip = clip(animation)
        return frames[clip.row][clip.frameIndex(elapsed: elapsed)]
    }
}

extension SpriteSheet {
    /// The FocusPet layout every companion uses: a 6×7 grid of 176×208 cells, one row per beat
    /// (walk in, idle, raise hand, speak, dismiss, lower hand, walk out), packed by tools/pack-sprite.swift.
    static func focusPet(_ image: CGImage) -> SpriteSheet? {
        SpriteSheet(image: image, cols: 6, rows: 7, clips: [
            .walkIn:  SpriteClip(row: 0, frames: 6, fps: 9, loops: true),
            .idle:    SpriteClip(row: 1, frames: 4, fps: 5, loops: true),
            .alert:   SpriteClip(row: 2, frames: 6, fps: 9, loops: false),
            .talk:    SpriteClip(row: 3, frames: 6, fps: 6, loops: true),
            .dismiss: SpriteClip(row: 4, frames: 6, fps: 9, loops: false),
            .settle:  SpriteClip(row: 5, frames: 4, fps: 7, loops: false),
            .walkOut: SpriteClip(row: 6, frames: 6, fps: 9, loops: true),
        ])
    }

    /// The bundled sheet named `name` (`<name>.png`), or nil if that art isn't in the app yet.
    static func bundled(_ name: String) -> SpriteSheet? { bundledSheets[name] }

    static var liguori: SpriteSheet? { bundled("liguori") }

    // Loaded once for every pet in the roster; pets without art are simply absent.
    private static let bundledSheets: [String: SpriteSheet] = {
        var sheets: [String: SpriteSheet] = [:]
        for name in Pet.roster.map(\.sheetName) {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let image = loadCGImage(url),
                  let sheet = focusPet(image) else { continue }
            sheets[name] = sheet
        }
        return sheets
    }()

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
