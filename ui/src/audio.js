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
    if (this.osc) this.osc.frequency.setValueAtTime(freq, this.ctx.currentTime);
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

  // Plays a single character's morse string (e.g. '.-')
  // onPulse: optional callback(null|'dot'|'dash')
  playString(morseStr, onPulse = null) {
    return new Promise(resolve => {
      this.init();
      const currentWpm = this.charWpm || 20;
      const dotLen = 6.0 / currentWpm; 
      const dashLen = dotLen * (this.dashRatio || 3.0);
      const intraCharGap = dotLen;
      const attack = 0.005; 
      const release = 0.005; 

      let time = this.ctx.currentTime + 0.01;

      for (let i = 0; i < morseStr.length; i++) {
        const symbol = morseStr[i];
        const type = symbol === '-' ? 'dash' : 'dot';
        const duration = symbol === '-' ? dashLen : dotLen;

        // Schedule pulse callbacks via timeouts (approximation to visual sync)
        if (onPulse) {
          const delayMs = (time - this.ctx.currentTime) * 1000;
          setTimeout(() => onPulse(type), delayMs);
          setTimeout(() => onPulse(null), delayMs + (duration * 1000));
        }

        this.gain.gain.setValueAtTime(0, time);
        this.gain.gain.linearRampToValueAtTime(this.volume, time + attack);
        
        time += duration;
        
        this.gain.gain.setValueAtTime(this.volume, time);
        this.gain.gain.linearRampToValueAtTime(0, time + release);

        if (i < morseStr.length - 1) {
          time += intraCharGap;
        }
      }

      const totalDuration = (time + release) - this.ctx.currentTime;
      setTimeout(resolve, totalDuration * 1000);
    });
  }

  // Plays a sequence of characters with Farnsworth timing
  async playSequence(sequence, morseDict, onCharPlay = null, onPulse = null) {
    this.init();
    let isCancelled = false;
    this.cancelTokens = this.cancelTokens || [];
    const token = { cancel: () => isCancelled = true };
    this.cancelTokens.push(token);

    for (let char of sequence) {
      if (isCancelled) break;
      
      // Calculate gaps and WPM dynamically in each iteration
      const currentGapWpm = this.gapWpm || 10;
      const charGap = (6.0 / currentGapWpm) * 3; 

      if (char === ' ') {
        await new Promise(r => setTimeout(r, charGap * 2.33 * 1000)); 
        continue;
      }
      
      const morsePattern = Object.keys(morseDict).find(k => morseDict[k] === char);
      if (morsePattern) {
        if (onCharPlay) onCharPlay(char);
        await this.playString(morsePattern, onPulse);
        await new Promise(r => setTimeout(r, charGap * 1000));
      }
    }

    this.cancelTokens = this.cancelTokens.filter(t => t !== token);
  }

  stopAll() {
    if (this.cancelTokens) {
      this.cancelTokens.forEach(t => t.cancel());
      this.cancelTokens = [];
    }
    if (this.gain) {
      this.gain.gain.cancelScheduledValues(this.ctx.currentTime);
      this.gain.gain.setValueAtTime(this.gain.gain.value, this.ctx.currentTime);
      this.gain.gain.linearRampToValueAtTime(0, this.ctx.currentTime + 0.005);
    }
  }
}

export const audioEngine = new MorseAudioEngine();
