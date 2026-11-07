const { EventEmitter } = require('node:events');
const { createControllerBroker, cleanSnapshot } = require('../task5-dev-controller.cjs');
const makeWindow = () => ({ isDestroyed: () => false, webContents: { send: jest.fn(), isDestroyed: () => false } });
const state = index => ({ index, status: 'paused', developmentPreview: true, blocked: false, variant: { steps: [{ id: 'call', title: 'Вызов', direction: 'transmit', expectedMessages: ['PRIVATE'] }, { id: 'reply', title: 'Ответ', direction: 'receive' }] } });
function fixture() {
  const ipcMain = new EventEmitter();
  const main = makeWindow(); let controller = makeWindow();
  const broker = createControllerBroker({ ipcMain, getMainWindow: () => main, getControllerWindow: () => controller });
  return { ipcMain, main, broker, get controller() { return controller; }, close() { controller = null; }, reopen() { controller = makeWindow(); return controller; } };
}
test('ready handshake works before the first snapshot and only the actual main window can publish state', () => {
  const h = fixture(); h.ipcMain.emit('task5-dev:controller-ready', { sender: h.controller.webContents });
  expect(h.main.webContents.send).toHaveBeenCalledWith('task5-dev:request-state', undefined);
  h.ipcMain.emit('task5-dev:state', { sender: {} }, state(0)); expect(h.controller.webContents.send).not.toHaveBeenCalled();
  h.ipcMain.emit('task5-dev:state', { sender: h.main.webContents }, state(1));
  const snapshot = h.controller.webContents.send.mock.calls.at(-1)[1];
  expect(snapshot.index).toBe(1); expect(JSON.stringify(snapshot)).not.toContain('PRIVATE');
  h.broker.dispose();
});
test('commands require the controller identity, an allowlisted shape, valid index and an unblocked main', () => {
  const h = fixture(); h.ipcMain.emit('task5-dev:state', { sender: h.main.webContents }, state(0));
  for (const command of [{ type: 'jump', index: -1 }, { type: 'jump', index: 2 }, { type: 'jump', index: 0.5 }, { type: 'enter', script: 'x' }, { type: 'delete' }, null]) h.ipcMain.emit('task5-dev:command', { sender: h.controller.webContents }, command);
  h.ipcMain.emit('task5-dev:command', { sender: {} }, { type: 'enter' });
  expect(h.main.webContents.send).not.toHaveBeenCalled();
  for (const command of [{ type: 'jump', index: 1 }, { type: 'enter' }, { type: 'group-error' }]) h.ipcMain.emit('task5-dev:command', { sender: h.controller.webContents }, command);
  expect(h.main.webContents.send).toHaveBeenCalledTimes(3);
  h.ipcMain.emit('task5-dev:state', { sender: h.main.webContents }, { ...state(0), blocked: true });
  h.ipcMain.emit('task5-dev:command', { sender: h.controller.webContents }, { type: 'enter' });
  expect(h.main.webContents.send).toHaveBeenCalledTimes(3); h.broker.dispose();
});
test('closing and reopening the controller retains fresh state without stopping the main session', () => {
  const h = fixture(); h.close();
  h.ipcMain.emit('task5-dev:state', { sender: h.main.webContents }, state(1));
  expect(h.main.webContents.send).not.toHaveBeenCalled();
  const reopened = h.reopen(); h.ipcMain.emit('task5-dev:controller-ready', { sender: reopened.webContents });
  expect(reopened.webContents.send).toHaveBeenCalledWith('task5-dev:state', expect.objectContaining({ index: 1 }));
  expect(h.main.webContents.send.mock.calls.every(([channel]) => channel === 'task5-dev:request-state')).toBe(true);
  h.broker.dispose(); expect(h.ipcMain.eventNames()).toEqual([]);
});
test('malformed snapshots are ignored and only main errors reach the controller', () => {
  expect(cleanSnapshot({ ...state(0), variant: { steps: [null] } })).toBeNull();
  expect(cleanSnapshot(state(3))).toBeNull();
  const h = fixture(); h.ipcMain.emit('task5-dev:error', { sender: {} }, 'fake'); expect(h.controller.webContents.send).not.toHaveBeenCalled();
  h.ipcMain.emit('task5-dev:error', { sender: h.main.webContents }, 'Audio unavailable');
  expect(h.controller.webContents.send).toHaveBeenCalledWith('task5-dev:error', 'Audio unavailable'); h.broker.dispose();
});
