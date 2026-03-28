const { spawn } = require('child_process');
const { WebSocketServer } = require('ws');
const path = require('path');
const fs = require('fs');

const wss = new WebSocketServer({ port: 8080 });
console.log('WebSocket server for Morse UI started on port 8080');

let activeEngine = null;
let isKeyConnected = false;

wss.on('connection', (ws) => {
    console.log('[Bridge] UI Client connected');
    ws.send(isKeyConnected ? 'STATUS:CONNECTED' : 'STATUS:DISCONNECTED');
    ws.on('message', (message) => {
        const str = message.toString();
        console.log(`[Bridge] Received from UI: ${str}`);
        if (activeEngine) {
            if (str.startsWith('F') || str.startsWith('V')) {
                activeEngine.stdin.write(str + '\n');
            } else if (!isNaN(str) && str.trim() !== '') {
                // Backwards compatibility for plain numbers
                activeEngine.stdin.write('F' + str + '\n');
            }
        }
    });
    ws.on('close', () => console.log('[Bridge] UI Client disconnected'));
});

function cleanup() {
    if (activeEngine) {
        console.log('[Bridge] Killing C++ engine...');
        activeEngine.kill();
    }
    process.exit();
}

process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);
process.on('exit', () => {
    if (activeEngine) activeEngine.kill();
});

function broadcast(data) {
    wss.clients.forEach(client => {
        if (client.readyState === 1) {
            client.send(data);
        }
    });
}

// Сборка C++ движка (Кроссплатформенная версия v2)
console.log('[Bridge] Building C++ engine (v2 miniaudio)...');
const isNativeDir = fs.existsSync(path.join(__dirname, 'native', 'morze_engine_v2.cpp'));
const engineSource = isNativeDir ? path.join('native', 'morze_engine_v2.cpp') : 'morze_engine_v2.cpp';

const isWin = process.platform === 'win32';
const appName = isWin ? 'morze_app.exe' : 'morze_app';

let buildArgs;
if (process.platform === 'darwin') {
    buildArgs = [engineSource, '-I', 'native', '-o', appName, '-lpthread', '-lm', '-ldl', '-framework', 'CoreAudio', '-framework', 'AudioUnit', '-framework', 'CoreFoundation'];
} else if (isWin) {
    // Windows build (assuming MinGW/GCC)
    buildArgs = [engineSource, '-I', 'native', '-o', appName, '-lpthread', '-lm', '-ldl', '-lwinmm'];
} else {
    // Linux build
    buildArgs = [engineSource, '-I', 'native', '-o', appName, '-lpthread', '-lm', '-ldl'];
}

const build = spawn('g++', buildArgs, {
    cwd: __dirname
});

build.stderr.on('data', (data) => console.error(`[Build Error]: ${data}`));

build.on('close', (code) => {
    if (code !== 0) {
        console.error('[Bridge] C++ Build failed!');
        process.exit(1);
    }
    console.log(`[Bridge] C++ Engine built (${appName}). Launching...`);
    
    activeEngine = spawn(isWin ? `./${appName}` : `./${appName}`, [], {
        cwd: __dirname
    });

    activeEngine.stdout.on('data', (data) => {
        const str = data.toString().trim();
        const lines = str.split('\n');
        lines.forEach(line => {
            const l = line.trim();
            if (l === '1' || l === '0') {
                broadcast(l);
            } else if (l.includes('[Engine] Connected to')) {
                isKeyConnected = true;
                broadcast('STATUS:CONNECTED');
            } else if (l.includes('disappeared') || l.includes('Connection lost')) {
                isKeyConnected = false;
                broadcast('STATUS:DISCONNECTED');
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
