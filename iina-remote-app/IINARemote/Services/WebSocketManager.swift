import Combine
import Foundation

class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var errorMessage: String = ""

    private var connectionData: ConnectionData?
    private var isManualDisconnect = false
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func connect(to connectionData: ConnectionData) {
        self.connectionData = connectionData
        connectionStatus = .connecting
        errorMessage = ""
        isManualDisconnect = false

        print("🔌 Attempting to connect to ws://\(connectionData.host):\(connectionData.port)")

        let url = URL(string: "ws://\(connectionData.host):\(connectionData.port)")!
        webSocketTask = urlSession.webSocketTask(with: url)

        webSocketTask?.resume()
        receiveMessage()

        // Set a timeout for connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if self.connectionStatus == .connecting {
                self.connectionStatus = .disconnected
                self.errorMessage = "Connection timeout - make sure IINA server is running and reachable"
            }
        }
    }

    func disconnect() {
        isManualDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionStatus = .disconnected
        errorMessage = ""
    }

    @MainActor
    func sendCommand(_ command: String) {
        guard let connectionData = connectionData,
              connectionStatus == .connected
        else {
            print("⚠️ Cannot send command: not connected (status: \(connectionStatus))")
            return
        }

        print("📤 Sending command: \(command)")
        let remoteCommand = RemoteCommand(command: command, token: connectionData.token)

        do {
            let data = try JSONEncoder().encode(remoteCommand)
            let message = URLSessionWebSocketTask.Message.data(data)
            webSocketTask?.send(message) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        print("❌ Failed to send command: \(error.localizedDescription)")
                        self?.errorMessage = "Failed to send command: \(error.localizedDescription)"
                    }
                } else {
                    print("✅ Command sent successfully")
                }
            }
        } catch {
            print("❌ Failed to encode command: \(error.localizedDescription)")
            errorMessage = "Failed to encode command: \(error.localizedDescription)"
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case let .failure(error):
                DispatchQueue.main.async {
                    self?.connectionStatus = .disconnected

                    guard let self = self, !self.isManualDisconnect else { return }

                    let errorDesc = error.localizedDescription
                    print("❌ WebSocket connection failed: \(errorDesc)")
                    self.errorMessage = "Connection failed: \(errorDesc)"
                }
            case let .success(message):
                print("📨 Received WebSocket message")

                switch message {
                case let .data(data):
                    self?.handleResponse(data: data)
                case let .string(string):
                    print("📨 Received string message: \(string)")
                    if let data = string.data(using: .utf8) {
                        self?.handleResponse(data: data)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didOpenWithProtocol _: String?) {
        DispatchQueue.main.async {
            self.connectionStatus = .connected
            print("✅ WebSocket connected successfully")
        }
    }

    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didCloseWith _: URLSessionWebSocketTask.CloseCode, reason _: Data?) {
        DispatchQueue.main.async {
            self.connectionStatus = .disconnected
            print("🔌 WebSocket disconnected")
        }
    }

    private func handleResponse(data: Data) {
        DispatchQueue.main.async {
            do {
                let response = try JSONDecoder().decode(CommandResponse.self, from: data)
                if !response.ok {
                    self.errorMessage = response.error ?? "Unknown error"
                }
            } catch {
                self.errorMessage = "Invalid response: \(error.localizedDescription)"
            }
        }
    }
}
