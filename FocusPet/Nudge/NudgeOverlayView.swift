import SwiftUI

struct NudgeOverlayView: View {
    let message: String
    let petImage: NSImage?
    let onDismiss: () -> Void

    @State private var offsetX: CGFloat = -200
    @State private var showBubble = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Speech bubble
            if showBubble {
                VStack(alignment: .leading, spacing: 0) {
                    SpeechBubble(text: message)
                        .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                    Spacer().frame(height: 8)
                }
                .offset(x: offsetX + 20, y: -80)
            }

            // Sprite
            SpriteView(image: petImage, frameSize: 64)
                .offset(x: offsetX, y: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                offsetX = 16
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.spring(response: 0.3)) {
                    showBubble = true
                }
            }
        }
        .onTapGesture {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.4)) {
            showBubble = false
            offsetX = -200
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onDismiss()
        }
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
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

            // Triangle pointer pointing down-left
            Triangle()
                .fill(Color.white)
                .frame(width: 12, height: 8)
                .overlay(Triangle().stroke(Color.black, lineWidth: 2))
                .offset(x: 16, y: -1)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
