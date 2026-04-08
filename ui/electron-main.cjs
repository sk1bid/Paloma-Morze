const { app, BrowserWindow, ipcMain, powerMonitor } = require('electron');

const { autoUpdater } = require('electron-updater');
const path = require('path');
const bridge = require('./bridge.cjs');

let mainWindow;

// --- Auto Updater Configuration ---
autoUpdater.autoDownload = false;
autoUpdater.autoInstallOnAppQuit = true;
autoUpdater.logger = null; // Suppress default logging

// Prevent update errors from crashing the app
process.on('uncaughtException', (err) => {
  console.error('[Main] Uncaught exception:', err.message);
});
process.on('unhandledRejection', (err) => {
  console.error('[Main] Unhandled rejection:', err);
});

function sendUpdateStatus(status, data = {}) {
  if (mainWindow && mainWindow.webContents) {
    mainWindow.webContents.send('update-status', { status, ...data });
  }
}

function setupAutoUpdater() {
  autoUpdater.allowPrerelease = true;
  autoUpdater.on('checking-for-update', () => {
    console.log('[Updater] Checking for updates...');
    sendUpdateStatus('checking');
  });

  autoUpdater.on('update-available', (info) => {
    console.log('[Updater] Update available:', info.version);
    sendUpdateStatus('available', { version: info.version });
  });

  autoUpdater.on('update-not-available', () => {
    console.log('[Updater] App is up to date.');
    sendUpdateStatus('uptodate');
  });

  autoUpdater.on('download-progress', (progress) => {
    sendUpdateStatus('downloading', { percent: Math.round(progress.percent) });
  });

  autoUpdater.on('update-downloaded', (info) => {
    console.log('[Updater] Update downloaded:', info.version);
    sendUpdateStatus('downloaded', { version: info.version });
  });

  autoUpdater.on('error', (err) => {
    console.error('[Updater] Error:', err.message);
    sendUpdateStatus('error', { message: err.message });
  });

  // IPC handlers from renderer
  ipcMain.on('check-for-update', () => {
    autoUpdater.checkForUpdates();
  });

  ipcMain.on('download-update', () => {
    autoUpdater.downloadUpdate();
  });

  ipcMain.on('install-update', () => {
    autoUpdater.quitAndInstall();
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 850,
    title: 'Paloma Morse',
    backgroundColor: '#0b0e14',
    show: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  if (!app.isPackaged) {
    // Development mode: Connect to Vite dev server
    mainWindow.loadURL('http://localhost:5173').catch(() => {
      // Fallback if Vite is not running
      const indexPath = path.join(__dirname, 'dist', 'index.html');
      mainWindow.loadURL(`file://${indexPath}`);
    });
    // Open DevTools by default in dev mode for easier debugging
    mainWindow.webContents.openDevTools();
  } else {
    // Production mode: Load built files
    const indexPath = path.join(__dirname, 'dist', 'index.html');
    mainWindow.loadURL(`file://${indexPath}`);
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow.setTitle('Paloma Morse');
    mainWindow.show();

    // Check for updates 3 seconds after window is ready
    if (app.isPackaged) {
      setTimeout(() => {
        console.log(`[Updater] Current version: ${app.getVersion()}`);
        autoUpdater.checkForUpdates().catch(err => {
          console.log('[Updater] Auto-check failed:', err.message);
        });
      }, 3000);
    }
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
  setupAutoUpdater();
  createWindow();

  // Listen for system sleep/wake to re-sync or reconnect if needed
  powerMonitor.on('resume', () => {
    console.log('[Main] System resumed from sleep');
    if (mainWindow && mainWindow.webContents) {
      mainWindow.webContents.send('power-resume');
    }
  });

  powerMonitor.on('suspend', () => {
    console.log('[Main] System going to sleep');
    if (mainWindow && mainWindow.webContents) {
      mainWindow.webContents.send('power-suspend');
    }
  });
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
