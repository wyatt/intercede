import SwiftUI
import AppKit

enum SpriteRow: Int {
    case idle = 0
    case runRight = 1
    case runLeft = 2
    case waving = 3
    case jumping = 4
    case failed = 5
    case waiting = 6
    case running = 7
    case review = 8

    var frameCount: Int {
        switch self {
        case .idle:     return 6
        case .runRight: return 8
        case .runLeft:  return 8
        case .waving:   return 4
        case .jumping:  return 5
        case .failed:   return 8
        case .waiting:  return 6
        case .running:  return 6
        case .review:   return 6
        }
    }
}

struct SpriteView: View {
    let image: NSImage?
    let displaySize: CGFloat
    var row: SpriteRow = .idle
    var cols: Int = PetEntry.cols
    var rows: Int = PetEntry.rows
    private let fps: Double = 8

    @State private var colIndex = 0
    @State private var animTimer: Timer?
    @State private var activeRow: SpriteRow = .idle

    var body: some View {
        ZStack {
            if let img = image {
                let frameW = img.size.width / CGFloat(cols)
                let frameH = img.size.height / CGFloat(rows)
                let scale = displaySize / frameW

                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: img.size.width * scale, height: img.size.height * scale)
                    .offset(
                        x: -CGFloat(colIndex) * frameW * scale,
                        y: -CGFloat(row.rawValue) * frameH * scale
                    )
                    .frame(width: displaySize, height: frameH * scale, alignment: .topLeading)
                    .clipped()
            } else {
                Text("🐾")
                    .font(.system(size: displaySize * 0.7))
                    .frame(width: displaySize, height: displaySize)
            }
        }
        .onAppear {
            activeRow = row
            startAnimation()
        }
        .onDisappear { stopAnimation() }
        .onChange(of: row) {
            activeRow = row
            colIndex = 0
            stopAnimation()
            startAnimation()
        }
    }

    private func startAnimation() {
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { _ in
            colIndex = (colIndex + 1) % activeRow.frameCount
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }
}
