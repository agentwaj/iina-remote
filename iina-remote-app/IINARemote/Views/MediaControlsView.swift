import SwiftUI

struct MediaControlsView: View {
    let isEnabled: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onForward: () -> Void
    let onBackward: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Media Controls")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 30) {
                MediaButton(
                    icon: "backward.fill",
                    action: onBackward,
                    isEnabled: isEnabled
                )

                MediaButton(
                    icon: "pause.fill",
                    action: onPause,
                    isEnabled: isEnabled
                )

                MediaButton(
                    icon: "play.fill",
                    action: onPlay,
                    isEnabled: isEnabled
                )

                MediaButton(
                    icon: "forward.fill",
                    action: onForward,
                    isEnabled: isEnabled
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground).opacity(0.5))
        .cornerRadius(15)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

#Preview {
    VStack(spacing: 20) {
        MediaControlsView(isEnabled: true, onPlay: {}, onPause: {}, onForward: {}, onBackward: {})
        MediaControlsView(isEnabled: false, onPlay: {}, onPause: {}, onForward: {}, onBackward: {})
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.gray)
}
