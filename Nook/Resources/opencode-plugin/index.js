import net from "node:net";
import fs from "node:fs";

/// Path to Nook's Unix domain socket, hard-coded to match HookSocketServer.
const SOCKET_PATH = "/tmp/nook.sock";

/// Path to the command socket — Nook connects here to send commands
/// (e.g. permission replies) back to the plugin.
/// Pid-scoped so multiple opencode instances don't contend for a single
/// socket (kernel load-balances new connections across listeners, so a
/// reply could land on the wrong instance → PermissionNotFoundError).
const INSTANCE_PID = process.pid;
const COMMAND_SOCKET_PATH = `/tmp/nook-command-${INSTANCE_PID}.sock`;

/// Debug log for plugin-side troubleshooting.
const DEBUG_LOG = "/tmp/nook-plugin-debug.log";

function logDebug(message) {
  try {
    fs.appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] pid=${INSTANCE_PID} ${message}\n`);
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

  // Remove our pid-scoped socket on exit so /tmp doesn't accumulate.
  process.on("exit", () => {
    try { fs.unlinkSync(COMMAND_SOCKET_PATH); } catch {}
  });

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
const PLUGIN_VERSION = "1.2.0";
export default function server(input) {
  logDebug(`nook plugin v${PLUGIN_VERSION} loaded serverUrl=${input?.serverUrl?.toString() ?? "undefined"}`);
  // Start listening for commands from Nook as soon as the plugin loads.
  startCommandServer(input);

  // Get the actual server port from input.serverUrl (provided by OpenCode).
  // serverUrl is set after the HTTP server starts, so it may be undefined briefly.
  // URL.port returns a string (e.g. "4096") — coerce to a number so Nook's
  // Int parsing doesn't drop the event.
  const getServerPort = () => {
    try {
      return Number(input?.serverUrl?.port ?? 4096) || 4096;
    } catch {
      return 4096;
    }
  };

  // Send server port to Nook. Retry until Nook's socket is ready.
  // Nook might not be listening on /tmp/nook.sock when the plugin first loads.
  let retryCount = 0;
  const maxRetries = 30; // 30 * 2s = 60s
  const sendServerPort = () => {
    if (retryCount >= maxRetries) return;
    retryCount++;
    const port = getServerPort();
    logDebug(`sending serverPort=${port} (attempt ${retryCount})`);
    send({
      origin: "opencode",
      type: "serverPort",
      properties: { port, pid: INSTANCE_PID },
    }).then(() => {
      if (retryCount < maxRetries) {
        setTimeout(sendServerPort, 2000);
      }
    });
  };
  // Initial attempt + retries every 2s
  sendServerPort();

  return {
    event: async ({ event }) => {
      if (event.type === "permission.asked") {
        logDebug(`permission.asked pid=${INSTANCE_PID} props=${JSON.stringify(event.properties)}`);
      }
      // Merge pid into forwarded properties so Nook can route per-instance
      // (permission replies, serverPort association).
      const props = (typeof event.properties === "object" && event.properties !== null)
        ? { ...event.properties, pid: INSTANCE_PID }
        : { pid: INSTANCE_PID };
      await send({
        origin: "opencode",
        type: event.type,
        properties: props,
      });
    },
  };
}
