import Foundation

struct ConnectionData: Codable, Equatable {
    let host: String
    let port: Int
    let token: String
}