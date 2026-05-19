const dgram = require('dgram');
const server = dgram.createSocket('udp4');

const PORT = process.env.PORT || 8888;
const HOST = process.env.HOST || '0.0.0.0';

let packetCount = 0;
let lastTime = Date.now();

function formatVector(values, labels) {
  return labels.map((label, i) => {
    const v = values[i];
    return v !== undefined ? `  ${label.padEnd(16)} ${v.toFixed(4)}` : null;
  }).filter(Boolean).join('\n');
}

server.on('message', (msg, rinfo) => {
  packetCount++;
  const now = Date.now();
  const elapsed = ((now - lastTime) / 1000).toFixed(1);
  lastTime = now;

  try {
    const data = JSON.parse(msg.toString());
    const values = data.prediction || [];

    const lines = [
      '\n' + '─'.repeat(55),
      `📦 Packet #${packetCount}  │  from ${rinfo.address}:${rinfo.port}  │  +${elapsed}s`,
      '─'.repeat(55),
    ];

    if (values.length >= 10) {
      // Mock format: [cx, cy, cz, height, spread, xMin, xMax, yMin, yMax, jointCount]
      lines.push('  🧍 Body Metrics:');
      lines.push(`  ${'centroid'.padEnd(16)} (${values[0].toFixed(3)}, ${values[1].toFixed(3)}, ${values[2].toFixed(3)})`);
      lines.push(`  ${'body height'.padEnd(16)} ${values[3].toFixed(3)} m`);
      lines.push(`  ${'spread (width)'.padEnd(16)} ${values[4].toFixed(3)} m`);
      lines.push(`  ${'x range'.padEnd(16)} [${values[5].toFixed(3)}, ${values[6].toFixed(3)}]`);
      lines.push(`  ${'y range'.padEnd(16)} [${values[7].toFixed(3)}, ${values[8].toFixed(3)}]`);
      lines.push(`  ${'joint count'.padEnd(16)} ${values[9]}`);
    } else if (values.length > 0) {
      lines.push(`  Values (${values.length}): [${values.map(v => v.toFixed(4)).join(', ')}]`);
    } else {
      lines.push('  ⚠️  Empty prediction');
    }

    lines.push('─'.repeat(55));
    console.log(lines.join('\n'));
  } catch (err) {
    console.log(`\n⚠️  Packet #${packetCount}: ${msg.length}B raw (not JSON)`);
    console.log(`   hex: ${msg.toString('hex').slice(0, 80)}...`);
  }
});

server.on('listening', () => {
  const addr = server.address();
  console.log('═'.repeat(55));
  console.log('  🎮 game_server_app — UDP Prediction Receiver');
  console.log('═'.repeat(55));
  console.log(`  Listening:  udp://${addr.address}:${addr.port}`);
  console.log(`  Ready for game_client_app predictions...`);
  console.log('═'.repeat(55));
});

server.on('error', (err) => {
  console.error(`Server error: ${err.message}`);
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is in use. Try: PORT=9999 node server.js`);
  }
  process.exit(1);
});

server.bind(PORT, HOST);

process.on('SIGINT', () => {
  console.log(`\n\nReceived ${packetCount} packets total. Shutting down.`);
  server.close();
  process.exit(0);
});
