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
    queueMicrotask(() => emitter.emit('listening'));
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

describe('native audio protocol bridge',()=>{
  let child,ws;
  const settings={speed:50,frequency:612.5,ratio:3,pause:3,front:6,volume:50,waveform:'sine',quality:'clean'};
  beforeEach(async()=>{
    child=new EventEmitter();child.stdin={write:jest.fn()};child.stdout=new EventEmitter();child.stderr=new EventEmitter();child.kill=jest.fn();
    spawn.mockReturnValue(child);start(true);await new Promise(r=>setTimeout(r,5));
    ws=new EventEmitter();ws.readyState=1;ws.send=jest.fn();lastWSSInstance.clients.add(ws);lastWSSInstance.emit('connection',ws);
  });
  afterEach(()=>stop());
  const ready=()=>child.stdout.emit('data',Buffer.from('AUDIO READY 1 48000\n'));
  test('buffers split stdout lines and routes native completion',()=>{
    child.stdout.emit('data',Buffer.from('AUDIO RE'));expect(ws.send).not.toHaveBeenCalledWith(expect.stringContaining('"ready"'));
    child.stdout.emit('data',Buffer.from('ADY 1 48000\n'));
    ws.emit('message',JSON.stringify({type:'audio',op:'play',id:'ui-1',settings,patterns:['.','.-'],spacing:'text'}));
    const command=child.stdin.write.mock.calls.at(-1)[0];expect(command).toMatch(/^P \d+ 50 18 30 30 6 0 0 0 \.\|\.-\n$/);
    const id=command.split(' ')[1];child.stdout.emit('data',Buffer.from(`AUDIO CHAR ${id} 0\nAUDIO DONE ${id} 0\n`));
    expect(ws.send).toHaveBeenCalledWith(expect.stringContaining('"id":"ui-1"'));
    expect(ws.send).toHaveBeenCalledWith(expect.stringContaining('"event":"done"'));
  });
  test('rejects command injection',()=>{
    ready();ws.emit('message',JSON.stringify({type:'audio',op:'play',id:1,settings,patterns:['.\nRESET'],spacing:'text'}));
    expect(child.stdin.write).not.toHaveBeenCalled();ws.emit('message','F500\nRESET');expect(child.stdin.write).not.toHaveBeenCalled();
  });
  test('disconnection releases native keys',()=>{
    ready();ws.emit('message',JSON.stringify({type:'audio',op:'key',source:'local',down:true}));ws.emit('close');
    expect(child.stdin.write).toHaveBeenLastCalledWith('RESET\n');
  });
  test('engine death settles clients',()=>{
    ready();ws.emit('message',JSON.stringify({type:'audio',op:'play',id:1,settings,patterns:['.'],spacing:'text'}));child.emit('close',1);
    expect(ws.send).toHaveBeenCalledWith(expect.stringContaining('"event":"unavailable"'));
  });
});
