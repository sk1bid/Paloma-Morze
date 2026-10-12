import { jest } from '@jest/globals';
import fs from 'node:fs';
import { playbackSignal } from './reference/playbackSignal.js';
import { MorseAudioEngine } from '../src/audio.js';
import { APAK_RATE, apakSettings, apakTone, apakWav, buildApakPCM, roundEven } from './reference/apakAudio.js';

const lookup = char => ({ E: '.', L: '.-..', V: '...-', A: '.-' })[char];
const reference = { speed: 50, frequency: 11025 / 23, front: 6, pause: 3, ratio: 3 };

describe('APAK 2.12 binary and live-output regression', () => {
  test.each(['E', 'L', 'V', 'A'])('%s matches original running APAK waveOutWrite byte for byte', char => {
    const expected = fs.readFileSync(new URL(`./fixtures/apak-2.12/${char}.pcm`, import.meta.url));
    const actual = buildApakPCM([char], lookup, reference);
    expect(Buffer.from(actual.pcm).equals(expected)).toBe(true);
  });
  test.each([[30, 2204], [50, 1322], [60, 1102], [100, 661], [150, 441]])(
    'speed %i produces %i samples per dot', (speed, samples) => {
      const rendered = buildApakPCM(['E'], lookup, { ...reference, speed });
      expect(rendered.pulses[0].length).toBe(samples);
      expect(rendered.pcm.length).toBe(samples * 2); // Includes the one-dot silent tail.
      expect([...rendered.pcm.slice(samples)].every(x => x === 128)).toBe(true);
    });
  test('x87 ties-to-even rounding, including a fractional dash', () => {
    expect([0.5, 1.5, 2.5, -0.5, -1.5].map(roundEven)).toEqual([0, 2, 2, 0, -2]);
    expect(apakSettings({ speed: 100, ratio: 2.5 }).dashSamples).toBe(1652);
  });
  test('intra-character silence is an entire dot; release stays inside the element', () => {
    const r = buildApakPCM(['I'], () => '..', reference);
    expect(r.pulses.map(p => p.frame)).toEqual([0, 2644]);
    expect([...r.pcm.slice(1322, 2644)].every(x => x === 128)).toBe(true);
    expect(r.pcm.length).toBe(5288);
  });
  test.each([[1, 3858, 6504], [3, 6504, 14442], [6, 10473, 26338]])(
    'text pause x%i uses Int.cwl and the PCM tail once', (pause, letter, group) => {
      const r = buildApakPCM(['E', 'E', ' ', 'E'], lookup, { ...reference, pause });
      const [a, b, c] = r.pulses;
      expect(b.frame - a.frame - a.length).toBe(letter);
      expect(c.frame - b.frame - b.length).toBe(group);
    });
  test('lesson 1 uses fixed 500/1500 ms timers, independent of pause control', () => {
    const first = buildApakPCM(['E','E',' ','E'], lookup, { ...reference, spacing: 'learning', pause: 1 });
    const second = buildApakPCM(['E','E',' ','E'], lookup, { ...reference, spacing: 'learning', pause: 6 });
    expect(first.pulses.map(p => p.frame)).toEqual([0, 8156, 27338]);
    expect(Buffer.from(first.pcm).equals(Buffer.from(second.pcm))).toBe(true);
  });
  test('error repeat uses APAK repeat timer 2 * calibration * pause', () => {
    const r = buildApakPCM(['E','E'], lookup, { ...reference, spacing: 'repeat' });
    expect(r.pulses[1].frame).toBe(9987); // 1322 tone + 1322 tail + 7343 timer samples.
  });
  test('front direction and frequency quantization match Delphi handlers', () => {
    expect(apakSettings({ ...reference, front: 0 }).edgeSamples).toBe(72);
    expect(apakSettings({ ...reference, front: 12 }).edgeSamples).toBe(6);
    expect(apakSettings({ frequency: 700 }).frequency).toBe(11025 / 16);
  });
  test('square mode thresholds to 8/248 and still has silent gaps', () => {
    const settings = apakSettings({ ...reference, waveform: 'square' });
    expect(new Set(apakTone(1322, settings))).toEqual(new Set([8,248]));
    const r = buildApakPCM(['E'], lookup, settings);
    expect([...r.pcm.slice(1322)].every(x => x === 128)).toBe(true);
  });
  test('multi-letter Q patterns use real character gaps and invalid patterns are silent', () => {
    const joined = buildApakPCM(['Q'], () => '. .', reference);
    const separate = buildApakPCM(['E','E'], lookup, reference);
    expect(Buffer.from(joined.pcm).equals(Buffer.from(separate.pcm))).toBe(true);
    expect(buildApakPCM(['X'], () => 'garbage', reference).pcm.length).toBe(0);
  });
  test('WAV is mono 11025 Hz unsigned PCM8; odd data sizes are RIFF-padded', () => {
    const wav = apakWav(new Uint8Array([128,255,0]));
    const v = new DataView(wav.buffer);
    expect(wav.length).toBe(48);
    expect(v.getUint32(24,true)).toBe(11025);
    expect(v.getUint16(34,true)).toBe(8);
    expect(v.getUint32(40,true)).toBe(3);
    expect([...wav.slice(44,47)]).toEqual([128,255,0]);
  });
});

describe('clean playback retains APAK rhythm without legacy quantization', () => {
  const settings = { ...reference, frequency: 612.5, front: 3 };
  test.each([44100, 48000, 96000])('all signal boundaries stay within half a sample at %i Hz', rate => {
    const r = buildApakPCM(['A','E',' ','L'], lookup, settings);
    const clean = playbackSignal(r, rate);
    expect(clean.sampleRate).toBe(rate);
    expect(Math.abs(clean.samples.length / rate - r.duration)).toBeLessThanOrEqual(0.5/rate);
    for (let j=0;j<r.pulses.length;j++) {
      const p = r.pulses[j];
      const start = Math.round(p.frame * rate / APAK_RATE);
      const end = Math.round((p.frame+p.length) * rate / APAK_RATE);
      expect(clean.samples[start]).toBe(0);
      expect(Math.abs(clean.samples[end-1])).toBe(0);
      const next = j+1<r.pulses.length ? Math.round(r.pulses[j+1].frame * rate / APAK_RATE) : clean.samples.length;
      expect(clean.samples.subarray(end,next).every(x=>x===0)).toBe(true);
    }
    expect(clean.samples.every(Number.isFinite)).toBe(true);
  });
  test('clean carrier has negligible distortion instead of PCM8 steps', () => {
    const r=buildApakPCM(['T'],()=>'-',settings);
    const clean=playbackSignal(r,44100);
    let cleanError=0, oldError=0;
    for(let i=500;i<1000;i++) {
      const ideal=(127/128)*Math.sin(2*Math.PI*612.5*i/44100);
      cleanError+=(clean.samples[i]-ideal)**2;
    }
    for(let i=125;i<250;i++) {
      const ideal=(127/128)*Math.sin(2*Math.PI*612.5*i/11025);
      oldError+=((r.pcm[i]-128)/128-ideal)**2;
    }
    expect(cleanError/500).toBeLessThan(1e-14);
    expect(oldError/125).toBeGreaterThan(1e-7);
  });
  test('original option still matches captured APAK PCM exactly', () => {
    const r=buildApakPCM(['L'],lookup,reference);
    const output=playbackSignal(r,48000,'original');
    const fixture=fs.readFileSync(new URL('./fixtures/apak-2.12/L.pcm',import.meta.url));
    expect(output.sampleRate).toBe(11025);
    expect([...output.samples]).toEqual([...fixture].map(x=>(x-128)/128));
  });
  test('clean square is bounded and finite, with an actual silent tail', () => {
    const r=buildApakPCM(['E'],lookup,{...settings,waveform:'square'});
    const output=playbackSignal(r,48000);
    expect(output.samples.every(x=>Number.isFinite(x)&&Math.abs(x)<=120/128)).toBe(true);
    expect(output.samples.subarray(Math.round(r.pulses[0].length*48000/11025)).every(x=>x===0)).toBe(true);
  });
  test('invalid output clock is rejected', () => {
    expect(()=>playbackSignal(buildApakPCM(['E'],lookup,settings),NaN)).toThrow(RangeError);
  });
});

class FakeSocket {
  constructor(){this.readyState=1;this.listeners={};this.sent=[];}
  addEventListener(name,fn){(this.listeners[name] ||= new Set()).add(fn);}
  removeEventListener(name,fn){this.listeners[name]?.delete(fn);}
  emit(name,data){this.listeners[name]?.forEach(fn=>fn({data:typeof data==='object'?JSON.stringify(data):data}));}
  send(data){this.sent.push(JSON.parse(data));}
}
describe('native audio control client',()=>{
  let engine,socket;
  beforeEach(()=>{engine=new MorseAudioEngine();socket=new FakeSocket();engine.bindSocket(socket);socket.emit('message',{type:'audio',event:'ready',sampleRate:48000});socket.sent=[];});
  test('serializes patterns and settings; never creates browser audio',()=>{
    global.window={AudioContext:jest.fn(()=>{throw Error('Browser audio forbidden');})};
    engine.playSequence(['E','A',' ','L'],lookup);
    expect(socket.sent[0]).toMatchObject({op:'play',patterns:['.','.-','/','.-..'],spacing:'text',settings:{quality:'clean',speed:50}});
    expect(global.window.AudioContext).not.toHaveBeenCalled();
  });
  test('UI callbacks and completion come from native events',async()=>{
    const char=jest.fn(),pulse=jest.fn(),p=engine.playSequence(['E','L'],lookup,char,pulse),id=socket.sent[0].id;
    socket.emit('message',{type:'audio',event:'char',id,value:1});socket.emit('message',{type:'audio',event:'pulse',id,value:2});
    expect(char).toHaveBeenCalledWith('L');expect(pulse).toHaveBeenCalledWith('dash');
    socket.emit('message',{type:'audio',event:'done',id,value:0});expect(await p).toEqual({cancelled:false});
  });
  test('stop resolves pending calls and suppresses delayed progress',async()=>{
    const pulse=jest.fn(),p=engine.playString('.',null,pulse),id=socket.sent[0].id;
    engine.stopAll();expect(await p).toMatchObject({cancelled:true});socket.emit('message',{type:'audio',event:'pulse',id,value:1});
    expect(pulse.mock.calls).toEqual([[null]]);expect(socket.sent.at(-1).op).toBe('reset');
  });
  test('loss cancels playback and reconnection sends newest settings',async()=>{
    const p=engine.playSequence(['E'],lookup);socket.emit('close');expect(await p).toMatchObject({cancelled:true});
    engine.setFrequency(612.5);const fresh=new FakeSocket();engine.bindSocket(fresh);fresh.emit('message',{type:'audio',event:'ready'});
    expect(fresh.sent.at(-1)).toMatchObject({op:'settings',settings:{frequency:612.5}});
  });
  test('local and remote key ownership are separate commands',()=>{
    engine.keyDown('local');engine.keyDown('local');engine.keyDown('remote');engine.keyUp('local');
    expect(socket.sent.filter(x=>x.op==='key')).toHaveLength(3);expect(engine.activeSources.has('remote')).toBe(true);
    engine.keyUp();expect(socket.sent.at(-1)).toMatchObject({source:'remote',down:false});
  });
  test('no native engine means an explicit error, never a Web Audio fallback',async()=>{
    socket.emit('close');const error=jest.fn();engine.onError=error;
    expect(await engine.playString('.')).toMatchObject({cancelled:true,error:expect.any(String)});expect(error).toHaveBeenCalled();
  });
  test('notifications share the native transport',()=>{engine.notice('connect');expect(socket.sent[0]).toMatchObject({op:'notice',name:'connect'});});
});
