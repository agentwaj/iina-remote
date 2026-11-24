// Drives server.ts the way the app does: real JSON messages in through a fake
// WebSocket, replies and IINA calls checked on the way out. Node runs the
// TypeScript source directly by stripping its types.
import assert from "node:assert/strict";
import { beforeEach, describe, test } from "node:test";

const TOKEN = "secret";

// A stand-in for IINA's `iina` global, recording what the plugin asks of it.
const fake = {
  handlers: {},
  events: {},
  sent: [],
  mpvCommands: [],
  trackList: [],
  core: {
    status: { title: "Movie.mkv" },
    subtitle: { id: 0 },
    resume() {},
    pause() {},
    seek() {},
  },
};

globalThis.iina = {
  ws: {
    onStateUpdate: (cb) => (fake.handlers.state = cb),
    onMessage: (cb) => (fake.handlers.message = cb),
    onNewConnection: (cb) => (fake.handlers.connection = cb),
    onConnectionStateUpdate: (cb) => (fake.handlers.connectionState = cb),
    createServer() {},
    startServer() {},
    sendText: (conn, text) => fake.sent.push({ conn, message: JSON.parse(text) }),
  },
  core: fake.core,
  mpv: {
    getNative: (name) => (name === "track-list" ? fake.trackList : undefined),
    command: (name, args) => fake.mpvCommands.push([name, ...args]),
  },
  event: { on: (name, cb) => (fake.events[name] = cb) },
};

// Imported after the global exists: server.ts reads `iina` at load time.
const { startServer } = await import("../src/server.ts");

startServer(TOKEN, () => {});
fake.handlers.state("ready");

const connect = (conn) => fake.handlers.connection(conn, { path: "/" });
const send = (conn, body) =>
  fake.handlers.message(conn, { text: () => JSON.stringify(body) });
const sentTo = (conn) => fake.sent.filter((s) => s.conn === conn).map((s) => s.message);
const lastReply = (conn) => sentTo(conn).at(-1);

beforeEach(() => {
  fake.sent = [];
  fake.mpvCommands = [];
  fake.core.subtitle.id = 0;
  fake.trackList = [
    { id: 1, type: "video" },
    { id: 1, type: "sub", title: "English", lang: "eng", selected: true },
    { id: 2, type: "sub", title: "Signs & Songs", lang: "und" },
    { id: 3, type: "sub", lang: "jpn" },
    { id: 4, type: "sub" },
    { id: 1, type: "audio", lang: "eng", selected: true },
  ];
});

describe("on connect", () => {
  test("sends the title, then subtitles", () => {
    connect("c1");
    const [title, subtitles] = sentTo("c1");
    assert.deepEqual(title, { type: "title", title: "Movie.mkv" });
    assert.equal(subtitles.type, "subtitles");
  });
});

describe("subtitle message", () => {
  test("lists only subtitle tracks, with readable titles", () => {
    connect("c1");
    const subtitles = sentTo("c1").find((m) => m.type === "subtitles");
    assert.deepEqual(subtitles, {
      type: "subtitles",
      tracks: [
        { id: 1, title: "English [eng]" },
        { id: 2, title: "Signs & Songs" }, // "und" (undetermined) is left out
        { id: 3, title: "[jpn]" },
        { id: 4, title: "Track 4" },
      ],
      currentId: 1,
    });
  });

  test("reports 0 when subtitles are off", () => {
    fake.trackList = fake.trackList.map((t) => ({ ...t, selected: t.type !== "sub" }));
    connect("c1");
    assert.equal(sentTo("c1").find((m) => m.type === "subtitles").currentId, 0);
  });

  test("is broadcast to open connections when the track changes", () => {
    connect("c1");
    connect("c2");
    connect("gone");
    fake.handlers.connectionState("gone", "cancelled");
    fake.sent = [];

    fake.events["mpv.sid.changed"]();

    assert.deepEqual(fake.sent.map((s) => s.conn).sort(), ["c1", "c2"]);
    assert.ok(fake.sent.every((s) => s.message.type === "subtitles"));
  });

  test("is broadcast when the track list changes", () => {
    connect("c1");
    fake.sent = [];
    fake.events["mpv.track-list.changed"]();
    assert.equal(lastReply("c1").type, "subtitles");
  });
});

describe("commands", () => {
  test("rejects a wrong token without acting", () => {
    send("c1", { command: "setSubtitle", subtitleId: 2, token: "wrong" });
    assert.deepEqual(lastReply("c1"), { ok: false, error: "Invalid token" });
    assert.equal(fake.core.subtitle.id, 0);
  });

  test("rejects malformed JSON", () => {
    fake.handlers.message("c1", { text: () => "not json" });
    assert.deepEqual(lastReply("c1"), { ok: false, error: "Invalid message" });
  });

  test("rejects an unknown command", () => {
    send("c1", { command: "rewind", token: TOKEN });
    assert.deepEqual(lastReply("c1"), { ok: false, error: "Unknown command" });
  });

  test("setSubtitle switches the track", () => {
    send("c1", { command: "setSubtitle", subtitleId: 2, token: TOKEN });
    assert.deepEqual(lastReply("c1"), { ok: true });
    assert.equal(fake.core.subtitle.id, 2);
  });

  test("setSubtitle with 0 turns subtitles off", () => {
    fake.core.subtitle.id = 1;
    send("c1", { command: "setSubtitle", subtitleId: 0, token: TOKEN });
    assert.equal(fake.core.subtitle.id, 0);
  });

  for (const subtitleId of [undefined, "2", 1.5]) {
    test(`setSubtitle rejects subtitleId ${JSON.stringify(subtitleId)}`, () => {
      send("c1", { command: "setSubtitle", subtitleId, token: TOKEN });
      assert.deepEqual(lastReply("c1"), { ok: false, error: "Invalid subtitle track" });
      assert.equal(fake.core.subtitle.id, 0);
    });
  }

  test("subtitleLarger and subtitleSmaller step sub-scale by 0.1", () => {
    send("c1", { command: "subtitleLarger", token: TOKEN });
    send("c1", { command: "subtitleSmaller", token: TOKEN });
    assert.deepEqual(fake.mpvCommands, [
      ["add", "sub-scale", "0.1"],
      ["add", "sub-scale", "-0.1"],
    ]);
    assert.deepEqual(lastReply("c1"), { ok: true });
  });
});
