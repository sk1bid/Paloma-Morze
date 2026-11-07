const COMMANDS = new Set(['jump', 'enter', 'group-error']);

function validCommand(command) {
  if (!command || typeof command !== 'object' || !COMMANDS.has(command.type)) return false;
  const keys = Object.keys(command);
  return command.type === 'jump'
    ? keys.length === 2 && keys.includes('index') && Number.isInteger(command.index) && command.index >= 0 && command.index < 200
    : keys.length === 1;
}
function cleanSnapshot(value) {
  if (!value || !Number.isInteger(value.index) || value.index < 0 || value.index > 200) return null;
  if (!['idle', 'running', 'playing', 'paused', 'completed', 'aborted', 'interrupted'].includes(value.status)) return null;
  const steps = value.variant?.steps || [];
  if (!Array.isArray(steps) || steps.length > 200 || !steps.every(step => step && typeof step.id === 'string' && typeof step.title === 'string' && (step.direction == null || ['transmit', 'receive'].includes(step.direction)))) return null;
  if (value.index > steps.length) return null;
  return {
    index: value.index, status: value.status,
    developmentPreview: value.developmentPreview === true,
    blocked: value.blocked === true,
    theme: value.theme === 'light' ? 'light' : 'dark',
    variant: steps.length ? { steps: steps.map(({ id, title, direction }) => ({ id, title, direction })) } : null,
    radiogramRecovery: typeof value.radiogramRecovery?.request === 'string' ? { request: value.radiogramRecovery.request.slice(0, 80) } : null
  };
}

// The main renderer owns the only session/audio client. This broker merely
// forwards small, allowlisted messages between the two known windows.
function createControllerBroker({ ipcMain, getMainWindow, getControllerWindow }) {
  let latest = null;
  const listeners = [];
  const alive = window => window && !window.isDestroyed() && !window.webContents.isDestroyed?.();
  const send = (window, channel, payload) => { if (alive(window)) window.webContents.send(channel, payload); };
  const listen = (channel, handler) => { ipcMain.on(channel, handler); listeners.push([channel, handler]); };
  listen('task5-dev:command', (event, command) => {
    const controller = getControllerWindow();
    if (!alive(controller) || event.sender !== controller.webContents || !validCommand(command)) return;
    if (!latest?.variant || latest.blocked) return;
    if (command.type === 'jump' && (!latest?.variant || command.index >= latest.variant.steps.length)) return;
    send(getMainWindow(), 'task5-dev:command', command);
  });
  listen('task5-dev:state', (event, state) => {
    const main = getMainWindow();
    if (!alive(main) || event.sender !== main.webContents) return;
    const snapshot = cleanSnapshot(state);
    if (!snapshot) return;
    latest = snapshot;
    send(getControllerWindow(), 'task5-dev:state', latest);
  });
  listen('task5-dev:controller-ready', event => {
    const controller = getControllerWindow();
    if (!alive(controller) || event.sender !== controller.webContents) return;
    if (latest) send(controller, 'task5-dev:state', latest);
    send(getMainWindow(), 'task5-dev:request-state');
  });
  listen('task5-dev:error', (event, error) => {
    const main = getMainWindow();
    if (!alive(main) || event.sender !== main.webContents || typeof error !== 'string') return;
    send(getControllerWindow(), 'task5-dev:error', error.slice(0, 1000));
  });
  return {
    dispose() { for (const [channel, handler] of listeners) ipcMain.removeListener(channel, handler); latest = null; }
  };
}
module.exports = { createControllerBroker, validCommand, cleanSnapshot };
