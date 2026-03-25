const { spawn } = require('child_process');
const { WebSocketServer } = require('ws');
const path = require('path');

const wss = new WebSocketServer({ port: 8080 });
console.log('WebSocket server for Morse UI started on port 8080');

let activeEngine = null;

wss.on('connection', (ws) => {
    console.log('[Bridge] UI Client connected');
    ws.on('message', (message) => {
        const str = message.toString();
        console.log(`[Bridge] Received from UI: ${str}`);
        if (activeEngine && !isNaN(str)) {
            activeEngine.stdin.write(str + '\n');
        }
    });
    ws.on('close', () => console.log('[Bridge] UI Client disconnected'));
});

function broadcast(data) {
    wss.clients.forEach(client => {
        if (client.readyState === 1) {
            client.send(data);
        }
    });
}

// Сборка C++ движка
console.log('[Bridge] Building C++ engine...');
const build = spawn('g++', ['morze_engine.cpp', '-o', 'morze_app', '-framework', 'AVFoundation', '-framework', 'Foundation', '-ObjC++', '-fobjc-arc'], {
    cwd: path.join(__dirname, '..')
});

build.stderr.on('data', (data) => console.error(`[Build Error]: ${data}`));

build.on('close', (code) => {
    if (code !== 0) {
        console.error('[Bridge] C++ Build failed!');
        process.exit(1);
    }
    console.log('[Bridge] C++ Engine built. Launching...');
    
    activeEngine = spawn('./morze_app', [], {
        cwd: path.join(__dirname, '..')
    });

    activeEngine.stdout.on('data', (data) => {
        const str = data.toString().trim();
        const lines = str.split('\n');
        lines.forEach(line => {
            const l = line.trim();
            if (l === '1' || l === '0') {
                broadcast(l);
            }
            console.log(`[Engine]: ${l}`);
        });
    });

    activeEngine.stderr.on('data', (data) => {
        console.error(`[Engine Error]: ${data}`);
    });

    activeEngine.on('close', (code) => {
        console.log(`[Bridge] Engine exited with code ${code}`);
        activeEngine = null;
    });
});
