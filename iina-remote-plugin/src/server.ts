const { ws, core, mpv, event } = iina;

// Bump whenever commands or messages change, and raise the app's
// minimumPluginProtocolVersion to match if the app depends on the change.
// 1: play/pause/seek and title (implicit: those plugins send no hello)
// 2: subtitle track selection and size
export const PROTOCOL_VERSION = 2;

interface RemoteCommand {
  command:
    | "play"
    | "pause"
    | "forward"
    | "backward"
    | "setSubtitle"
    | "subtitleLarger"
    | "subtitleSmaller";
  token: string;
  // Only for "setSubtitle". 0 turns subtitles off, matching IINA's own "None" track.
  subtitleId?: number;
}

type CommandResponse = { ok: true } | { ok: false; error: string };

// Always the first message on a connection, so the app can tell whether
// this plugin build supports what it needs.
interface HelloMessage {
  type: "hello";
  protocolVersion: number;
}

interface TitleUpdate {
  type: "title";
  title: string;
}

interface SubtitleUpdate {
  type: "subtitles";
  tracks: { id: number; title: string }[];
  // 0 when subtitles are off.
  currentId: number;
}

// An entry of mpv's `track-list` property.
interface MpvTrack {
  id: number;
  type: "video" | "audio" | "sub";
  title?: string;
  lang?: string;
  selected?: boolean;
}

const connections = new Set<string>();

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
      sendResponse(connectionId, executeCommand(command));
    } catch (error) {
      sendResponse(connectionId, { ok: false, error: "Invalid message" });
    }
  });

  ws.onNewConnection((connectionId) => {
    connections.add(connectionId);
    const hello: HelloMessage = { type: "hello", protocolVersion: PROTOCOL_VERSION };
    ws.sendText(connectionId, JSON.stringify(hello));
    const titleUpdate: TitleUpdate = {
      type: "title",
      title: core.status.title || "No title",
    };
    ws.sendText(connectionId, JSON.stringify(titleUpdate));
    ws.sendText(connectionId, JSON.stringify(getSubtitleUpdate()));
  });

  ws.onConnectionStateUpdate((connectionId, state) => {
    if (state === "failed" || state === "cancelled") {
      connections.delete(connectionId);
    }
  });

  // Fires when the user switches tracks (from IINA or the remote), a subtitle
  // file is added, or a new file loads.
  const broadcastSubtitles = () => {
    const message = JSON.stringify(getSubtitleUpdate());
    connections.forEach((connectionId) => ws.sendText(connectionId, message));
  };
  event.on("mpv.sid.changed", broadcastSubtitles);
  event.on("mpv.track-list.changed", broadcastSubtitles);
};

// Read mpv's track-list directly instead of core.subtitle: IINA refreshes its
// cached track info asynchronously, so it can still be stale when these
// change events fire.
const getSubtitleUpdate = (): SubtitleUpdate => {
  const subtitles = (mpv.getNative<MpvTrack[]>("track-list") ?? []).filter(
    (track) => track.type === "sub",
  );
  return {
    type: "subtitles",
    tracks: subtitles.map((track) => ({
      id: track.id,
      title: formatTrackTitle(track),
    })),
    currentId: subtitles.find((track) => track.selected)?.id ?? 0,
  };
};

const formatTrackTitle = ({ id, title, lang }: MpvTrack) => {
  const language = lang && lang !== "und" ? `[${lang}]` : "";
  return [title, language].filter(Boolean).join(" ") || `Track ${id}`;
};

const executeCommand = (command: RemoteCommand): CommandResponse => {
  try {
    switch (command.command) {
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
      case "setSubtitle":
        if (!Number.isInteger(command.subtitleId)) {
          return { ok: false, error: "Invalid subtitle track" };
        }
        core.subtitle.id = command.subtitleId!;
        break;
      // Same step as IINA's default Shift+G / Shift+F bindings.
      case "subtitleLarger":
        mpv.command("add", ["sub-scale", "0.1"]);
        break;
      case "subtitleSmaller":
        mpv.command("add", ["sub-scale", "-0.1"]);
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
