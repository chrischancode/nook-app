import net from "node:net";
import fs from "node:fs";

/// Path to Nook's Unix domain socket, hard-coded to match HookSocketServer.
const SOCKET_PATH = "/tmp/nook.sock";

/// Path to the command socket — Nook connects here to send commands
/// (e.g. permission replies) back to the plugin.
const COMMAND_SOCKET_PATH = "/tmp/nook-command.sock";

/// Debug log for plugin-side troubleshooting.
const DEBUG_LOG = "/tmp/nook-plugin-debug.log";

function logDebug(message) {
  try {
    fs.appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${message}\n`);
  } catch {}
}

/// Send a payload to Nook's Unix socket.
/// Failures are silently swallowed so the plugin never crashes OpenCode.
function send(payload) {
  return new Promise((resolve) => {
    try {
      const socket = new net.Socket();
      socket.connect(SOCKET_PATH, () => {
        socket.end(JSON.stringify(payload) + "\n");
      });
      socket.on("error", () => resolve());
      socket.on("close", () => resolve());
    } catch {
      resolve();
    }
  });
}

/// Create the command socket server so Nook can send commands to us.
/// Commands are JSON objects with a `cmd` field. The only command today
/// is `permission.reply`, which carries `requestId` and `reply`
/// ("once" | "always" | "reject").
function startCommandServer(input) {
  try {
    // Clean up any stale socket from a previous run.
    try { fs.unlinkSync(COMMAND_SOCKET_PATH); } catch {}
  } catch {}

  const server = net.createServer((socket) => {
    let buffer = "";
    socket.on("data", (chunk) => { buffer += chunk.toString(); });
    socket.on("end", () => {
      handleCommand(buffer, input);
    });
    socket.on("error", () => {});
  });

  server.on("error", (err) => {
    logDebug(`command server error: ${err.message}`);
  });

  server.listen(COMMAND_SOCKET_PATH, () => {
    logDebug(`command server listening on ${COMMAND_SOCKET_PATH}`);
  });
}

/// Handle a single command line from Nook.
async function handleCommand(rawLine, input) {
  let cmd;
  try {
    cmd = JSON.parse(rawLine);
  } catch (err) {
    logDebug(`handleCommand parse error: ${err.message}`);
    return;
  }

  logDebug(`handleCommand cmd=${JSON.stringify(cmd)}`);

  if (cmd.cmd === "permission.reply") {
    const requestId = cmd.requestId;
    const reply = cmd.reply; // "once" | "always" | "reject"
    if (!requestId || !reply) {
      logDebug("handleCommand missing requestId or reply");
      return;
    }

    try {
      const client = input?.client;
      // opencode 1.17.20 exposes the HTTP client on `client._client`
      // (HeyApi Client). The v2 permission reply route is
      // POST /permission/{requestID}/reply. When opencode runs without a
      // serverUrl (TUI mode), `client._client` is configured with an
      // in-process fetch that hits opencode's own app — so we don't need
      // a real HTTP listener on port 4096.
      const heyApiClient = client?._client;
      if (!heyApiClient || typeof heyApiClient.post !== "function") {
        logDebug("reply FAILED: no client._client.post available");
        return;
      }

      // opencode v1 permission reply body: { reply: "once" | "always" | "reject" }
      // Nook's reply values map 1:1 — no transformation needed.
      const res = await heyApiClient.post({
        url: "/permission/{requestID}/reply",
        path: { requestID: requestId },
        body: { reply },
      });

      logDebug(`reply OK res=${JSON.stringify(res)}`);
    } catch (err) {
      logDebug(`reply FAILED: ${err.message}\n${err.stack || ""}`);
    }
  }
}

/// OpenCode server plugin entry point.
/// opencode calls `server(input, options)` directly with the plugin input
/// (including `client`). We capture `input` in the closure so the command
/// socket handler can use it later for permission replies.
export default function server(input) {
  // Start listening for commands from Nook as soon as the plugin loads.
  startCommandServer(input);

  return {
    event: async ({ event }) => {
      if (event.type === "permission.asked") {
        logDebug(`permission.asked props=${JSON.stringify(event.properties)}`);
      }
      await send({
        origin: "opencode",
        type: event.type,
        properties: event.properties,
      });
    },
  };
}
