import Foundation

struct CommandResponse: Codable {
    let ok: Bool
    let error: String?
}