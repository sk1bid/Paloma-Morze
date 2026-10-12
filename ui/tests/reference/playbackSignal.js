import { APAK_RATE, roundEven } from './apakAudio.js';

// The original byte-accurate PCM stays available for reference comparisons.
// Everyday playback retains its event timetable but avoids quantization to PCM8
// and conversion from 11025 Hz by synthesizing directly at the output rate.
export function playbackSignal(rendered, outputRate, quality = 'clean') {
  if (quality === 'original') {
    return { sampleRate: APAK_RATE,
      samples: Float32Array.from(rendered.pcm, value => (value - 128) / 128) };
  }
  if (!Number.isFinite(outputRate) || outputRate < 8000 || outputRate > 192000) {
    throw new RangeError('Invalid audio output sample rate');
  }
  const samples = new Float32Array(roundEven(rendered.pcm.length * outputRate / APAK_RATE));
  const { frequency, edgeSamples, waveform } = rendered.settings;
  const edge = edgeSamples / APAK_RATE * outputRate;
  // A band-limited square avoids folding its high harmonics into audible tones.
  let square;
  if (waveform === 'square') {
    square = new Float32Array(4096);
    let peak = 0;
    const maxHarmonic = Math.min(63, Math.floor(0.45 * outputRate / frequency));
    for (let i = 0; i < square.length; i++) {
      let value = 0;
      for (let h = 1; h <= maxHarmonic; h += 2) value += Math.sin(2 * Math.PI * h * i / square.length) / h;
      square[i] = value; peak = Math.max(peak, Math.abs(value));
    }
    for (let i = 0; i < square.length; i++) square[i] *= (120 / 128) / peak;
  }
  for (const pulse of rendered.pulses) {
    const start = roundEven(pulse.frame * outputRate / APAK_RATE);
    const end = roundEven((pulse.frame + pulse.length) * outputRate / APAK_RATE);
    const length = end - start;
    for (let i = 0; i < length; i++) {
      // Both endpoints are exactly zero. The edge remains inside the element.
      const envelope = Math.min(1, i / edge, (length - 1 - i) / edge);
      const phase = frequency * i / outputRate;
      let carrier;
      if (square) {
        const index = (phase % 1) * square.length;
        const low = Math.floor(index), mix = index - low;
        carrier = square[low] * (1 - mix) + square[(low + 1) % square.length] * mix;
      } else carrier = (127 / 128) * Math.sin(2 * Math.PI * phase);
      samples[start + i] = carrier * envelope;
    }
  }
  return { sampleRate: outputRate, samples };
}
