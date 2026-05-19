const { WebSocketServer } = require("ws");
const fs = require("fs");
const path = require("path");

const PORT = process.env.DATA_PORT || 3001;
const SAVE_DIR = process.env.SAVE_DIR || path.join(__dirname, "training_data");

// Ensure save directory exists
fs.mkdirSync(SAVE_DIR, { recursive: true });

const wss = new WebSocketServer({ port: PORT });
console.log(`Data server listening on ws://0.0.0.0:${PORT}`);
console.log(`Saving training data to: ${SAVE_DIR}`);

wss.on("connection", (ws, req) => {
  const remoteAddr = req.socket.remoteAddress;
  console.log(`[connect] ${remoteAddr}`);

  // Create a session file for this connection
  const sessionId = `${Date.now()}_${remoteAddr.replace(/[^a-zA-Z0-9]/g, "_")}`;
  const sessionFile = path.join(SAVE_DIR, `${sessionId}.jsonl`);
  const stream = fs.createWriteStream(sessionFile, { flags: "a" });

  console.log(`[session] ${sessionId}`);

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      console.warn("[parse] invalid JSON from", remoteAddr);
      return;
    }

    // Add server timestamp
    msg.serverReceivedAt = Date.now();
    stream.write(JSON.stringify(msg) + "\n");

    const preview = JSON.stringify(msg).substring(0, 80);
    console.log(`[data] ${sessionId}: ${preview}...`);
  });

  ws.on("close", () => {
    console.log(`[disconnect] ${sessionId}`);
    stream.end();
  });

  ws.on("error", (err) => {
    console.error(`[error] ${sessionId}:`, err.message);
    stream.end();
  });

  // Send session confirmation
  ws.send(
    JSON.stringify({
      type: "session_started",
      sessionId,
      savePath: sessionFile,
    })
  );
});

process.on("SIGINT", () => {
  console.log("\nShutting down data server...");
  wss.close(() => process.exit(0));
});
