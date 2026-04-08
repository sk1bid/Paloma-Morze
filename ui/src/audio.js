class MorseAudioEngine {
  constructor() {
    this.ctx = null;
    this.osc = null;
    this.gain = null;
    this.frequency = 700;
    this.volume = 0.5;
    this.dashRatio = 3.0;
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

  setGapWpm(wpm) {
    this.gapWpm = wpm;
  }

  setDashRatio(ratio) {
    this.dashRatio = ratio;
  }

  // Returns a Promise that resolves when the sound finishes
  playString(morseStr, startTime, onPulse = null) {
    this.init();
    const currentSpeed = isFinite(this.charWpm) ? (this.charWpm || 60) : 60;
    const dotLen = 6.0 / currentSpeed; 
    const dashLen = dotLen * (this.dashRatio || 3.0);
    const intraCharGap = dotLen;
    const attack = 0.005; // Standard 5ms
    const release = 0.005; 

    // Safety: ensure startTime is finite and in the future
    let time = (typeof startTime === 'number' && isFinite(startTime)) ? startTime : this.ctx.currentTime;
    if (time < this.ctx.currentTime) time = this.ctx.currentTime;
    time += 0.005; // Tiny buffer

    for (let i = 0; i < morseStr.length; i++) {
      const symbol = morseStr[i];
      const type = symbol === '-' ? 'dash' : 'dot';
      const duration = symbol === '-' ? dashLen : dotLen;

      if (onPulse) {
        const pulseStartMs = (time - this.ctx.currentTime) * 1000;
        const pulseEndMs = (time + duration - this.ctx.currentTime) * 1000;
        setTimeout(() => onPulse(type), Math.max(0, pulseStartMs));
        setTimeout(() => onPulse(null), Math.max(0, pulseEndMs));
      }

      // Attack
      this.gain.gain.setValueAtTime(0, time);
      this.gain.gain.linearRampToValueAtTime(this.volume, time + attack);
      
      time += duration;
      
      // Release
      this.gain.gain.setValueAtTime(this.volume, time);
      this.gain.gain.linearRampToValueAtTime(0, time + release);

      if (i < morseStr.length - 1) {
        time += intraCharGap;
      }
    }

    const finishTime = time + release;
    const waitTimeMs = (finishTime - this.ctx.currentTime) * 1000;
    
    const promise = new Promise(r => setTimeout(r, Math.max(0, waitTimeMs)));
    promise.finishTime = finishTime;
    return promise;
  }

  async playSequence(sequence, morseDict, onCharPlay = null, onPulse = null) {
    this.init();
    let isCancelled = false;
    this.cancelTokens = this.cancelTokens || [];
    const token = { cancel: () => isCancelled = true };
    this.cancelTokens.push(token);

    try {
      const currentGapSpeed = this.gapWpm || 60;
      const gapDotLen = 6.0 / currentGapSpeed;
      
      const interCharGap = gapDotLen * 3; // Standard: 3 dots
      const wordGap = gapDotLen * 7;      // Standard: 7 dots
      const extraWordGap = wordGap - interCharGap; // 4 extra dots for a total of 7

      let nextStartTime = this.ctx.currentTime + 0.1;

      for (let i = 0; i < sequence.length; i++) {
        if (isCancelled) break;
        const char = sequence[i];
        
        if (char === ' ') {
          nextStartTime += extraWordGap; 
          continue;
        }
        
        const morsePattern = Object.keys(morseDict).find(k => morseDict[k] === char);
        if (morsePattern) {
          if (onCharPlay) {
            const charDelayMs = (nextStartTime - this.ctx.currentTime) * 1000;
            setTimeout(() => onCharPlay(char), Math.max(0, charDelayMs));
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

  stopAll() {
    if (this.cancelTokens) {
      this.cancelTokens.forEach(t => t.cancel());
      this.cancelTokens = [];
    }
    if (this.gain && this.ctx) {
      this.gain.gain.cancelScheduledValues(this.ctx.currentTime);
      this.gain.gain.setValueAtTime(this.gain.gain.value, this.ctx.currentTime);
      this.gain.gain.linearRampToValueAtTime(0, this.ctx.currentTime + 0.005);
    }
  }
}

export const audioEngine = new MorseAudioEngine();
