import SwiftUI
import AppKit

struct SpriteView: View {
    let image: NSImage?
    let frameSize: CGFloat
    private let fps: Double = 8

    @State private var frameIndex = 0
    @State private var animTimer: Timer?

    // Sprite sheet: horizontal strip, each frame is square (width == height per frame)
    var body: some View {
        ZStack {
            if let img = image {
                let frameCount = max(1, Int(img.size.width / img.size.height))
                let safeFrame = frameCount > 1 ? frameIndex % frameCount : 0
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: frameSize * CGFloat(frameCount), height: frameSize)
                    .offset(x: -frameSize * CGFloat(safeFrame))
            } else {
                Text("🐾")
                    .font(.system(size: frameSize * 0.7))
            }
        }
        .frame(width: frameSize, height: frameSize)
        .clipped()
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
    }

    private func startAnimation() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { _ in
            frameIndex += 1
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }
}
