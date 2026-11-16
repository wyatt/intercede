import SwiftUI
import AppKit

/// Plays one clip of a sprite sheet. Frame selection is derived from the clock (no timers to leak),
/// so the parent restarts a clip by passing a new `startedAt`.
struct SpriteView: View {
    let sheet: SpriteSheet?
    let animation: PatronAnimation
    var startedAt: Date = .distantPast
    let height: CGFloat

    var width: CGFloat {
        guard let sheet else { return height }
        return height * sheet.frameSize.width / sheet.frameSize.height
    }

    var body: some View {
        if let sheet {
            let clip = sheet.clip(animation)
            TimelineView(.periodic(from: startedAt, by: 1.0 / clip.fps)) { context in
                Image(decorative: sheet.frame(animation, elapsed: context.date.timeIntervalSince(startedAt)), scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            }
        } else {
            Text("🐾")
                .font(.system(size: height * 0.6))
                .frame(width: width, height: height)
        }
    }
}
