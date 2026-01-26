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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

#Preview {
    MediaControlsView(isEnabled: true, onPlay: {}, onPause: {}, onForward: {}, onBackward: {})
}
