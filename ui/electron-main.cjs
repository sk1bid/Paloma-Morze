const { app, BrowserWindow } = require('electron');
const path = require('path');
const bridge = require('./bridge.cjs');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 800,
    title: 'Paloma Morse',
    backgroundColor: '#0b0e14', // Match the UI background
    show: false, // Don't show until ready-to-show
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  const indexPath = path.join(__dirname, 'dist', 'index.html');
  mainWindow.loadFile(indexPath);

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  mainWindow.on('closed', function () {
    mainWindow = null;
  });
}

app.on('ready', () => {
  console.log(`[Main] Starting Paloma Morse (Packaged: ${app.isPackaged})`);
  bridge.start(app.isPackaged);
  createWindow();
});

app.on('window-all-closed', function () {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', function () {
  if (mainWindow === null) createWindow();
});

app.on('will-quit', () => {
  console.log('[Main] Cleaning up engine...');
  bridge.stop();
});
