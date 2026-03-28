const { app, BrowserWindow } = require('electron');
const path = require('path');
const bridge = require('./bridge.cjs');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 800,
    title: 'Paloma Morse',
    backgroundColor: '#0b0e14', 
    show: false, 
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  const indexPath = path.join(__dirname, 'dist', 'index.html');
  mainWindow.loadURL(`file://${indexPath}`);

  mainWindow.once('ready-to-show', () => {
    mainWindow.setTitle('Paloma Morse');
    mainWindow.show();
  });

  // Enable standard DevTools shortcuts for profiling
  mainWindow.webContents.on('before-input-event', (event, input) => {
    if (input.control && input.shift && input.key.toLowerCase() === 'i') {
      mainWindow.webContents.openDevTools();
    }
    if (input.meta && input.alt && input.key.toLowerCase() === 'i') {
      mainWindow.webContents.openDevTools();
    }
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
  app.quit();
});

app.on('activate', function () {
  if (mainWindow === null) createWindow();
});

app.on('will-quit', () => {
  console.log('[Main] Cleaning up engine...');
  bridge.stop();
});
