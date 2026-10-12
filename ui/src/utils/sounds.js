import { audioEngine } from '../audio.js';
// UI notifications share the C++ audio device and its priority rules.
export const sounds = {
  init: () => audioEngine.init(),
  playConnect: () => audioEngine.notice('connect'),
  playDisconnect: () => audioEngine.notice('disconnect'),
};
