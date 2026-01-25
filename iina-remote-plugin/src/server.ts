const { ws, core } = iina;

interface RemoteCommand {
  command: "play" | "pause" | "forward" | "backward";
  token: string;
}

type CommandResponse = { ok: true } | { ok: false; error: string };

export const startServer = (
  token: string,
  onSuccess: (port: number) => void,
) => {
  const maxPort = 9000;
  let currentPort = 8000;
  let attemptingPort = currentPort;
  let isActive = true;
  let pendingRetry = false;

  ws.onStateUpdate((state) => {
    if (!isActive) return;

    if (state === "ready") {
      isActive = false;
      setupHandlers(token);
      onSuccess(attemptingPort);
    } else if ((state === "failed" || state === "cancelled") && !pendingRetry) {
      pendingRetry = true;
      currentPort++;
      if (currentPort <= maxPort) {
        setTimeout(() => {
          pendingRetry = false;
          tryPort();
        }, 50);
      } else {
        isActive = false;
      }
    }
  });

  const tryPort = () => {
    if (currentPort > maxPort || !isActive || pendingRetry) return;

    attemptingPort = currentPort;
    ws.createServer({ port: attemptingPort });
    ws.startServer();
  };

  tryPort();
};

const setupHandlers = (token: string) => {
  ws.onMessage((connectionId, message) => {
    try {
      const command: RemoteCommand = JSON.parse(message.text());
      if (command.token !== token) {
        sendResponse(connectionId, { ok: false, error: "Invalid token" });
        return;
      }
      sendResponse(connectionId, executeCommand(command.command));
    } catch (error) {
      sendResponse(connectionId, { ok: false, error: "Invalid message" });
    }
  });
};

const executeCommand = (command: string): CommandResponse => {
  try {
    switch (command) {
      case "play":
        core.resume();
        break;
      case "pause":
        core.pause();
        break;
      case "forward":
        core.seek(5, true);
        break;
      case "backward":
        core.seek(-5, true);
        break;

      default:
        return { ok: false, error: "Unknown command" };
    }

    return { ok: true };
  } catch (error) {
    return { ok: false, error: "Failed to execute command" };
  }
};

const sendResponse = async (connectionId: string, response: CommandResponse) =>
  ws.sendText(connectionId, JSON.stringify(response));
