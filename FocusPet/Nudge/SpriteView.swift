import SwiftUI
import AppKit

struct SpriteView: View {
    let image: NSImage?
    let frameSize: CGFloat
    private let fps: Double = 8

    @State private var frameIndex = 0
    @State private var timer: Timer?

    // Expects a horizontal sprite sheet where each frame is square
    var body: some View {
        Canvas { ctx, size in
            guard let img = image else {
                // Draw fallback block character
                ctx.draw(Text("🐾").font(.system(size: frameSize * 0.8)), at: CGPoint(x: size.width/2, y: size.height/2))
                return
            }
            let frameCount = Int(img.size.width / img.size.height)
            let safeFrame = frameCount > 0 ? frameIndex % frameCount : 0
            let frameWidth = img.size.width / CGFloat(max(frameCount, 1))
            let srcRect = NSRect(
                x: CGFloat(safeFrame) * frameWidth,
                y: 0,
                width: frameWidth,
                height: img.size.height
            )
            let destRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let croppedCG = cgImg.cropping(to: CGRect(
                   x: srcRect.origin.x / img.size.width * CGFloat(cgImg.width),
                   y: 0,
                   width: srcRect.width / img.size.width * CGFloat(cgImg.width),
                   height: CGFloat(cgImg.height)
               )) {
                ctx.draw(Image(decorative: croppedCG, scale: 1.0), in: destRect)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .interpolation(.none)  // Crisp pixel art
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { _ in
            frameIndex += 1
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
