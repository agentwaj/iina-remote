import Foundation
import Observation

@Observable
final class WebSocketManager {
    private static let connectionDataKey = "SavedConnectionData"
    /// Raise when the app starts relying on newer plugin commands or messages.
    /// See PROTOCOL_VERSION in the plugin's server.ts.
    private static let minimumPluginProtocolVersion = 2

    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var errorMessage: String = ""
    private(set) var currentTitle: String = ""
    private(set) var subtitleTracks: [SubtitleTrack] = []
    /// 0 when subtitles are off.
    private(set) var currentSubtitleId: Int = 0
    /// The connected plugin is too old for this app; set from its hello message.
    private(set) var isPluginOutdated = false

    @ObservationIgnored private var webSocketTask: URLSessionWebSocketTask?
    @ObservationIgnored private var connectionData: ConnectionData?
    @ObservationIgnored private var hasReceivedHello = false
    @ObservationIgnored private var isManualDisconnect = false
    @ObservationIgnored private var isAutoConnecting = false
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private var socketEventsTask: Task<Void, Never>?

    init() {
        // URLSession calls its delegate on a background queue, so the delegate
        // only forwards open/close events here, onto the main actor.
        let (events, continuation) = AsyncStream.makeStream(of: SocketEvent.self)
        urlSession = URLSession(
            configuration: .default,
            delegate: SocketEventDelegate(events: continuation),
            delegateQueue: nil
        )
        socketEventsTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    // MARK: - Persistence

    private func saveConnectionData(_ data: ConnectionData) {
        do {
            let encoded = try JSONEncoder().encode(data)
            UserDefaults.standard.set(encoded, forKey: Self.connectionDataKey)
        } catch {}
    }

    private func loadSavedConnectionData() -> ConnectionData? {
        guard let data = UserDefaults.standard.data(forKey: Self.connectionDataKey) else { return nil }
        do {
            return try JSONDecoder().decode(ConnectionData.self, from: data)
        } catch {
            clearSavedConnectionData()
            return nil
        }
    }

    private func clearSavedConnectionData() {
        clearMediaInfo()
        UserDefaults.standard.removeObject(forKey: Self.connectionDataKey)
    }

    private func clearMediaInfo() {
        currentTitle = ""
        subtitleTracks = []
        currentSubtitleId = 0
    }

    func autoConnectIfPossible() {
        guard let savedData = loadSavedConnectionData() else { return }
        isAutoConnecting = true
        connect(to: savedData)
    }

    func connect(to connectionData: ConnectionData) {
        self.connectionData = connectionData
        connectionStatus = .connecting
        errorMessage = ""
        isManualDisconnect = false
        isPluginOutdated = false
        hasReceivedHello = false

        // Close any previous socket (e.g. one left over from before the app was
        // backgrounded). Its events are ignored by the identity checks below.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let url = URL(string: "ws://\(connectionData.host):\(connectionData.port)")!
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task

        task.resume()
        Task { await receiveMessages(on: task) }

        // Set a timeout for connection
        Task {
            try? await Task.sleep(for: .seconds(10))
            // A newer connect() owns the state now.
            guard task === webSocketTask, connectionStatus == .connecting else { return }

            connectionStatus = .disconnected

            if isAutoConnecting {
                clearSavedConnectionData()
                isAutoConnecting = false
            } else {
                errorMessage = "Connection timeout - make sure IINA server is running and reachable"
            }
        }
    }

    func disconnect() {
        isManualDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStatus = .disconnected
        errorMessage = ""

        clearSavedConnectionData()
    }

    /// Pass 0 to turn subtitles off.
    func selectSubtitle(_ id: Int) {
        sendCommand("setSubtitle", subtitleId: id)
    }

    func sendCommand(_ command: String, subtitleId: Int? = nil) {
        guard let connectionData = connectionData,
              let task = webSocketTask,
              connectionStatus == .connected
        else { return }

        let remoteCommand = RemoteCommand(command: command, token: connectionData.token, subtitleId: subtitleId)

        let data: Data
        do {
            data = try JSONEncoder().encode(remoteCommand)
        } catch {
            errorMessage = "Failed to encode command: \(error.localizedDescription)"
            return
        }

        Task {
            do {
                try await task.send(.data(data))
            } catch {
                guard task === webSocketTask else { return }
                errorMessage = "Failed to send command: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Socket events

    private func receiveMessages(on task: URLSessionWebSocketTask) async {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                handleReceiveFailure(error, on: task)
                return
            }

            // A message still buffered on a replaced socket would confuse the hello check.
            guard task === webSocketTask else { return }

            switch message {
            case let .data(data):
                handleMessage(data)
            case let .string(string):
                if let data = string.data(using: .utf8) {
                    handleMessage(data)
                }
            @unknown default:
                break
            }
        }
    }

    private func handleReceiveFailure(_ error: Error, on task: URLSessionWebSocketTask) {
        // A failure from a replaced socket says nothing about the current one.
        guard task === webSocketTask else { return }

        connectionStatus = .disconnected

        guard !isManualDisconnect else { return }

        if isAutoConnecting {
            clearSavedConnectionData()
            isAutoConnecting = false
        } else {
            errorMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    private func handle(_ event: SocketEvent) {
        switch event {
        case let .opened(task):
            guard task === webSocketTask else { return }

            connectionStatus = .connected
            // Anything from earlier attempts no longer applies.
            errorMessage = ""

            if let connectionData {
                saveConnectionData(connectionData)
            }

            isAutoConnecting = false

        case let .closed(task):
            guard task === webSocketTask else { return }

            connectionStatus = .disconnected
        }
    }

    private func handleMessage(_ data: Data) {
        if let hello = try? JSONDecoder().decode(HelloMessage.self, from: data),
           hello.type == "hello"
        {
            hasReceivedHello = true
            isPluginOutdated = hello.protocolVersion < Self.minimumPluginProtocolVersion
            return
        }

        let messageType = (try? JSONDecoder().decode(MessageEnvelope.self, from: data))?.type
        // Hello is always sent first, so plugins from before the handshake
        // reveal themselves by pushing anything else before it.
        if messageType != nil, !hasReceivedHello {
            isPluginOutdated = true
        }

        // Try to decode as TitleUpdate first
        if let titleUpdate = try? JSONDecoder().decode(TitleUpdate.self, from: data),
           titleUpdate.type == "title"
        {
            currentTitle = titleUpdate.title
            return
        }

        if let subtitleUpdate = try? JSONDecoder().decode(SubtitleUpdate.self, from: data),
           subtitleUpdate.type == "subtitles"
        {
            subtitleTracks = subtitleUpdate.tracks
            currentSubtitleId = subtitleUpdate.currentId
            return
        }

        // A pushed message from a newer plugin that this app doesn't know yet.
        if messageType != nil { return }

        // Otherwise, try to decode as CommandResponse
        do {
            let response = try JSONDecoder().decode(CommandResponse.self, from: data)
            if response.ok {
                // A command just went through, so any earlier error is stale.
                errorMessage = ""
            } else {
                errorMessage = response.error ?? "Unknown error"
            }
        } catch {
            errorMessage = "Invalid response: \(error.localizedDescription)"
        }
    }
}

private enum SocketEvent: Sendable {
    case opened(URLSessionWebSocketTask)
    case closed(URLSessionWebSocketTask)
}

/// URLSession requires a thread-safe delegate. This one holds no state of its
/// own and just hands events to the manager through the stream.
private nonisolated final class SocketEventDelegate: NSObject, URLSessionWebSocketDelegate, Sendable {
    private let events: AsyncStream<SocketEvent>.Continuation

    init(events: AsyncStream<SocketEvent>.Continuation) {
        self.events = events
    }

    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol _: String?) {
        events.yield(.opened(webSocketTask))
    }

    func urlSession(_: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith _: URLSessionWebSocketTask.CloseCode, reason _: Data?) {
        events.yield(.closed(webSocketTask))
    }
}
