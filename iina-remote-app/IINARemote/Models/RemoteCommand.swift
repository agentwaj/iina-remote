import Foundation

struct RemoteCommand: Codable {
    let command: String
    let token: String
    /// Only for "setSubtitle". 0 turns subtitles off.
    var subtitleId: Int? = nil
}