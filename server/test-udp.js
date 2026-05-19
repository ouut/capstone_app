const dgram = require("dgram");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

const RECEIVER_PORT = 9876; // Use a non-default port for test isolation
const TEST_TIMEOUT = 5000;

let passed = 0;
let failed = 0;

function assert(label, condition) {
  if (condition) {
    console.log(`  \x1b[32m✓\x1b[0m ${label}`);
    passed++;
  } else {
    console.error(`  \x1b[31m✗\x1b[0m ${label}`);
    failed++;
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function run() {
  console.log("Testing UDP receiver...\n");

  // Start the receiver in a child process
  const receiver = spawn("node", ["udp-receiver.js"], {
    cwd: __dirname,
    env: { ...process.env, UDP_PORT: String(RECEIVER_PORT) },
    stdio: ["ignore", "pipe", "pipe"],
  });

  const received = [];
  receiver.stdout.on("data", (chunk) => {
    const lines = chunk.toString().split("\n").filter(Boolean);
    for (const line of lines) {
      if (line.startsWith("[")) {
        received.push(line);
        console.log("  recv:", line.substring(0, 100));
      }
    }
  });
  receiver.stderr.on("data", (chunk) => {
    console.error("  receiver stderr:", chunk.toString().trim());
  });

  // Wait for receiver to start
  await sleep(800);

  // Test 1: Single frame
  console.log("\n--- Single frame ---");
  const sender = dgram.createSocket("udp4");
  const frame1 = Buffer.from(JSON.stringify({
    timestamp: 1.0,
    pose: { joints: { right_wrist: { x: 0.5, y: 0.3, confidence: 0.9 } } },
    motion: null,
    audio: null,
    prediction: null,
  }));
  sender.send(frame1, RECEIVER_PORT, "127.0.0.1");
  await sleep(300);
  assert("Single frame received", received.length >= 1);

  // Test 2: Multiple frames from same sender
  console.log("\n--- Multiple frames ---");
  for (let i = 0; i < 3; i++) {
    const f = Buffer.from(JSON.stringify({
      timestamp: 1.0 + i * 0.033,
      pose: null,
      motion: { acceleration: { x: 0.1, y: 0.2, z: -1 }, rotationRate: { x: 0, y: 0, z: 0 }, attitude: { x: 0, y: 0, z: 0, w: 1 }, gravity: { x: 0, y: 0, z: -1 }, userAcceleration: { x: 0, y: 0, z: 0 } },
      audio: null,
      prediction: null,
    }));
    sender.send(f, RECEIVER_PORT, "127.0.0.1");
  }
  await sleep(300);
  assert("All 4 frames received", received.length >= 4);

  // Test 3: Invalid JSON handled
  console.log("\n--- Invalid JSON ---");
  const before = received.length;
  sender.send(Buffer.from("not json {{{"), RECEIVER_PORT, "127.0.0.1");
  await sleep(300);
  assert("Invalid JSON does not crash receiver", received.length === before);

  // Test 4: JSONL file created
  console.log("\n--- JSONL output ---");
  const dataDir = path.join(__dirname, "training_data");
  const files = fs.readdirSync(dataDir).filter(f => f.endsWith(".jsonl"));
  assert("Training data directory created", files.length >= 1);

  const latestFile = path.join(dataDir, files.sort().pop());
  const content = fs.readFileSync(latestFile, "utf-8");
  const lines = content.split("\n").filter(Boolean);
  assert("JSONL has entries", lines.length >= 4);
  const parsed = JSON.parse(lines[0]);
  assert("JSONL entry has serverReceivedAt", typeof parsed.serverReceivedAt === "number");
  assert("JSONL entry has sender field", typeof parsed.sender === "string" && parsed.sender.includes("127.0.0.1"));

  // Cleanup
  sender.close();
  receiver.kill();
  await sleep(200);

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

run().catch((e) => {
  console.error("Test error:", e);
  process.exit(1);
});
