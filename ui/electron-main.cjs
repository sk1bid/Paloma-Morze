const { app, BrowserWindow } = require('electron');
const { spawn } = require('child_process');
const path = require('path');

let mainWindow;
let bridgeProcess;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 800,
    title: 'Paloma Morse',
    backgroundColor: '#0b0e14', // Match the UI background
    show: false, // Don't show until ready-to-show
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true
    }
  });

  // Load the production build
  const indexPath = path.join(__dirname, 'dist', 'index.html');
  mainWindow.loadFile(indexPath);

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  mainWindow.on('closed', function () {
    mainWindow = null;
  });
}

// Ensure children are killed on quit
function cleanup() {
  if (bridgeProcess) {
    console.log('[Main] Killing bridge process...');
    bridgeProcess.kill('SIGTERM');
  }
}

app.on('ready', () => {
  // 1. Start the Bridge and Engine
  // On production, we assume bridge.cjs and morze_app are in the right places
  bridgeProcess = spawn('node', [path.join(__dirname, 'bridge.cjs')], {
    cwd: __dirname,
    stdio: 'inherit'
  });

  createWindow();
});

app.on('window-all-closed', function () {
  app.quit();
});

app.on('activate', function () {
  if (mainWindow === null) createWindow();
});

app.on('will-quit', cleanup);
app.on('before-quit', cleanup);
