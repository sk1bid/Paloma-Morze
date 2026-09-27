class MorseAudioEngine {
  constructor() {
    this.ctx = null;
    this.osc = null;
    this.gain = null;
    this.frequency = 700;
    this.volume = 0.5;
    this.dashRatio = 3.0;
    this.charWpm = 50;
    this.pauseFactor = 1.0;
    this.activeTimeouts = new Set();
    this.activeSources = new Set();
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

    const currentSpeed = isFinite(this.charWpm) ? (this.charWpm || 50) : 50;
    // APAK Speed 50 = 118.5ms dot. 5.925 / 50 = 0.1185
    const dotLen = 5.925 / currentSpeed;
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
      const currentSpeed = this.charWpm || 50;
      const dotLen = 5.925 / currentSpeed;
      const uiPause = this.pauseFactor || 1.0; 
      
      console.log(`[AudioEngine] Starting sequence: Speed=${currentSpeed} CPM, Pause=x${uiPause}`);

      // APAK Timing Sync:
      // Letter gap = Dot * (Factor + 1) * 1.5
      // Word gap = Dot * (Factor + 1) * 3
      // For x1.0 (standard): 3/6 dots. For x3.0: 6/12 dots.
      const interCharGap = dotLen * (uiPause + 1) * 1.5; 
      const wordGap = dotLen * (uiPause + 1) * 3;
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

  // Live key tone. Mirrors the native engine sidetone (morze_engine_v2.cpp) so the
  // keyboard and the hardware key sound the same: a linear ramp of 0.001 per sample
  // at 44.1 kHz, i.e. 44.1 gain units per second.
  rampKeyTone(target) {
    if (!this.gain || !this.ctx) return;
    const param = this.gain.gain;
    const now = this.ctx.currentTime;
    const current = param.value;
    if (param.cancelAndHoldAtTime) param.cancelAndHoldAtTime(now);
    else param.cancelScheduledValues(now);
    param.setValueAtTime(current, now);
    param.linearRampToValueAtTime(target, now + Math.abs(target - current) / 44.1);
  }

  // Optional `source` ('local', 'remote') lets several keys share one tone: it stays
  // on while at least one source is held. keyUp() without a source is a hard stop.
  keyDown(source) {
    this.init();
    if (source) this.activeSources.add(source);
    this.rampKeyTone(this.volume);
  }

  keyUp(source) {
    if (source) {
      this.activeSources.delete(source);
      if (this.activeSources.size > 0) return;
    } else {
      this.activeSources.clear();
    }
    this.rampKeyTone(0);
  }

  stopAll() {
    this.clearAllTimeouts();
    this.activeSources.clear();
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
