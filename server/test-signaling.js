// Verify the signaling server by simulating two peers exchanging SDP + ICE + data.
// Usage: node test-signaling.js

const WebSocket = require("ws");

const SIGNALING_URL = process.env.URL || "ws://localhost:3000/signaling";
const TEST_TIMEOUT = 5000;
let passed = 0;
let failed = 0;

function assert(label, condition) {
  if (condition) {
    console.log(`  ✓ ${label}`);
    passed++;
  } else {
    console.error(`  ✗ ${label}`);
    failed++;
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function connect(id) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(SIGNALING_URL);
    ws.on("open", () => {
      ws.send(JSON.stringify({ type: "register", clientId: id }));
    });
    ws.on("error", reject);
    let registered = false;
    ws.on("message", (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === "registered") {
        registered = true;
        resolve(ws);
      }
    });
    setTimeout(() => {
      if (!registered) reject(new Error(`Timeout waiting for ${id} to register`));
    }, TEST_TIMEOUT);
  });
}

async function waitForMessage(ws, type) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timeout waiting for ${type}`)), TEST_TIMEOUT);
    ws.on("message", function handler(raw) {
      const msg = JSON.parse(raw.toString());
      if (msg.type === type) {
        clearTimeout(timer);
        ws.removeListener("message", handler);
        resolve(msg);
      }
    });
  });
}

async function run() {
  console.log("Testing signaling server at", SIGNALING_URL);

  let phone, game;

  try {
    // Test 1: Connect & register two clients
    console.log("\n--- Registration ---");
    phone = await connect("phone_001");
    assert("Phone registers with ID 'phone_001'", phone.readyState === WebSocket.OPEN);

    await sleep(200);
    game = await connect("game_server");
    assert("Game server registers", game.readyState === WebSocket.OPEN);

    // Test 2: Phone sends offer -> game receives it
    console.log("\n--- SDP Offer Relay ---");
    const offerSdp = "v=0\r\no=- ...\r\n...";
    phone.send(JSON.stringify({ type: "offer", clientId: "phone_001", sdp: offerSdp }));

    const receivedOffer = await waitForMessage(game, "offer");
    assert("Game receives offer from phone", receivedOffer.sdp === offerSdp);
    assert("Offer has correct type", receivedOffer.type === "offer");

    // Test 3: Game sends answer -> phone receives it
    console.log("\n--- SDP Answer Relay ---");
    const answerSdp = "v=0\r\no=- ... answer ...";
    game.send(JSON.stringify({ type: "answer", clientId: "game_server", sdp: answerSdp }));

    const receivedAnswer = await waitForMessage(phone, "answer");
    assert("Phone receives answer from game", receivedAnswer.sdp === answerSdp);

    // Test 4: ICE candidate exchange
    console.log("\n--- ICE Candidate Relay ---");
    const iceMsg = {
      type: "ice",
      clientId: "phone_001",
      candidate: "candidate:1 1 UDP 2130706431 192.168.1.1 54321 typ host",
      sdpMid: "0",
      sdpMLineIndex: 0,
    };
    phone.send(JSON.stringify(iceMsg));

    const receivedIce = await waitForMessage(game, "ice");
    assert("Game receives ICE candidate", receivedIce.candidate === iceMsg.candidate);
    assert("ICE sdpMid preserved", receivedIce.sdpMid === "0");
    assert("ICE sdpMLineIndex preserved", receivedIce.sdpMLineIndex === 0);

    // Test 5: Data relay
    console.log("\n--- Data Relay ---");
    const payload = JSON.stringify({ joints: { wrist: { x: 0.5, y: 0.3 } } });
    const b64 = Buffer.from(payload).toString("base64");
    phone.send(JSON.stringify({ type: "data", clientId: "phone_001", candidate: b64 }));

    const receivedData = await waitForMessage(game, "data");
    const decoded = Buffer.from(receivedData.candidate, "base64").toString();
    assert("Game receives data relay", decoded === payload);

    // Test 6: Broadcast excludes sender
    console.log("\n--- No Self-Receive ---");
    let selfReceived = false;
    game.on("message", function selfCheck(raw) {
      const msg = JSON.parse(raw.toString());
      if (msg.type === "self-test") selfReceived = true;
    });
    game.send(JSON.stringify({ type: "self-test", clientId: "game_server" }));
    await sleep(300);
    assert("Sender does not receive its own message", !selfReceived);

    // Test 7: Invalid JSON is handled
    console.log("\n--- Error Handling ---");
    phone.send("not valid json {{{");
    await sleep(200);
    assert("Invalid JSON does not crash server", phone.readyState === WebSocket.OPEN);
  } catch (e) {
    console.error("\n  TEST ERROR:", e.message);
    failed++;
  } finally {
    // Cleanup
    if (phone) phone.close();
    if (game) game.close();
  }

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

run();
