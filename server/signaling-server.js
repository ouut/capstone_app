const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 3000;
const wss = new WebSocketServer({ port: PORT });

// Map of clientId -> WebSocket connection
const clients = new Map();

console.log(`Signaling server listening on ws://0.0.0.0:${PORT}`);

wss.on("connection", (ws, req) => {
  const remoteAddr = req.socket.remoteAddress;
  console.log(`[connect] ${remoteAddr}`);

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      console.warn("[parse] invalid JSON from", remoteAddr);
      return;
    }

    // Ignore messages from unregistered clients (except register itself)
    if (!ws._clientId && msg.type !== "register") {
      console.warn(`[unregistered] type=${msg.type} from ${remoteAddr} — ignoring`);
      return;
    }

    switch (msg.type) {
      case "register": {
        const clientId = msg.clientId || remoteAddr;
        clients.set(clientId, ws);
        ws._clientId = clientId;
        console.log(`[register] ${clientId}`);

        // Confirm registration
        ws.send(JSON.stringify({ type: "registered", clientId }));
        break;
      }

      case "offer":
      case "answer":
      case "ice": {
        // Relay to all other connected clients (or a specific target)
        broadcast(msg, ws._clientId);
        console.log(`[relay] ${msg.type} from ${ws._clientId}`);
        break;
      }

      case "data": {
        // Relay data to all other clients (game server receives it)
        broadcast(msg, ws._clientId);
        break;
      }

      default:
        console.log(`[unknown] type=${msg.type} from ${ws._clientId}`);
    }
  });

  ws.on("close", () => {
    if (ws._clientId) {
      console.log(`[disconnect] ${ws._clientId}`);
      clients.delete(ws._clientId);
    }
  });

  ws.on("error", (err) => {
    console.error(`[error] ${ws._clientId || remoteAddr}:`, err.message);
  });
});

function broadcast(message, excludeClientId) {
  const payload = JSON.stringify(message);
  for (const [id, ws] of clients) {
    if (id !== excludeClientId && ws.readyState === 1) {
      ws.send(payload);
    }
  }
}

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\nShutting down...");
  wss.close(() => process.exit(0));
});
