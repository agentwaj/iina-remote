import Foundation

struct ConnectionData: Codable {
    let host: String
    let port: Int
    let token: String
}