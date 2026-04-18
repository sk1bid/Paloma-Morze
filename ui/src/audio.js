class MorseAudioEngine {
  constructor() {
    this.ctx = null;
    this.osc = null;
    this.gain = null;
    this.frequency = 700;
    this.volume = 0.5;
    this.dashRatio = 3.0;
    this.activeTimeouts = new Set();
  }

  init() {
    if (!this.ctx) {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.gain = this.ctx.createGain();
      this.gain.connect(this.ctx.destination);
      this.gain.gain.value = 0;

      this.osc = this.ctx.createOscillator();
      this.osc.type = 'sine';
      this.osc.frequency.value = this.frequency;
      this.osc.connect(this.gain);
      this.osc.start();
    }
    if (this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  registerTimeout(callback, ms) {
    const id = setTimeout(() => {
      this.activeTimeouts.delete(id);
      callback();
    }, ms);
    this.activeTimeouts.add(id);
    return id;
  }

  clearAllTimeouts() {
    this.activeTimeouts.forEach(id => clearTimeout(id));
    this.activeTimeouts.clear();
  }

  setFrequency(freq) {
    this.frequency = freq;
    if (this.osc && this.ctx) this.osc.frequency.setValueAtTime(freq, this.ctx.currentTime);
  }

  setVolume(vol) {
    this.volume = vol / 100;
  }

  setCharWpm(wpm) {
    this.charWpm = wpm;
  }

  setPauseFactor(factor) {
    this.pauseFactor = factor;
  }

  setDashRatio(ratio) {
    this.dashRatio = ratio;
  }

  // Returns a Promise that resolves when the sound finishes
  playString(morseStr, startTime, onPulse = null) {
    this.init();
    let isCancelled = false;
    this.cancelTokens = this.cancelTokens || [];
    const token = { cancel: () => { isCancelled = true; } };
    this.cancelTokens.push(token);

    const currentSpeed = isFinite(this.charWpm) ? (this.charWpm || 60) : 60;
    const dotLen = 6.0 / currentSpeed;
    const dashLen = dotLen * (this.dashRatio || 3.0);
    const intraCharGap = dotLen;
    const attack = 0.005; // Standard 5ms
    const release = 0.005;

    // Safety: ensure startTime is finite and in the future
    let time = (typeof startTime === 'number' && isFinite(startTime)) ? startTime : this.ctx.currentTime;
    if (time < this.ctx.currentTime) time = this.ctx.currentTime;
    time += 0.020; // 20ms buffer to strictly prevent scheduling in the past
    const baseTime = this.ctx.currentTime;

    for (let i = 0; i < morseStr.length; i++) {
      const symbol = morseStr[i];
      
      if (symbol === ' ') {
        time += intraCharGap * 2; // Extra gap (space in pattern means extra pause)
        continue;
      }

      const type = symbol === '-' ? 'dash' : 'dot';
      const duration = symbol === '-' ? dashLen : dotLen;

      if (onPulse) {
        const pulseStartMs = (time - baseTime) * 1000;
        const pulseEndMs = (time + duration - baseTime) * 1000;
        this.registerTimeout(() => { if (!isCancelled) onPulse(type); }, Math.max(0, pulseStartMs));
        this.registerTimeout(() => { if (!isCancelled) onPulse(null); }, Math.max(0, pulseEndMs));
      }

      // Attack: LCWO (jscwlib) style raised-cosine envelope (Hann window half)
      const e_attack = new Float32Array(32);
      for (let j=0; j<32; j++) {
        e_attack[j] = this.volume * (0.5 - 0.5 * Math.cos(Math.PI * (j / 31)));
      }
      this.gain.gain.setValueCurveAtTime(e_attack, time, attack);

      time += duration;

      // Release: LCWO style
      const e_release = new Float32Array(32);
      for (let j=0; j<32; j++) {
        e_release[j] = this.volume * (0.5 + 0.5 * Math.cos(Math.PI * (j / 31)));
      }
      this.gain.gain.setValueCurveAtTime(e_release, time, release);

      if (i < morseStr.length - 1) {
        time += intraCharGap;
      }
    }

    const finishTime = time + release;
    const waitTimeMs = (finishTime - this.ctx.currentTime) * 1000;

    const promise = new Promise(r => {
      this.registerTimeout(() => {
        this.cancelTokens = this.cancelTokens.filter(t => t !== token);
        r();
      }, Math.max(0, waitTimeMs));
    });
    promise.finishTime = finishTime;
    return promise;
  }

  async playSequence(sequence, morseDict, onCharPlay = null, onPulse = null) {
    this.init();
    let isCancelled = false;
    this.cancelTokens = this.cancelTokens || [];
    const token = {
      cancel: () => {
        isCancelled = true;
        if (onCharPlay) onCharPlay(null);
        if (onPulse) onPulse(null);
      }
    };
    this.cancelTokens.push(token);

    try {
      const currentSpeed = this.charWpm || 60;
      const dotLen = 6.0 / currentSpeed;

      const uiPause = this.pauseFactor || 3.0; 
      // APAK mapping: x1.0 -> 3 dots, x2.0 -> 5 dots, x3.0 -> 7 dots.
      const pFactor = (uiPause * 2.0) + 1.0; 

      const interCharGap = dotLen * pFactor; 
      const wordGap = dotLen * (pFactor * (7.0 / 3.0)); // Proportional word gap
      const extraWordGap = wordGap - interCharGap;

      let nextStartTime = this.ctx.currentTime + 0.1;

      for (let i = 0; i < sequence.length; i++) {
        if (isCancelled) break;
        const char = sequence[i];

        if (char === ' ') {
          nextStartTime += extraWordGap;
          continue;
        }

        const morsePattern = typeof morseDict === 'function' 
          ? morseDict(char)
          : Object.keys(morseDict).find(k => morseDict[k] === char);
        if (morsePattern) {
          if (onCharPlay) {
            const charDelayMs = (nextStartTime - this.ctx.currentTime) * 1000;
            this.registerTimeout(() => {
              if (!isCancelled) onCharPlay(char);
            }, Math.max(0, charDelayMs));
          }

          const playPromise = this.playString(morsePattern, nextStartTime, onPulse);
          await playPromise;
          const finishTime = playPromise.finishTime;

          // Prepare for next char
          nextStartTime = finishTime + interCharGap;
        }
      }
    } finally {
      this.cancelTokens = this.cancelTokens.filter(t => t !== token);
    }
  }

  keyDown() {
    this.init();
    if (this.gain && this.ctx) {
      this.gain.gain.cancelScheduledValues(this.ctx.currentTime);
      this.gain.gain.setTargetAtTime(this.volume, this.ctx.currentTime, 0.005);
    }
  }

  keyUp() {
    if (this.gain && this.ctx) {
      this.gain.gain.cancelScheduledValues(this.ctx.currentTime);
      this.gain.gain.setTargetAtTime(0, this.ctx.currentTime, 0.005);
    }
  }

  stopAll() {
    this.clearAllTimeouts();
    if (this.cancelTokens) {
      this.cancelTokens.forEach(t => t.cancel());
      this.cancelTokens = [];
    }
    if (this.gain && this.ctx) {
      this.gain.gain.cancelScheduledValues(this.ctx.currentTime);
      // Cancel without setting any harsh value, decay naturally from current position
      this.gain.gain.setTargetAtTime(0, this.ctx.currentTime, 0.005);
    }
  }
}

export const audioEngine = new MorseAudioEngine();
