const { spawn } = require('child_process');
const { WebSocketServer } = require('ws');
const path = require('path');
const fs = require('fs');

let activeEngine = null;
let isKeyConnected = false;
let wss = null;

function startEngine(isProduction = false, extraArgs = []) {
    if (wss) return; // Already started

    wss = new WebSocketServer({ port: 8080 });
    console.log('[Bridge] WebSocket server started on port 8080');

    // Linux-specific audio unmute (e.g. for Server/Mac Pro setups)
    if (process.platform === 'linux') {
        try {
            const { execSync } = require('child_process');
            console.log('[Bridge] Attempting to unmute ALSA channels...');
            execSync("amixer -c 0 sset 'Master' 100% unmute", { stdio: 'ignore' });
            execSync("amixer -c 0 sset 'Speaker' 100% unmute", { stdio: 'ignore' });
            execSync("amixer -c 0 sset 'Headphone' 100% unmute", { stdio: 'ignore' });
        } catch (e) {
            console.log('[Bridge] ALSA unmute failed or amixer missing. Continuing...');
        }
    }

    wss.on('connection', (ws) => {
        console.log('[Bridge] UI Client connected');
        ws.send(isKeyConnected ? 'STATUS:CONNECTED' : 'STATUS:DISCONNECTED');
        ws.on('message', (message) => {
            const str = message.toString();
            if (activeEngine) {
                if (str.startsWith('F') || str.startsWith('V')) {
                    activeEngine.stdin.write(str + '\n');
                }
            }
        });
    });

    const isWin = process.platform === 'win32';
    const appName = isWin ? 'morze_app.exe' : 'morze_app';
    
    // Resolve engine path
    let enginePath;
    if (isProduction) {
        // In production, we look in app.asar.unpacked/native/ (pre-built by CI)
        const resourcesPath = process.resourcesPath || path.join(__dirname, '..');
        enginePath = path.join(resourcesPath, 'app.asar.unpacked', 'native', appName);
        console.log(`[Bridge] Production mode. Looking for engine at: ${enginePath}`);
    } else {
        // In development, we look in the ui/native/ folder
        enginePath = path.join(__dirname, 'native', appName);
        console.log(`[Bridge] Development mode. Looking for engine at: ${enginePath}`);
    }

    const launch = () => {
        console.log(`[Bridge] Launching engine: ${enginePath} with args: ${extraArgs.join(' ')}`);
        activeEngine = spawn(enginePath, extraArgs, {
            cwd: path.dirname(enginePath)
        });

        activeEngine.stdout.on('data', (data) => {
            const str = data.toString().trim();
            str.split('\n').forEach(line => {
                const l = line.trim();
                if (l === '1' || l === '0') {
                    broadcast(l);
                } else if (l.includes('[Engine] Connected')) {
                    isKeyConnected = true;
                    broadcast('STATUS:CONNECTED');
                } else if (l.includes('Disconnected') || l.includes('Reconnecting') || l.includes('Port lost')) {
                    isKeyConnected = false;
                    broadcast('STATUS:DISCONNECTED');
                } else if (l.includes('Permission denied')) {
                    broadcast('ERROR:PERMISSION_DENIED');
                }
                console.log(`[Engine]: ${l}`);
            });
        });

        activeEngine.stderr.on('data', (data) => console.error(`[Engine Error]: ${data}`));
        activeEngine.on('close', (code) => {
            console.log(`[Bridge] Engine exited with code ${code}`);
            activeEngine = null;
        });
    };

    // Auto-build in development if binary is missing
    if (!isProduction && !fs.existsSync(enginePath)) {
        console.log('[Bridge] Engine binary missing in dev. Building via g++...');
        const engineSource = path.join(__dirname, 'native', 'morze_engine_v2.cpp');
        let buildArgs;
        if (process.platform === 'darwin') {
            buildArgs = [engineSource, '-I', path.dirname(engineSource), '-o', enginePath, '-lpthread', '-lm', '-ldl', '-framework', 'CoreAudio', '-framework', 'AudioUnit', '-framework', 'CoreFoundation'];
        } else if (isWin) {
            buildArgs = [engineSource, '-I', path.dirname(engineSource), '-o', enginePath, '-lpthread', '-lm', '-ldl', '-lwinmm'];
        } else {
            buildArgs = [engineSource, '-I', path.dirname(engineSource), '-o', enginePath, '-lpthread', '-lm', '-ldl', '-lasound'];
        }
        
        const build = spawn('g++', buildArgs);
        build.on('close', (code) => {
            if (code === 0) launch();
            else console.error('[Bridge] Build failed!');
        });
    } else {
        launch();
    }
}

function stopEngine() {
    if (activeEngine) {
        activeEngine.kill();
        activeEngine = null;
    }
    isKeyConnected = false;
    if (wss) {
        wss.close();
        wss = null;
    }
}

function broadcast(data) {
    if (!wss) return;
    wss.clients.forEach(client => {
        if (client.readyState === 1) client.send(data);
    });
}

module.exports = { start: startEngine, stop: stopEngine };

