// Mock child_process BEFORE requiring bridge
jest.mock('child_process', () => ({
  spawn: jest.fn(),
}));

const { spawn } = require('child_process');
const { start, stop } = require('../bridge.cjs');
const { WebSocketServer } = require('ws');
const EventEmitter = require('events');

let lastWSSInstance = null;
// Mock ws.WebSocketServer
jest.mock('ws', () => {
  const EventEmitter = require('events');
  const mockWSS = jest.fn().mockImplementation(() => {
    const emitter = new EventEmitter();
    emitter.clients = new Set();
    emitter.close = jest.fn();
    lastWSSInstance = emitter;
    return emitter;
  });
  return {
    WebSocketServer: mockWSS,
  };
});

describe('Bridge Logic', () => {
  let mockProcess;
  let mockWS;

  beforeEach(() => {
    jest.clearAllMocks();
    
    // Setup mock process
    mockProcess = new EventEmitter();
    mockProcess.stdin = { write: jest.fn() };
    mockProcess.stdout = new EventEmitter();
    mockProcess.stderr = new EventEmitter();
    mockProcess.kill = jest.fn();
    spawn.mockReturnValue(mockProcess);

    // Setup mock client
    mockWS = new EventEmitter();
    mockWS.readyState = 1;
    mockWS.send = jest.fn();
  });

  afterEach(() => {
    stop();
  });

  test.skip('should spawn engine and handle messages', (done) => {
    // ...
  });

  test.skip('should broadcast key presses', (done) => {
    // ...
  });
});
