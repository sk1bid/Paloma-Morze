const { app, BrowserWindow, ipcMain, powerMonitor, dialog, Menu, MenuItem } = require('electron');

const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs');
const bridge = require('./bridge.cjs');
const { createControllerBroker } = require('./task5-dev-controller.cjs');
const task5Development = process.argv.includes('--task5-dev');
if (task5Development) {
  const developmentData = `${app.getPath('userData')}-task5-dev`;
  fs.mkdirSync(developmentData, { recursive: true });
  app.setPath('userData', developmentData);
  app.setPath('sessionData', developmentData);
  process.env.PALOMA_AUDIO_PORT = '8085';
}
const task5Query = task5Development ? '?task5dev=1' : '';

let mainWindow;
let controllerWindow = null;
let controllerBroker = null;

function loadRenderer(window, query) {
  const indexPath = path.join(__dirname, 'dist', 'index.html');
  if (!app.isPackaged) {
    const port = process.env.VITE_PORT || 5173;
    window.loadURL(`http://localhost:${port}${query}`).catch(() => window.loadURL(`file://${indexPath}${query}`));
  } else window.loadURL(`file://${indexPath}${query}`);
}
function showTask5Controller() {
  if (!task5Development || !mainWindow || mainWindow.isDestroyed()) return;
  if (controllerWindow && !controllerWindow.isDestroyed()) { controllerWindow.show(); controllerWindow.focus(); return; }
  controllerWindow = new BrowserWindow({
    width: 720, height: 470, minWidth: 600, minHeight: 380,
    title: 'DEV · Управление задачей №5', backgroundColor: '#0b0e14', show: false,
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  });
  loadRenderer(controllerWindow, '?task5dev=1&task5controller=1');
  controllerWindow.once('ready-to-show', () => controllerWindow?.show());
  // Destroying this renderer clears only its automatic-preview timer. The main
  // session, its selected stage, and manually started audio remain untouched.
  controllerWindow.on('closed', () => { controllerWindow = null; });
}
function installTask5DevelopmentMenu() {
  const item = { label: 'DEV', submenu: [{ label: 'Показать управление задачей №5', accelerator: 'CmdOrCtrl+Alt+D', click: showTask5Controller }] };
  const menu = Menu.getApplicationMenu();
  if (menu) { menu.append(new MenuItem(item)); Menu.setApplicationMenu(menu); }
  else Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
    { role: 'editMenu' }, { role: 'viewMenu' }, { role: 'windowMenu' }, item
  ]));
}

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
  ipcMain.handle('get-app-version', () => app.getVersion());
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

  loadRenderer(mainWindow, task5Query);
  if (!app.isPackaged) {
    // Open DevTools by default in dev mode for easier debugging
    mainWindow.webContents.openDevTools();
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow.setTitle('Paloma Morse');
    mainWindow.show();
    if (task5Development) showTask5Controller();

    // Check for updates 3 seconds after window is ready
    if (app.isPackaged && !task5Development) {
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
    if (controllerWindow && !controllerWindow.isDestroyed()) controllerWindow.close();
    mainWindow = null;
  });
}

// macOS: an app launched from a DMG or Downloads runs from a read-only
// translocated copy, and Squirrel cannot install updates over it.
// Offer to move it into /Applications; on success Electron relaunches it there.
function offerMoveToApplications() {
  if (task5Development) return false;
  if (process.platform !== 'darwin' || !app.isPackaged || app.isInApplicationsFolder()) return false;

  const ru = app.getLocale().toLowerCase().startsWith('ru');
  const choice = dialog.showMessageBoxSync({
    type: 'question',
    buttons: ru ? ['Переместить', 'Не сейчас'] : ['Move to Applications', 'Not Now'],
    defaultId: 0,
    cancelId: 1,
    message: ru ? 'Переместить Paloma Morse в папку «Программы»?' : 'Move Paloma Morse to the Applications folder?',
    detail: ru
      ? 'Приложение запущено не из «Программ». Так автоматические обновления не смогут установиться.'
      : 'The app is not running from Applications, so automatic updates cannot be installed.',
  });
  if (choice !== 0) return false;

  try {
    const moved = app.moveToApplicationsFolder();
    console.log(`[Main] Move to Applications: ${moved ? 'done, relaunching' : 'not moved'}`);
    return moved;
  } catch (err) {
    console.error('[Main] Move to Applications failed:', err.message);
    return false;
  }
}

app.on('ready', () => {
  console.log(`[Main] Starting Paloma Morse (Packaged: ${app.isPackaged})`);
  if (offerMoveToApplications()) return; // relaunching from /Applications
  bridge.start(app.isPackaged);
  if (!task5Development) setupAutoUpdater();
  if (task5Development) controllerBroker = createControllerBroker({ ipcMain, getMainWindow: () => mainWindow, getControllerWindow: () => controllerWindow });
  createWindow();
  if (task5Development) installTask5DevelopmentMenu();

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
  controllerBroker?.dispose();
  console.log('[Main] Cleaning up engine...');
  bridge.stop();
});
