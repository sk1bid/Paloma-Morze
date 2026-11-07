const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { EventEmitter } = require('node:events');

function launch(argumentsList) {
  const operations = [];
  const app = { getPath: () => '/profile/Paloma', setPath: (key, value) => operations.push(['setPath', key, value]), on: jest.fn() };
  const process = { argv: argumentsList, env: {}, on: jest.fn() };
  const context = {
    console, process,
    require: name => {
      if (name === 'electron') return { app };
      if (name === 'electron-updater') return { autoUpdater: {} };
      if (name === 'path') return path;
      if (name === 'fs') return { mkdirSync: (...args) => operations.push(['mkdir', ...args]) };
      if (name === './bridge.cjs') return {};
      if (name === './task5-dev-controller.cjs') return { createControllerBroker: jest.fn() };
      throw new Error(name);
    }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../electron-main.cjs'), 'utf8'), context);
  return { operations, process };
}
test('developer launch creates its isolated profile before selecting userData/sessionData and uses another audio port', () => {
  const result = launch(['electron', '--task5-dev']);
  expect(result.operations).toEqual([
    ['mkdir', '/profile/Paloma-task5-dev', { recursive: true }],
    ['setPath', 'userData', '/profile/Paloma-task5-dev'],
    ['setPath', 'sessionData', '/profile/Paloma-task5-dev']
  ]);
  expect(result.process.env.PALOMA_AUDIO_PORT).toBe('8085');
});
test('ordinary launch keeps its normal profile and audio port', () => {
  const result = launch(['electron']);
  expect(result.operations).toEqual([]);
  expect(result.process.env.PALOMA_AUDIO_PORT).toBeUndefined();
});

function windowHost(args) {
  const windows = [], menu = { current: null };
  class Window extends EventEmitter {
    constructor(options) {
      super(); this.options = options; this.destroyed = false;
      this.webContents = new EventEmitter();
      this.webContents.send = jest.fn(); this.webContents.isDestroyed = () => this.destroyed;
      this.webContents.openDevTools = jest.fn();
      this.show = jest.fn(); this.focus = jest.fn(); this.setTitle = jest.fn();
      this.loadURL = jest.fn(() => Promise.resolve()); windows.push(this);
    }
    isDestroyed() { return this.destroyed; }
    close() { this.destroyed = true; this.emit('closed'); }
  }
  const app = new EventEmitter();
  Object.assign(app, { isPackaged: true, getPath: () => '/profile/Paloma', setPath: jest.fn(), isInApplicationsFolder: () => true, getVersion: () => '0.4.20', quit: jest.fn() });
  const ipcMain = new EventEmitter(); ipcMain.handle = jest.fn();
  const bridge = { start: jest.fn(), stop: jest.fn() };
  const electron = {
    app, BrowserWindow: Window, ipcMain, powerMonitor: new EventEmitter(),
    Menu: { getApplicationMenu: () => null, buildFromTemplate: template => template, setApplicationMenu: value => { menu.current = value; } },
    MenuItem: class { constructor(value) { Object.assign(this, value); } }
  };
  const context = {
    console: { log: jest.fn(), error: jest.fn() }, __dirname: path.join(__dirname, '..'),
    process: { argv: args, env: {}, platform: 'darwin', on: jest.fn() }, setTimeout,
    require: name => {
      if (name === 'electron') return electron;
      if (name === 'electron-updater') return { autoUpdater: { on: jest.fn() } };
      if (name === 'path') return path;
      if (name === 'fs') return { mkdirSync: jest.fn() };
      if (name === './bridge.cjs') return bridge;
      if (name === './task5-dev-controller.cjs') return require('../task5-dev-controller.cjs');
      throw new Error(name);
    }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../electron-main.cjs'), 'utf8'), context);
  return { windows, app, ipcMain, bridge, menu };
}
test('DEV uses a separate controller, reopens one controller and closes it with the main window', () => {
  const h = windowHost(['electron', '--task5-dev']); h.app.emit('ready');
  const main = h.windows[0]; main.emit('ready-to-show');
  expect(h.windows).toHaveLength(2); expect(main.options.title).toBe('Paloma Morse');
  const controller = h.windows[1];
  expect(controller.loadURL.mock.calls[0][0]).toContain('task5controller=1');
  expect(main.loadURL.mock.calls[0][0]).not.toContain('task5controller');
  const reopen = h.menu.current.find(item => item.label === 'DEV').submenu[0].click;
  reopen(); expect(h.windows).toHaveLength(2); expect(controller.focus).toHaveBeenCalled();
  controller.close(); expect(main.destroyed).toBe(false); expect(h.bridge.stop).not.toHaveBeenCalled();
  reopen(); expect(h.windows).toHaveLength(3); main.close(); expect(h.windows[2].destroyed).toBe(true);
  h.app.emit('will-quit'); expect(h.bridge.stop).toHaveBeenCalledTimes(1);
  expect(h.ipcMain.listenerCount('task5-dev:command')).toBe(0);
});
test('ordinary launch registers no controller IPC/menu and the broker file is packaged', () => {
  const h = windowHost(['electron']); h.app.emit('ready');
  expect(h.windows).toHaveLength(1); expect(h.menu.current).toBeNull();
  expect(h.ipcMain.listenerCount('task5-dev:command')).toBe(0);
  const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
  expect(pkg.build.files).toContain('task5-dev-controller.cjs');
});
