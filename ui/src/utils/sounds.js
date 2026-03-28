/**
 * SoundManager uses the Web Audio API to synthesize interactive UI feedback
 * sounds. This approach ensures zero-latency and zero-weight for the app.
 */
class SoundManager {
    constructor() {
        this.ctx = null;
    }

    init() {
        if (!this.ctx) {
            this.ctx = new (window.AudioContext || window.webkitAudioContext)();
        }
    }

    playConnect() {
        this.init();
        const oscillator = this.ctx.createOscillator();
        const gain = this.ctx.createGain();

        oscillator.type = 'sine';
        // Gentle rising major triad (C5 -> E5 -> G5)
        const now = this.ctx.currentTime;
        oscillator.frequency.setValueAtTime(523.25, now); // C5
        oscillator.frequency.exponentialRampToValueAtTime(659.25, now + 0.05); // E5
        oscillator.frequency.exponentialRampToValueAtTime(783.99, now + 0.1); // G5

        gain.gain.setValueAtTime(0, now);
        gain.gain.linearRampToValueAtTime(0.1, now + 0.02);
        gain.gain.linearRampToValueAtTime(0, now + 0.15);

        oscillator.connect(gain);
        gain.connect(this.ctx.destination);

        oscillator.start();
        oscillator.stop(now + 0.2);
    }

    playDisconnect() {
        this.init();
        const oscillator = this.ctx.createOscillator();
        const gain = this.ctx.createGain();

        oscillator.type = 'sine';
        // Muted down-sweep (G4 -> C4)
        const now = this.ctx.currentTime;
        oscillator.frequency.setValueAtTime(392.00, now); // G4
        oscillator.frequency.exponentialRampToValueAtTime(261.63, now + 0.1); // C4

        gain.gain.setValueAtTime(0, now);
        gain.gain.linearRampToValueAtTime(0.1, now + 0.02);
        gain.gain.linearRampToValueAtTime(0, now + 0.2);

        oscillator.connect(gain);
        gain.connect(this.ctx.destination);

        oscillator.start();
        oscillator.stop(now + 0.25);
    }
}

export const sounds = new SoundManager();
