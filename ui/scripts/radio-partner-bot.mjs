// Scripted correspondent for testing the online radio network without a real partner.
//
//   node scripts/radio-partner-bot.mjs [relayUrl]
//
// The bot registers/logs in as BOT1, creates the lobby "SIMPLEX TEST", waits for
// a second participant, starts the session and then keys a long dash every few
// seconds so you can press your own key on top of it and provoke a collision.
// Everything you transmit is printed as dots/dashes and decoded letters.
// It also registers a local test operator account, OPERATOR_CALLSIGN / OPERATOR_PASSWORD,
// for signing into the app itself (local dev relay only).
import { io } from 'socket.io-client';

const RELAY = process.argv[2] || 'http://localhost:3001';
const CALLSIGN = 'BOT1';
const PASSWORD = 'bot-test-pass';
const OPERATOR_CALLSIGN = 'TEST1';
const OPERATOR_PASSWORD = 'test-pass-1';
const LOBBY = 'SIMPLEX TEST';
const HOLD_MS = 1500;   // how long the bot keeps its key down
const PERIOD_MS = 4000; // how often it keys

const post = async (path, body) => {
  const res = await fetch(`${RELAY}/api${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { ok: res.ok, data: await res.json().catch(() => ({})) };
};

const MORSE = {
  '.-': 'А', '-...': 'Б', '.--': 'В', '--.': 'Г', '-..': 'Д', '.': 'Е', '...-': 'Ж', '--..': 'З',
  '..': 'И', '.---': 'Й', '-.-': 'К', '.-..': 'Л', '--': 'М', '-.': 'Н', '---': 'О', '.--.': 'П',
  '.-.': 'Р', '...': 'С', '-': 'Т', '..-': 'У', '..-.': 'Ф', '....': 'Х', '-.-.': 'Ц', '---.': 'Ч',
  '----': 'Ш', '--.-': 'Щ', '-.--': 'Ы', '-..-': 'Ь', '..-..': 'Э', '..--': 'Ю', '.-.-': 'Я',
  '-----': '0', '.----': '1', '..---': '2', '...--': '3', '....-': '4', '.....': '5',
  '-....': '6', '--...': '7', '---..': '8', '----.': '9',
};

await post('/auth/register', { callsign: CALLSIGN, password: PASSWORD });
await post('/auth/register', { callsign: OPERATOR_CALLSIGN, password: OPERATOR_PASSWORD });
const login = await post('/auth/login', { callsign: CALLSIGN, password: PASSWORD });
if (!login.ok) throw new Error(`Login failed: ${JSON.stringify(login.data)}`);
const { token } = login.data;

const lobby = await post('/lobbies', { name: LOBBY, token });
if (!lobby.ok) throw new Error(`Lobby create failed (restart the relay to clear stale lobbies): ${JSON.stringify(lobby.data)}`);
const roomId = lobby.data.id;

const socket = io(RELAY, { auth: { callsign: CALLSIGN } });
socket.on('connect', () => {
  socket.emit('join', { roomId, token });
  console.log(`[bot] ${CALLSIGN} is waiting in lobby "${LOBBY}". Join it from the app.`);
});
socket.on('error', (err) => console.error('[bot] relay error:', err));

let started = false;
socket.on('room_update', ({ participants }) => {
  console.log(`[bot] participants: ${participants.map((p) => p.callsign).join(', ')}`);
  if (!started && participants.length >= 2) {
    started = true;
    setTimeout(() => socket.emit('start_session', { roomId }), 500);
  }
});

let keyTimer = null;
socket.on('session_started', () => {
  console.log(`[bot] session started. Keying a ${HOLD_MS} ms tone every ${PERIOD_MS} ms.`);
  clearInterval(keyTimer);
  keyTimer = setInterval(() => {
    socket.emit('morse_event', { roomId, value: 1 });
    console.log('[bot] KEY DOWN');
    setTimeout(() => {
      socket.emit('morse_event', { roomId, value: 0 });
      console.log('[bot] KEY UP');
    }, HOLD_MS);
  }, PERIOD_MS);
});
socket.on('session_ended', () => {
  clearInterval(keyTimer);
  started = false;
  console.log('[bot] session ended');
});

// Decode what the human operator sends (same 15 WPM thresholds as RadioNetwork.jsx)
const UNIT = 1200 / 15;
let downAt = 0;
let symbol = '';
let letterTimer = null;
socket.on('remote_morse', ({ callsign, value }) => {
  const now = Date.now();
  if (value === 1) {
    downAt = now;
    clearTimeout(letterTimer);
    return;
  }
  if (!downAt) return; // key-up without a key-down (e.g. a safety release)
  symbol += now - downAt >= UNIT * 2 ? '-' : '.';
  downAt = 0;
  letterTimer = setTimeout(() => {
    console.log(`[bot] received from ${callsign}: ${symbol} -> ${MORSE[symbol] ?? '?'}`);
    symbol = '';
  }, UNIT * 3);
});

process.on('SIGINT', () => {
  socket.emit('leave_room', { roomId });
  setTimeout(() => process.exit(0), 300);
});
