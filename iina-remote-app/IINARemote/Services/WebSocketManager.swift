import Combine
import Foundation

class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private static let connectionDataKey = "SavedConnectionData"

    private var webSocketTask: URLSessionWebSocketTask?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var errorMessage: String = ""
    @Published var currentTitle: String = ""

    private var connectionData: ConnectionData?
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
        currentTitle = ""
        UserDefaults.standard.removeObject(forKey: Self.connectionDataKey)
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
        currentTitle = ""

        clearSavedConnectionData()
    }

    @MainActor
    func sendCommand(_ command: String) {
        guard let connectionData = connectionData,
              connectionStatus == .connected
        else { return }

        let remoteCommand = RemoteCommand(command: command, token: connectionData.token)

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
                    self?.handleResponse(data: data)
                case let .string(string):
                    if let data = string.data(using: .utf8) {
                        self?.handleResponse(data: data)
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

    private func handleResponse(data: Data) {
        DispatchQueue.main.async {
            // Try to decode as TitleUpdate first
            if let titleUpdate = try? JSONDecoder().decode(TitleUpdate.self, from: data),
               titleUpdate.type == "title"
            {
                self.currentTitle = titleUpdate.title
                return
            }

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
