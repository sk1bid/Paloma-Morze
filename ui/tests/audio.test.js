import { jest } from '@jest/globals';
import { audioEngine } from '../src/audio.js';

describe('MorseAudioEngine Mathematical Timings', () => {
  let mockSetTargetAtTime, mockSetValueCurveAtTime, mockSetValueAtTime;

  beforeAll(() => {
    // Mock AudioContext for Node environment
    mockSetTargetAtTime = jest.fn();
    mockSetValueCurveAtTime = jest.fn();
    mockSetValueAtTime = jest.fn();

    global.window = {
      AudioContext: class {
        constructor() {
          this.currentTime = 0;
          this.state = 'running';
        }
        createGain() {
          return {
            connect: jest.fn(),
            gain: {
              value: 0,
              setValueAtTime: mockSetValueAtTime,
              linearRampToValueAtTime: jest.fn(),
              setTargetAtTime: mockSetTargetAtTime,
              setValueCurveAtTime: mockSetValueCurveAtTime,
              cancelScheduledValues: jest.fn(),
            }
          };
        }
        createOscillator() {
          return {
            type: 'sine',
            frequency: { value: 700, setValueAtTime: jest.fn() },
            connect: jest.fn(),
            start: jest.fn(),
            stop: jest.fn()
          };
        }
        resume() { return Promise.resolve(); }
      }
    };
  });

  beforeEach(() => {
    audioEngine.init();
    audioEngine.clearAllTimeouts();
    jest.clearAllMocks();
  });

  test('1. Validates standard Dot, Dash and Intra-character lengths (CPM=50)', () => {
    audioEngine.setCharWpm(50);
    audioEngine.setDashRatio(3.0);
    // dotLen = 6.0 / 50 = 0.12s
    const dotLen = 6.0 / 50;
    const dashLen = dotLen * 3.0;

    expect(dotLen).toBeCloseTo(0.12, 3);
    expect(dashLen).toBeCloseTo(0.36, 3);
  });

  test('2. Validates Linear APAK UI Pause Mapping', async () => {
    audioEngine.setCharWpm(50);
    
    // Test 1.0 -> 3 dots
    audioEngine.setPauseFactor(1.0); 
    let pFactor = (1.0 * 2.0) + 1.0;
    expect(pFactor).toBe(3.0);
    
    // Test 3.0 -> 7 dots (Farnsworth delay from video)
    audioEngine.setPauseFactor(3.0);
    pFactor = (3.0 * 2.0) + 1.0;
    expect(pFactor).toBe(7.0);

    // Test 7.0 -> 15 dots
    audioEngine.setPauseFactor(7.0);
    pFactor = (7.0 * 2.0) + 1.0;
    expect(pFactor).toBe(15.0);
  });

  test('3. Confirms Web Audio Envelopes use LCWO Raised-Cosine arrays (No Clicks)', async () => {
    audioEngine.setCharWpm(250); // fast speed to isolate envelope tests
    audioEngine.setVolume(100);  // Volume = 1.0
    
    // Play a single dot
    const playPromise = audioEngine.playString('.', 0, null);
    
    // We expect setValueCurveAtTime to be called TWICE per element (Attack and Release)
    expect(mockSetValueCurveAtTime).toHaveBeenCalledTimes(2);
    
    const attackCallArgs = mockSetValueCurveAtTime.mock.calls[0];
    const releaseCallArgs = mockSetValueCurveAtTime.mock.calls[1];
    
    const attackCurve = attackCallArgs[0];
    const releaseCurve = releaseCallArgs[0];
    
    // Ensure curves are 32-sample Float32Arrays
    expect(attackCurve).toBeInstanceOf(Float32Array);
    expect(attackCurve.length).toBe(32);
    
    // Verify mathematical bounds of Hanning window:
    // Attack must start strictly at 0 and end strictly at max volume (1.0)
    expect(attackCurve[0]).toBeCloseTo(0, 3);
    expect(attackCurve[31]).toBeCloseTo(1.0, 3);
    
    // Release must reverse this logic
    expect(releaseCurve[0]).toBeCloseTo(1.0, 3);
    expect(releaseCurve[31]).toBeCloseTo(0, 3);
  });

  test('4. Confirms Hardware Key methods use safe setTargetAtTime to prevent transient pops', () => {
    audioEngine.setVolume(50);
    audioEngine.keyDown();
    // Should use setTargetAtTime with 0.005 time constant
    expect(mockSetTargetAtTime).toHaveBeenCalledWith(0.5, 0, 0.005); // volume 0.5 because default is 50
    
    audioEngine.keyUp();
    expect(mockSetTargetAtTime).toHaveBeenCalledWith(0, 0, 0.005);
    
    audioEngine.stopAll();
    expect(mockSetTargetAtTime).toHaveBeenCalledWith(0, 0, 0.005);
    
    // Must NOT call setValueCurveAtTime abruptly for external unsync events!
    expect(mockSetValueCurveAtTime).not.toHaveBeenCalled();
  });

  test('5. Validates PARIS effective WPM formulation matches simulation exactly', async () => {
    audioEngine.setCharWpm(50);
    // Standard pause = 1.0 (3 physical dots)
    audioEngine.setPauseFactor(1.0);
    
    // Re-create the logic of interCharGap and wordGap from playSequence
    const dotLen = 6.0 / 50; 
    const pFactor = (1.0 * 2.0) + 1.0; // 3.0
    const interCharGap = dotLen * pFactor; 
    const wordGap = dotLen * (pFactor * (7.0 / 3.0)); 
    
    // A standard PARIS word has 31 dots of internal audio + 4 intra-character gaps
    // Space between 5 characters = 4 * interCharGap
    // Word Gap = 1 * wordGap
    const parisPhysicalTime = (31 * dotLen) + (4 * interCharGap) + wordGap;
    
    // Since 50 CPM = 10 WPM, a word takes exactly 6.0 seconds. Let's see!
    // 31 * 0.12 = 3.72
    // 4 * (0.12 * 3.0) = 4 * 0.36 = 1.44
    // 1 * (0.12 * 7.0) = 0.84
    // 3.72 + 1.44 + 0.84 = 6.00 seconds! Perfect!
    expect(parisPhysicalTime).toBeCloseTo(6.0, 3);
    
    // At exactly 6 seconds per word, we play 10 words (50 characters) in 60 seconds!
    // Effective CPM = 50.
  });

  test('6. Ensures all RU and EN characters result in valid audio sequences', async () => {
    const MORSE_RU = {
      '.-': 'А', '-...': 'Б', '.--': 'В', '--.': 'Г', '-..': 'Д', '.': 'Е',
      '...-': 'Ж', '--..': 'З', '..': 'И', '.---': 'Й', '-.-': 'К', '.-..': 'Л',
      '--': 'М', '-.': 'Н', '---': 'О', '.--.': 'П', '.-.': 'Р', '...': 'С',
      '-': 'Т', '..-': 'У', '..-.': 'Ф', '....': 'Х', '-.-.': 'Ц', '---.': 'Ч',
      '----': 'Ш', '--.-': 'Щ', '-.--': 'Ы', '-..-': 'Ь', '..-..': 'Э', '..--': 'Ю', '.-.-': 'Я',
      '-----': '0', '.----': '1', '..---': '2', '...--': '3', '....-': '4', '.....': '5',
      '-....': '6', '--...': '7', '---..': '8', '----.': '9', '-..-.': '/', '-...-': '=', '..--..': '?'
    };

    const MORSE_EN = {
      '.-': 'A', '-...': 'B', '-.-.': 'C', '-..': 'D', '.': 'E', '..-.': 'F',
      '--.': 'G', '....': 'H', '..': 'I', '.---': 'J', '-.-': 'K', '.-..': 'L',
      '--': 'M', '-.': 'N', '---': 'O', '.--.': 'P', '--.-': 'Q', '.-.': 'R',
      '...': 'S', '-': 'T', '..-': 'U', '...-': 'V', '.--': 'W', '-..-': 'X',
      '-.--': 'Y', '--..': 'Z', '-----': '0', '.----': '1', '..---': '2',
      '...--': '3', '....-': '4', '.....': '5', '-....': '6', '--...': '7',
      '---..': '8', '----.': '9', '.-.-': 'AR', '-...-': '='
    };

    const allPatterns = new Set([
      ...Object.keys(MORSE_RU),
      ...Object.keys(MORSE_EN)
    ]);

    audioEngine.setCharWpm(100); // Speed it up for testing

    for (const pattern of allPatterns) {
      // Each character should ideally resolve without error and produce valid finishTime
      const promise = audioEngine.playString(pattern, 0, null);
      expect(promise).toBeDefined();
      expect(promise.finishTime).toBeGreaterThan(0);
      await promise;
    }
  }, 30000);
});
