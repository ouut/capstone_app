const dgram = require("dgram");
const fs = require("fs");
const path = require("path");

const PORT = process.env.UDP_PORT || 5000;
const SAVE_DIR = process.env.SAVE_DIR || path.join(__dirname, "training_data");

// Ensure save directory exists
fs.mkdirSync(SAVE_DIR, { recursive: true });

const server = dgram.createSocket("udp4");

// Track senders by their IP:port — each gets its own .jsonl file
const streams = new Map();

server.on("listening", () => {
  const addr = server.address();
  console.log(`UDP receiver listening on ${addr.address}:${addr.port}`);
  console.log(`Saving training data to: ${SAVE_DIR}`);
});

server.on("message", (msg, rinfo) => {
  const senderKey = `${rinfo.address}:${rinfo.port}`;

  // Get or create a stream for this sender
  let stream = streams.get(senderKey);
  if (!stream) {
    const sessionId = `${Date.now()}_${rinfo.address.replace(/[^a-zA-Z0-9]/g, "_")}`;
    const sessionFile = path.join(SAVE_DIR, `${sessionId}.jsonl`);
    stream = fs.createWriteStream(sessionFile, { flags: "a" });
    streams.set(senderKey, stream);
    console.log(`[new sender] ${senderKey} → ${sessionFile}`);
  }

  // Parse and enrich the frame
  let frame;
  try {
    frame = JSON.parse(msg.toString());
  } catch {
    console.warn(`[parse] invalid JSON from ${senderKey}`);
    return;
  }

  frame.serverReceivedAt = Date.now();
  frame.sender = senderKey;

  stream.write(JSON.stringify(frame) + "\n");

  // Log a compact preview
  const parts = [];
  if (frame.pose) parts.push("pose");
  if (frame.motion) parts.push("motion");
  if (frame.audio) parts.push("audio");
  if (frame.prediction) parts.push(`pred=${frame.prediction.gesture}`);
  const sensors = parts.join(",") || "empty";
  console.log(`[${senderKey}] ts=${frame.timestamp.toFixed(2)} sensors=[${sensors}]`);
});

server.on("error", (err) => {
  console.error(`UDP server error: ${err.message}`);
  server.close();
});

server.bind(PORT);

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\nShutting down...");
  for (const stream of streams.values()) {
    stream.end();
  }
  server.close(() => process.exit(0));
});
