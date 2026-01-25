const { ws, core } = iina;

interface RemoteCommand {
  command: "play" | "pause" | "forward" | "backward";
  token: string;
}

type CommandResponse = { ok: true } | { ok: false; error: string };

export const startServer = (port: number, token: string) => {
  ws.createServer({ port });

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

  ws.startServer();
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
