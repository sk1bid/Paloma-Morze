class MorseAudioEngine {
  constructor() {
    this.ctx = null;
    this.osc = null;
    this.gain = null;
    this.frequency = 700;
    this.volume = 0.5;
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
    if (this.osc) this.osc.frequency.setTargetAtTime(freq, this.ctx.currentTime, 0.05);
  }

  setVolume(vol) {
    this.volume = vol / 100.0;
  }

  // Plays a single character's morse string (e.g. '.-')
  // wpm: Speed of the character itself
  // Return a Promise that resolves when the character finishes playing
  playString(morseStr, wpm = 20) {
    return new Promise(resolve => {
      this.init();
      const dotLen = 1.2 / wpm; // 1200 / wpm in seconds
      const dashLen = dotLen * 3;
      const intraCharGap = dotLen;
      const attack = 0.01; // 10ms linear attack 
      const release = 0.01; // 10ms linear release

      let time = this.ctx.currentTime + 0.01;

      for (let i = 0; i < morseStr.length; i++) {
        const symbol = morseStr[i];
        const duration = symbol === '-' ? dashLen : dotLen;

        // Force exactly 0 before attack
        this.gain.gain.setValueAtTime(0, time);
        // Ramp up to target volume linearly
        this.gain.gain.linearRampToValueAtTime(this.volume, time + attack);
        
        time += duration;
        
        // Hold volume until end of duration
        this.gain.gain.setValueAtTime(this.volume, time);
        // Ramp down to 0 linearly
        this.gain.gain.linearRampToValueAtTime(0, time + release);

        // Gap between dots/dashes
        if (i < morseStr.length - 1) {
          time += intraCharGap;
        }
      }

      // We add release padding to the timeout
      const totalDuration = (time + release) - this.ctx.currentTime;
      setTimeout(resolve, totalDuration * 1000);
    });
  }

  // Plays a sequence of characters with Farnsworth timing
  // charWpm: Speed of the dots/dashes
  // gapWpm: Speed of the gap between characters (usually slower, e.g., 10)
  async playSequence(sequence, morseDict, charWpm = 20, gapWpm = 10, onCharPlay = null) {
    this.init();
    let isCancelled = false;
    this.cancelTokens = this.cancelTokens || [];
    const token = { cancel: () => isCancelled = true };
    this.cancelTokens.push(token);

    const charGap = (1.2 / gapWpm) * 3; // 3 units of gapWpm for inter-character pause

    for (let char of sequence) {
      if (isCancelled) break;
      if (char === ' ') {
        await new Promise(r => setTimeout(r, charGap * 2.33 * 1000)); // Word gap
        continue;
      }
      
      const morsePattern = Object.keys(morseDict).find(k => morseDict[k] === char);
      if (morsePattern) {
        if (onCharPlay) onCharPlay(char);
        await this.playString(morsePattern, charWpm);
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
