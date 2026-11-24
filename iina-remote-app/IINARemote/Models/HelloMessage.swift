import Foundation

/// The first message on every connection from plugins at protocol version 2+.
struct HelloMessage: Codable {
    let type: String
    let protocolVersion: Int
}

/// Just the `type` of a pushed message, to recognise kinds this app predates.
struct MessageEnvelope: Codable {
    let type: String?
}