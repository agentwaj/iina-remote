import SwiftUI

struct MediaButton: View {
    let icon: String
    let action: () -> Void
    let isEnabled: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title)
                .frame(width: 60, height: 60)
                .background(isEnabled ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
        .disabled(!isEnabled)
    }
}

#Preview {
    MediaButton(icon: "play.fill", action: {}, isEnabled: true)
    MediaButton(icon: "play.fill", action: {}, isEnabled: false)
}
