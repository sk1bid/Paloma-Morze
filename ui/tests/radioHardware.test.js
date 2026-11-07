import { jest, test, expect } from '@jest/globals';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { transform } from 'rolldown/experimental';

class Events {
  listeners = new Map();
  readyState = 1;
  send = jest.fn();
  addEventListener(name, callback) {
    if (!this.listeners.has(name)) this.listeners.set(name, new Set());
    this.listeners.get(name).add(callback);
  }
  removeEventListener(name, callback) { this.listeners.get(name)?.delete(callback); }
  dispatch(name, event = {}) { for (const callback of this.listeners.get(name) || []) callback(event); }
}

test('physical hardware loss releases the relay key while the bridge remains open', async () => {
  const effects = [], hardware = new Events(), browser = new Events();
  const emit = jest.fn();
  const context = vm.createContext({ window: browser, Date, setInterval: () => 1, clearInterval: () => {} });
  const stubs = {
    react: {
      default: {}, useState: value => [value, jest.fn()], useRef: current => ({ current }),
      useEffect: callback => effects.push(callback),
    },
    'react/jsx-runtime': { jsx: () => null, jsxs: () => null },
    'lucide-react': Object.fromEntries(['X', 'Radio', 'ArrowLeftRight', 'Activity', 'TriangleAlert'].map(name => [name, () => null])),
    './TapeDisplay': { TapeDisplay: () => null },
    './audio': { audioEngine: { init: jest.fn(), keyDown: jest.fn(), keyUp: jest.fn() } },
  };
  const source = readFileSync(new URL('../src/RadioNetwork.jsx', import.meta.url), 'utf8');
  const { code } = await transform('RadioNetwork.jsx', source);
  const module = new vm.SourceTextModule(code, { context });
  await module.link(name => {
    const values = stubs[name];
    if (!values) throw new Error(`Unexpected component dependency: ${name}`);
    return new vm.SyntheticModule(Object.keys(values), function () {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, { context });
  });
  await module.evaluate();
  module.namespace.RadioNetwork({ user: { callsign: 'AAA' }, participants: [], ws: hardware,
    socket: { current: { emit } }, roomId: 'room', remoteSignal: 0 });
  const cleanups = effects.map(callback => callback()).filter(Boolean);
  hardware.dispatch('message', { data: '1' });
  hardware.dispatch('message', { data: '1' });
  hardware.dispatch('message', { data: 'STATUS:DISCONNECTED' });
  hardware.dispatch('message', { data: 'STATUS:DISCONNECTED' });
  expect(hardware.readyState).toBe(1);
  expect(emit.mock.calls).toEqual([
    ['morse_event', { roomId: 'room', value: 1 }],
    ['morse_event', { roomId: 'room', value: 0 }],
  ]);
  // A fresh hardware press works on the same bridge after reconnecting the key.
  hardware.dispatch('message', { data: 'STATUS:CONNECTED' });
  hardware.dispatch('message', { data: '1' });
  hardware.dispatch('close');
  expect(emit.mock.calls.map(([, value]) => value.value)).toEqual([1, 0, 1, 0]);
  for (const cleanup of cleanups.reverse()) cleanup();
  expect(emit).toHaveBeenCalledTimes(4);
});
