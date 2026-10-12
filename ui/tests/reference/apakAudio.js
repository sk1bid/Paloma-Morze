// APAK-CWL 2.12 PCM and timing model. See docs/APAK-AUDIO.txt.
export const APAK_RATE = 11025;
export const APAK_INTERVALS = Object.freeze([
  188, 161, 140, 124, 111, 93, 92, 91, 70, 65, 60, 62, 58,
  43, 56, 45, 39, 37, 41, 33, 41, 34, 25, 23, 31,
]);
export function roundEven(value) {
  const floor = Math.floor(value);
  return value - floor === 0.5 ? floor + Math.abs(floor % 2) : Math.round(value);
}
const bounded = (value, fallback, min, max) =>
  Math.min(max, Math.max(min, Number.isFinite(Number(value)) ? Number(value) : fallback));
export function apakSettings(options = {}) {
  const speed = Math.round(bounded(options.speed ?? 50, 50, 30, 150) / 5) * 5;
  const period = Math.round(bounded(APAK_RATE / Number(options.frequency || APAK_RATE / 23), 23, 8, 38));
  const front = Math.round(bounded(options.front ?? 6, 6, 0, 12));
  const ratioTenths = Math.round(bounded(options.ratio ?? 3, 3, 2, 4.5) * 10);
  const pauseTenths = Math.round(bounded(options.pause ?? 3, 3, 1, 6) * 10);
  const dotSamples = roundEven(66120 / speed);
  const dashSamples = roundEven(dotSamples * ratioTenths / 10);
  const edgeSamples = roundEven((13 - front) * APAK_RATE / 2000);
  const calibrationMs = APAK_INTERVALS[speed / 5 - 6];
  const spacing = ['learning', 'repeat'].includes(options.spacing) ? options.spacing : 'text';
  const timerMs = multiplier => spacing === 'learning' ? (multiplier === 1 ? 500 : 1500)
    : spacing === 'repeat' ? Math.trunc(multiplier * 2 * calibrationMs * pauseTenths / 10)
    : Math.trunc(multiplier * pauseTenths * dotSamples * 1000 / 110250) + calibrationMs;
  return Object.freeze({ speed, period, frequency: APAK_RATE / period, front, spacing,
    ratio: ratioTenths / 10, pause: pauseTenths / 10,
    waveform: options.waveform === 'square' ? 'square' : 'sine',
    dotSamples, dashSamples, edgeSamples, calibrationMs,
    letterGapSamples: dotSamples + roundEven(timerMs(1) * APAK_RATE / 1000),
    groupGapSamples: dotSamples + roundEven(timerMs(3) * APAK_RATE / 1000),
  });
}
export function apakTone(length, settings) {
  const pcm = new Uint8Array(length);
  const { period, edgeSamples: edge, waveform } = settings;
  for (let i = 0; i < length; i++) {
    const sine = Math.sin(2 * Math.PI * i / period);
    const envelope = i < edge ? i / edge : i >= length - edge ? (length - i) / edge : 1;
    const amplitude = waveform === 'square' && i >= edge && i < length - edge ? 120 : 127;
    const sample = 128 + roundEven(sine * amplitude * envelope);
    pcm[i] = waveform === 'square' ? (sample > 128 ? 248 : 8) : sample;
  }
  return pcm;
}
// Spaces inside a multi-letter pattern (Q codes) are character boundaries.
export function buildApakPCM(sequence, lookup, options = {}) {
  const settings = apakSettings(options);
  const { dotSamples: dot, dashSamples: dash } = settings;
  const parts = [], pulses = [], characters = [];
  let frames = 0, pendingSpace = false, hasCharacter = false;
  const silence = length => { if (length > 0) { parts.push({ length }); frames += length; } };
  for (const char of sequence) {
    if (/^\s+$/.test(char)) { pendingSpace = true; continue; }
    const pattern = lookup(char);
    if (!pattern || !/^[.\-\s]+$/.test(pattern)) continue;
    const words = pattern.trim().split(/\s+/).filter(Boolean);
    if (!words.length) continue;
    if (hasCharacter) silence(pendingSpace ? settings.groupGapSamples : settings.letterGapSamples);
    pendingSpace = false;
    characters.push({ char, frame: frames });
    words.forEach((word, wordIndex) => {
      if (wordIndex) silence(settings.letterGapSamples);
      [...word].forEach((symbol, i) => {
        if (i) silence(dot);
        const length = symbol === '-' ? dash : dot;
        pulses.push({ type: symbol === '-' ? 'dash' : 'dot', frame: frames, length });
        parts.push({ length, tone: symbol }); frames += length;
      });
    });
    hasCharacter = true;
  }
  if (hasCharacter) silence(dot); // Original WAVEHDR's one-dot silent tail.
  if (frames > APAK_RATE * 3600) throw new RangeError('Morse sequence exceeds one hour');
  const pcm = new Uint8Array(frames).fill(128);
  const tones = { '.': apakTone(dot, settings), '-': apakTone(dash, settings) };
  let cursor = 0;
  for (const part of parts) {
    if (part.tone) pcm.set(tones[part.tone], cursor);
    cursor += part.length;
  }
  return { pcm, settings, pulses, characters, sampleRate: APAK_RATE, duration: frames / APAK_RATE };
}
export function apakWav(pcm) {
  const bytes = new Uint8Array(44 + pcm.length + (pcm.length % 2));
  const view = new DataView(bytes.buffer);
  const text = (offset, value) => [...value].forEach((c, i) => bytes[offset+i] = c.charCodeAt(0));
  text(0, 'RIFF'); view.setUint32(4, bytes.length - 8, true); text(8, 'WAVE');
  text(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
  view.setUint16(22, 1, true); view.setUint32(24, APAK_RATE, true);
  view.setUint32(28, APAK_RATE, true); view.setUint16(32, 1, true); view.setUint16(34, 8, true);
  text(36, 'data'); view.setUint32(40, pcm.length, true); bytes.set(pcm, 44);
  return bytes;
}
