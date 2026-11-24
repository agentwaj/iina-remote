import Combine
import Foundation

class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private static let connectionDataKey = "SavedConnectionData"
    /// Raise when the app starts relying on newer plugin commands or messages.
    /// See PROTOCOL_VERSION in the plugin's server.ts.
    private static let minimumPluginProtocolVersion = 2

    private var webSocketTask: URLSessionWebSocketTask?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var errorMessage: String = ""
    @Published var currentTitle: String = ""
    @Published var subtitleTracks: [SubtitleTrack] = []
    /// 0 when subtitles are off.
    @Published var currentSubtitleId: Int = 0
    /// The connected plugin is too old for this app; set from its hello message.
    @Published var isPluginOutdated = false

    private var connectionData: ConnectionData?
    private var hasReceivedHello = false
    private var isManualDisconnect = false
    private var isAutoConnecting = false
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Persistence

    @MainActor
    private func saveConnectionData(_ data: ConnectionData) {
        do {
            let encoded = try JSONEncoder().encode(data)
            UserDefaults.standard.set(encoded, forKey: Self.connectionDataKey)
        } catch {}
    }

    @MainActor
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

    @MainActor
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
        // backgrounded). Its callbacks are ignored by the identity checks below.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let url = URL(string: "ws://\(connectionData.host):\(connectionData.port)")!
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task

        task.resume()
        receiveMessage(on: task)

        // Set a timeout for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            // A newer connect() owns the state now.
            guard task === self.webSocketTask else { return }

            if self.connectionStatus == .connecting {
                self.connectionStatus = .disconnected

                if self.isAutoConnecting {
                    self.clearSavedConnectionData()
                    self.isAutoConnecting = false
                } else {
                    self.errorMessage = "Connection timeout - make sure IINA server is running and reachable"
                }
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
    @MainActor
    func selectSubtitle(_ id: Int) {
        sendCommand("setSubtitle", subtitleId: id)
    }

    @MainActor
    func sendCommand(_ command: String, subtitleId: Int? = nil) {
        guard let connectionData = connectionData,
              connectionStatus == .connected
        else { return }

        let remoteCommand = RemoteCommand(command: command, token: connectionData.token, subtitleId: subtitleId)

        do {
            let data = try JSONEncoder().encode(remoteCommand)
            let message = URLSessionWebSocketTask.Message.data(data)
            webSocketTask?.send(message) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Failed to send command: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            errorMessage = "Failed to encode command: \(error.localizedDescription)"
        }
    }

    private func receiveMessage(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            switch result {
            case let .failure(error):
                DispatchQueue.main.async {
                    // A failure from a replaced socket says nothing about the current one.
                    guard let self = self, task === self.webSocketTask else { return }

                    self.connectionStatus = .disconnected

                    guard !self.isManualDisconnect else { return }

                    if self.isAutoConnecting {
                        self.clearSavedConnectionData()
                        self.isAutoConnecting = false
                    } else {
                        self.errorMessage = "Connection failed: \(error.localizedDescription)"
                    }
                }
            case let .success(message):
                switch message {
                case let .data(data):
                    self?.handleResponse(data: data, from: task)
                case let .string(string):
                    if let data = string.data(using: .utf8) {
                        self?.handleResponse(data: data, from: task)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage(on: task)
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_: URLSession, webSocketTask task: URLSessionWebSocketTask, didOpenWithProtocol _: String?) {
        DispatchQueue.main.async {
            guard task === self.webSocketTask else { return }

            self.connectionStatus = .connected
            // Anything from earlier attempts no longer applies.
            self.errorMessage = ""

            if let connectionData = self.connectionData {
                self.saveConnectionData(connectionData)
            }

            self.isAutoConnecting = false
        }
    }

    func urlSession(_: URLSession, webSocketTask task: URLSessionWebSocketTask, didCloseWith _: URLSessionWebSocketTask.CloseCode, reason _: Data?) {
        DispatchQueue.main.async {
            guard task === self.webSocketTask else { return }

            self.connectionStatus = .disconnected
        }
    }

    private func handleResponse(data: Data, from task: URLSessionWebSocketTask) {
        DispatchQueue.main.async {
            // A message still buffered on a replaced socket would confuse the hello check.
            guard task === self.webSocketTask else { return }

            if let hello = try? JSONDecoder().decode(HelloMessage.self, from: data),
               hello.type == "hello"
            {
                self.hasReceivedHello = true
                self.isPluginOutdated = hello.protocolVersion < Self.minimumPluginProtocolVersion
                return
            }

            let messageType = (try? JSONDecoder().decode(MessageEnvelope.self, from: data))?.type
            // Hello is always sent first, so plugins from before the handshake
            // reveal themselves by pushing anything else before it.
            if messageType != nil, !self.hasReceivedHello {
                self.isPluginOutdated = true
            }

            // Try to decode as TitleUpdate first
            if let titleUpdate = try? JSONDecoder().decode(TitleUpdate.self, from: data),
               titleUpdate.type == "title"
            {
                self.currentTitle = titleUpdate.title
                return
            }

            if let subtitleUpdate = try? JSONDecoder().decode(SubtitleUpdate.self, from: data),
               subtitleUpdate.type == "subtitles"
            {
                self.subtitleTracks = subtitleUpdate.tracks
                self.currentSubtitleId = subtitleUpdate.currentId
                return
            }

            // A pushed message from a newer plugin that this app doesn't know yet.
            if messageType != nil { return }

            // Otherwise, try to decode as CommandResponse
            do {
                let response = try JSONDecoder().decode(CommandResponse.self, from: data)
                if response.ok {
                    // A command just went through, so any earlier error is stale.
                    self.errorMessage = ""
                } else {
                    self.errorMessage = response.error ?? "Unknown error"
                }
            } catch {
                self.errorMessage = "Invalid response: \(error.localizedDescription)"
            }
        }
    }
}
