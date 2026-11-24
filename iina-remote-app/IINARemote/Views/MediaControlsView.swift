import SwiftUI

struct MediaControlsView: View {
    let isEnabled: Bool
    let subtitleTracks: [SubtitleTrack]
    let currentSubtitleId: Int
    let onPlay: () -> Void
    let onPause: () -> Void
    let onForward: () -> Void
    let onBackward: () -> Void
    let onSelectSubtitle: (Int) -> Void
    let onSubtitleSmaller: () -> Void
    let onSubtitleLarger: () -> Void

    private var hasSubtitles: Bool { isEnabled && !subtitleTracks.isEmpty }

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

            SubtitlePicker(
                tracks: subtitleTracks,
                currentId: currentSubtitleId,
                isEnabled: isEnabled,
                onSelect: onSelectSubtitle
            )

            HStack {
                MediaButton(
                    icon: "textformat.size.smaller",
                    action: onSubtitleSmaller,
                    isEnabled: hasSubtitles
                )

                Spacer()

                Text("Subtitle Size")
                    .font(.headline)

                Spacer()

                MediaButton(
                    icon: "textformat.size.larger",
                    action: onSubtitleLarger,
                    isEnabled: hasSubtitles
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

private struct SubtitlePicker: View {
    let tracks: [SubtitleTrack]
    let currentId: Int
    let isEnabled: Bool
    let onSelect: (Int) -> Void

    private var canSelect: Bool { isEnabled && !tracks.isEmpty }

    private var label: String {
        if tracks.isEmpty { return "No Subtitles" }
        let current = tracks.first { $0.id == currentId }?.title ?? "Off"
        return "Subtitles: \(current)"
    }

    var body: some View {
        Menu {
            // The selection mirrors what IINA reports back, so it stays correct
            // when subtitles are also changed from the Mac.
            Picker("Subtitles", selection: Binding(get: { currentId }, set: onSelect)) {
                Text("Off").tag(0)
                ForEach(tracks) { track in
                    Text(track.title).tag(track.id)
                }
            }
        } label: {
            Label(label, systemImage: "captions.bubble")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSelect ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .disabled(!canSelect)
    }
}

#Preview {
    let tracks = [SubtitleTrack(id: 1, title: "English [eng]"), SubtitleTrack(id: 2, title: "Signs & Songs [eng]")]

    VStack(spacing: 20) {
        MediaControlsView(isEnabled: true, subtitleTracks: tracks, currentSubtitleId: 1, onPlay: {}, onPause: {}, onForward: {}, onBackward: {}, onSelectSubtitle: { _ in }, onSubtitleSmaller: {}, onSubtitleLarger: {})
        MediaControlsView(isEnabled: true, subtitleTracks: [], currentSubtitleId: 0, onPlay: {}, onPause: {}, onForward: {}, onBackward: {}, onSelectSubtitle: { _ in }, onSubtitleSmaller: {}, onSubtitleLarger: {})
        MediaControlsView(isEnabled: false, subtitleTracks: [], currentSubtitleId: 0, onPlay: {}, onPause: {}, onForward: {}, onBackward: {}, onSelectSubtitle: { _ in }, onSubtitleSmaller: {}, onSubtitleLarger: {})
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.gray)
}
