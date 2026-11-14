import SwiftUI

/// Drives the nudge choreography: walk in → idle → raise hand → speak … dismiss → lower hand → walk out.
/// All steps run in one cancellable task, so dismissing mid-entrance cleanly switches to the exit.
@MainActor
final class NudgeScene: ObservableObject {
    @Published private(set) var animation: PetAnimation = .walkIn
    @Published private(set) var animationStart = Date()
    @Published private(set) var offsetX: CGFloat
    @Published private(set) var showBubble = false
    var bubbleSize: CGSize = .zero  // reported by the view; used for click-through hit testing

    let sheet: SpriteSheet?
    let headline: String?  // the pet's catchphrase, shown above the message
    let message: String
    let spriteHeight: CGFloat = 150
    let restX: CGFloat = 24
    let bottomInset: CGFloat = 8
    let bubbleGap: CGFloat = 4
    private let walkDuration: TimeInterval = 1.6
    private let autoDismissAfter: TimeInterval = 45

    private var script: Task<Void, Never>?
    private var isExiting = false
    private var onFinished: (() -> Void)?

    var spriteWidth: CGFloat { SpriteView(sheet: sheet, animation: .idle, height: spriteHeight).width }
    private var offstageX: CGFloat { -spriteWidth - 20 }

    init(headline: String? = nil, message: String, sheet: SpriteSheet?) {
        self.headline = headline
        self.message = message
        self.sheet = sheet
        self.offsetX = 0
        self.offsetX = offstageX
    }

    func enter(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        script = Task { [weak self] in
            guard let self else { return }
            play(.walkIn)
            withAnimation(.linear(duration: walkDuration)) { offsetX = restX }
            guard await pause(walkDuration) else { return }
            play(.idle)
            guard await pause(0.6) else { return }
            play(.alert)
            guard await pause(clipDuration(.alert)) else { return }
            play(.talk)
            withAnimation(.spring(response: 0.3)) { showBubble = true }
            guard await pause(autoDismissAfter) else { return }
            exit(reason: "auto-dismiss")
        }
    }

    func exit(reason: String = "tap") {
        guard !isExiting else { return }
        Log.overlay.info("exit requested: \(reason, privacy: .public) (during \(String(describing: self.animation), privacy: .public))")
        isExiting = true
        let handRaised = animation == .alert || animation == .talk
        script?.cancel()
        script = Task { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.2)) { showBubble = false }
            if handRaised {
                play(.dismiss)
                await pause(clipDuration(.dismiss) + 0.15)
                play(.settle)
                await pause(clipDuration(.settle))
            }
            play(.walkOut)
            withAnimation(.linear(duration: walkDuration)) { offsetX = offstageX }
            await pause(walkDuration)
            finish()
        }
    }

    /// Ends immediately without the exit choreography (e.g. the window was hidden out from under us).
    func abort(reason: String) {
        Log.overlay.info("abort: \(reason, privacy: .public)")
        isExiting = true
        script?.cancel()
        finish()
    }

    private func finish() {
        let done = onFinished
        onFinished = nil
        done?()
    }

    /// Clickable regions in window coordinates (origin bottom-left). Everything else passes clicks
    /// through to the app underneath. Empty once exiting, since there's nothing left to click.
    var hitRects: [CGRect] {
        guard !isExiting else { return [] }
        var rects = [CGRect(x: offsetX, y: bottomInset, width: spriteWidth, height: spriteHeight)]
        if showBubble {
            rects.append(CGRect(origin: bubbleOrigin, size: bubbleSize))
        }
        return rects
    }

    var bubbleOrigin: CGPoint {
        CGPoint(x: offsetX + spriteWidth * 0.45, y: bottomInset + spriteHeight + bubbleGap)
    }

    private func play(_ next: PetAnimation) {
        Log.overlay.debug("play \(String(describing: next), privacy: .public)")
        animation = next
        animationStart = Date()
    }

    private func clipDuration(_ a: PetAnimation) -> TimeInterval { sheet?.clip(a).duration ?? 0.5 }

    /// Returns false if the script was cancelled.
    @discardableResult
    private func pause(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

struct NudgeOverlayView: View {
    @ObservedObject var scene: NudgeScene

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Tap targets are attached before .offset so they move with what's drawn.
            if scene.showBubble {
                SpeechBubble(headline: scene.headline, text: scene.message)
                    .frame(maxWidth: 340, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { scene.bubbleSize = $0 }
                    .contentShape(Rectangle())
                    .onTapGesture { scene.exit() }
                    .offset(x: scene.bubbleOrigin.x, y: -(scene.spriteHeight + scene.bubbleGap))
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }

            SpriteView(sheet: scene.sheet, animation: scene.animation, startedAt: scene.animationStart, height: scene.spriteHeight)
                .contentShape(Rectangle())
                .onTapGesture { scene.exit() }
                .offset(x: scene.offsetX)
        }
        .padding(.bottom, scene.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

struct SpeechBubble: View {
    var headline: String? = nil
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let headline {
                Text(headline)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            Text(text)
                .font(.system(size: headline == nil ? 13 : 12, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 2)
    }
}
