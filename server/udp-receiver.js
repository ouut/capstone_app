const dgram = require("dgram");
const fs = require("fs");
const path = require("path");

const PORT = process.env.UDP_PORT || 5000;
const SAVE_DIR = process.env.SAVE_DIR || path.join(__dirname, "training_data");
const VERBOSE = process.env.VERBOSE === "1";

// Ensure save directory exists
fs.mkdirSync(SAVE_DIR, { recursive: true });

const server = dgram.createSocket("udp4");

// Track senders by their IP:port
const senders = new Map(); // senderKey -> { stream, file, frameCount, firstSeen }

server.on("listening", () => {
  const addr = server.address();
  console.log(`UDP receiver listening on ${addr.address}:${addr.port}`);
  console.log(`Saving training data to: ${SAVE_DIR}`);
  console.log(`Verbose: ${VERBOSE ? "ON" : "OFF"}\n`);
});

server.on("message", (msg, rinfo) => {
  const senderKey = `${rinfo.address}:${rinfo.port}`;

  // Get or create sender state
  let sender = senders.get(senderKey);
  if (!sender) {
    const sessionId = `${Date.now()}_${rinfo.address.replace(/[^a-zA-Z0-9]/g, "_")}`;
    const sessionFile = path.join(SAVE_DIR, `${sessionId}.jsonl`);
    sender = {
      stream: fs.createWriteStream(sessionFile, { flags: "a" }),
      file: sessionFile,
      frameCount: 0,
      firstSeen: Date.now(),
    };
    senders.set(senderKey, sender);
    console.log(`\n[+] New sender: ${senderKey}`);
    console.log(`    Saving to: ${sessionFile}\n`);
  }

  // Parse frame
  let frame;
  try {
    frame = JSON.parse(msg.toString());
  } catch {
    console.warn(`[!] Invalid JSON from ${senderKey}`);
    return;
  }

  // Enrich with server metadata
  frame.serverReceivedAt = Date.now();
  frame.sender = senderKey;

  // Write to .jsonl
  sender.stream.write(JSON.stringify(frame) + "\n");
  sender.frameCount++;

  // Console output
  if (VERBOSE) {
    console.log(`[${senderKey}] ${JSON.stringify(frame)}`);
  } else {
    const parts = [];
    if (frame.pose) {
      const jointCount = Object.keys(frame.pose.joints || {}).length;
      parts.push(`pose(${jointCount}j)`);
    }
    if (frame.motion) parts.push("motion");
    if (frame.audio) {
      const a = frame.audio;
      parts.push(`audio(rms:${a.rmsDB?.toFixed(1)},peak:${a.peakDB?.toFixed(1)})`);
    }
    if (frame.prediction) {
      parts.push(`pred:[${frame.prediction.gesture}](${(frame.prediction.confidence * 100).toFixed(0)}%)`);
    }
    const label = parts.join(" | ") || "(empty frame)";
    const fps = sender.frameCount / ((Date.now() - sender.firstSeen) / 1000);
    console.log(`[${senderKey}] #${sender.frameCount} ${label}  ~${fps.toFixed(0)}fps`);
  }
});

server.on("error", (err) => {
  console.error(`UDP server error: ${err.message}`);
  server.close();
});

server.bind(PORT);

// Graceful shutdown with summary
process.on("SIGINT", () => {
  console.log("\n");
  console.log("=" .repeat(50));
  console.log("  Training Session Summary");
  console.log("=" .repeat(50));

  let totalFrames = 0;
  for (const [key, sender] of senders) {
    sender.stream.end();
    const duration = ((Date.now() - sender.firstSeen) / 1000).toFixed(1);
    const avgFps = (sender.frameCount / (duration || 1)).toFixed(1);
    console.log(`  ${key}`);
    console.log(`    Frames: ${sender.frameCount}  Duration: ${duration}s  Avg: ${avgFps} fps`);
    console.log(`    File:   ${sender.file}`);
    totalFrames += sender.frameCount;
  }

  console.log(`  Total: ${totalFrames} frames from ${senders.size} sender(s)`);
  console.log("=" .repeat(50));

  server.close(() => process.exit(0));
});
