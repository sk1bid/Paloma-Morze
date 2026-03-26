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
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  // Load the Vite dev server for now (we can bundle it later)
  mainWindow.loadURL('http://localhost:5173');

  mainWindow.on('closed', function () {
    mainWindow = null;
  });
}

app.on('ready', () => {
  // 1. Start the Bridge and Engine
  bridgeProcess = spawn('node', [path.join(__dirname, 'bridge.cjs')], {
    cwd: __dirname,
    stdio: 'inherit'
  });

  // 2. Start Vite Dev Server
  const viteProcess = spawn('npm', ['run', 'dev'], {
    cwd: __dirname,
    stdio: 'inherit'
  });

  // Wait a moment for Vite to start before opening the window
  setTimeout(createWindow, 2000);
});

app.on('window-all-closed', function () {
  if (bridgeProcess) bridgeProcess.kill();
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', function () {
  if (mainWindow === null) createWindow();
});

app.on('will-quit', () => {
  if (bridgeProcess) bridgeProcess.kill();
});
