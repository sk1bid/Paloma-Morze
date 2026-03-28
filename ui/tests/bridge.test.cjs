// 1. MOCKS FIRST
jest.mock('child_process', () => ({
  spawn: jest.fn(),
}));

let lastWSSInstance = null;
jest.mock('ws', () => {
  const EventEmitter = require('events');
  const mockWSS = jest.fn().mockImplementation(() => {
    const emitter = new EventEmitter();
    emitter.clients = new Set();
    emitter.close = jest.fn();
    lastWSSInstance = emitter;
    return emitter;
  });
  return { WebSocketServer: mockWSS };
});

// 2. REQUIRES
const { spawn } = require('child_process');
const { start, stop } = require('../bridge.cjs');
const { WebSocketServer } = require('ws');
const EventEmitter = require('events');

describe('Bridge Hardware Logic', () => {
  let mockProcess;
  let mockWS;

  beforeEach(() => {
    jest.clearAllMocks();
    lastWSSInstance = null;
    
    mockProcess = new EventEmitter();
    mockProcess.stdin = { write: jest.fn() };
    mockProcess.stdout = new EventEmitter();
    mockProcess.stderr = new EventEmitter();
    mockProcess.kill = jest.fn();
    spawn.mockReturnValue(mockProcess);

    mockWS = new EventEmitter();
    mockWS.readyState = 1;
    mockWS.send = jest.fn();
  });

  afterEach(() => {
    stop();
  });

  const sleep = (ms) => new Promise(res => setTimeout(res, ms));

  test('should connect when engine reports Auth OK', async () => {
    start(true, ['--test-mode', 'auth_ok']);
    await sleep(20);
    
    const wss = lastWSSInstance;
    wss.emit('connection', mockWS);
    wss.clients.add(mockWS);

    mockProcess.stdout.emit('data', Buffer.from('[Engine] Connected to COM3 (Auth OK!)\n'));
    await sleep(20);
    
    expect(mockWS.send).toHaveBeenCalledWith('STATUS:CONNECTED');
  });

  test('should remain disconnected when auth fails', async () => {
    start(true, ['--test-mode', 'auth_fail']);
    await sleep(20);
    
    const wss = lastWSSInstance;
    wss.emit('connection', mockWS);
    wss.clients.add(mockWS);

    // Initial message on connection
    expect(mockWS.send).toHaveBeenCalledWith('STATUS:DISCONNECTED');

    // Send ignore message
    mockProcess.stdout.emit('data', Buffer.from('[Engine] Ignored COM1 (no PALOMA response)\n'));
    await sleep(20);
    
    // Check that it did NOT call CONNECTED
    expect(mockWS.send).not.toHaveBeenCalledWith('STATUS:CONNECTED');
  });

  test('should handle reconnection when port is lost', async () => {
    start(true, ['--test-mode', 'auth_ok']);
    await sleep(20);
    
    const wss = lastWSSInstance;
    wss.emit('connection', mockWS);
    wss.clients.add(mockWS);

    // 1. Connect
    mockProcess.stdout.emit('data', Buffer.from('[Engine] Connected to COM3 (Auth OK!)\n'));
    await sleep(20);
    expect(mockWS.send).toHaveBeenCalledWith('STATUS:CONNECTED');

    // 2. Disconnect
    mockProcess.stdout.emit('data', Buffer.from('[Engine] Port lost. Reconnecting...\n'));
    await sleep(20);
    expect(mockWS.send).toHaveBeenCalledWith('STATUS:DISCONNECTED');
  });
});
