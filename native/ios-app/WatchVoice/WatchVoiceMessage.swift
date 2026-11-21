import Foundation

enum WatchVoiceRequest: Codable {
    case submit(id: UUID, audio: Data)
    case status(id: UUID)

    // A 15-second mono AAC recording at 16 kbps stays below this limit.
    static let maxAudioBytes = 43_000
    static let contextKey = "poki.watchVoice.update"
    static let maxMessageBytes = 60_000
}

struct WatchVoiceUpdate: Codable, Equatable, Identifiable {
    enum Phase: Int, Codable {
        case received
        case running
        case finished
        case blocked

        var isTerminal: Bool { self == .finished || self == .blocked }
    }

    let id: UUID
    let phase: Phase
    let text: String?
}
