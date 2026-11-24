import Foundation

struct SubtitleUpdate: Codable {
    let type: String
    let tracks: [SubtitleTrack]
    /// 0 when subtitles are off.
    let currentId: Int
}

struct SubtitleTrack: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
}