import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Zap, History, Speaker, Settings, Info } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { io } from 'socket.io-client';
import { audioEngine } from './audio';
import { MORSE_EN, MORSE_RU, MNEMONICS_RU as MNEMONICS } from './constants';
import { decodeMorse, getMnemonic, getQCodeMeaning } from './utils/morseProvider';
import { TapeDisplay } from './TapeDisplay';
import './App.css';


export const Transmission = ({ 
  frequency, volume, lang, ws, wpm: initialWpm, 
  setWpm: setWpmProp, transmissionKey, disabled, 
  customOverrides = {}, roomId, token, socketRef 
}) => {
  const [isPressed, setIsPressed] = useState(false);
  const [decodedText, setDecodedText] = useState('');
  const [lastMnemonic, setLastMnemonic] = useState('');
  const [morseBuffer, setMorseBuffer] = useState('');
  const [wpm, setWpm] = useState(15); // Reverted to fixed 15 for stability
  const isPressedRef = useRef(false); // Ref for stable animation loop
  
  const lastPressTime = useRef(Date.now());
  const lastDotDuration = useRef(1200 / wpm);
  const textScrollRef = useRef(null);
  const events = useRef([]); // {start, end, type}

  // WPM determines thresholds: 1 unit = 1200 / wpm (ms)
  const unit = 1200 / wpm;
  const dashThreshold = unit * 2; // Halfway between 1x and 3x
  const charGapThreshold = unit * 2.5; // Halfway between 1x and 3x (for gap)
  const wordGapThreshold = unit * 8; // User requested 8x standard
  const [previewChar, setPreviewChar] = useState('');
  const [previewMnemonic, setPreviewMnemonic] = useState('');

  // Auto-scroll text to bottom/right
  useEffect(() => {
    if (textScrollRef.current) {
      textScrollRef.current.scrollLeft = textScrollRef.current.scrollWidth;
    }
  }, [decodedText, morseBuffer]);

  // TapeDisplay uses refs and state from Transmission
  // Multiplayer signaling is now managed at the App level to support the Radio Direction mode.
  // We only emit the local pulse here if a socket and roomId are provided.
  useEffect(() => {
    if (socketRef && roomId) {
      socketRef.current?.emit('morse_event', { roomId, value: isPressed ? 1 : 0 });
    }
  }, [isPressed, roomId, socketRef]);

  useEffect(() => {
    // If ws is passed as a ref, pull the current object. If it's the socket itself, use it.
    const socket = ws?.current || ws;
    if (!socket) return;
    
    const handleMessage = (event) => {
      // INTERLOCK: Ignore hardware signals if the component is disabled (e.g., Online mode turn-taking)
      if (disabled) return;
      
      const val = event.data;
      const now = Date.now();
      const duration = now - lastPressTime.current;

      if (val === '1') {
        isPressedRef.current = true;
        setIsPressed(true);
      } else if (val === '0') {
        isPressedRef.current = false;
        setIsPressed(false);
        let type = 'dot';
        if (duration >= dashThreshold) {
          type = (duration > lastDotDuration.current * 4.5) ? 'too-long' : 'dash';
        } else {
          lastDotDuration.current = duration; // Update rhythm based on last dot
        }
        setMorseBuffer(prev => {
          const next = prev + (type === 'dot' ? '.' : '-');
          
          const char = decodeMorse(next, lang, customOverrides);
          setPreviewChar(char);
          
          setPreviewMnemonic(getMnemonic(char, lang, customOverrides)); // Live mnemonic preview
          return next;
        });
        events.current.push({ start: lastPressTime.current, end: now, type });
      }
      lastPressTime.current = now;
    };
    
    socket.addEventListener('message', handleMessage);
    return () => {
      socket.removeEventListener('message', handleMessage);
    };
  }, [lang, dashThreshold, charGapThreshold, ws, ws?.current, disabled]);

  // Keyboard Handling
  useEffect(() => {
    if (disabled) return; // Completely ignore shortcuts when disabled
    
    const handleKeyDown = (e) => {
      console.log('[Transmission] KeyDown:', e.code, 'Target:', transmissionKey);
      // Prevent repetition while holding key and browser shortcuts
      if (e.repeat) return;
      if (e.code === transmissionKey) {
        e.preventDefault();
        const now = Date.now();
        lastPressTime.current = now;
        isPressedRef.current = true;
        setIsPressed(true);
        audioEngine.init();
        audioEngine.keyDown();
      }
    };

    const handleKeyUp = (e) => {
      console.log('[Transmission] KeyUp:', e.code);
      if (e.code === transmissionKey) {
        e.preventDefault();
        const now = Date.now();
        const duration = now - lastPressTime.current;
        isPressedRef.current = false;
        setIsPressed(false);
        audioEngine.keyUp();

        // Process rhythm
        let type = 'dot';
        if (duration >= dashThreshold) {
          type = (duration > lastDotDuration.current * 4.5) ? 'too-long' : 'dash';
        } else {
          lastDotDuration.current = duration;
        }

        setMorseBuffer(prev => {
          const next = prev + (type === 'dot' ? '.' : '-');
          const char = decodeMorse(next, lang, customOverrides);
          setPreviewChar(char);
          setPreviewMnemonic(getMnemonic(char, lang, customOverrides));
          return next;
        });
        events.current.push({ start: lastPressTime.current, end: now, type });
        lastPressTime.current = now;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, [transmissionKey, dashThreshold, lang, disabled]);

  // Safety Reset when Transmission is disabled or hidden
  useEffect(() => {
    if (disabled) {
      isPressedRef.current = false;
      setIsPressed(false);
      audioEngine.keyUp();
    }
  }, [disabled]);


  // Handle Gaps (Characters and Words)
  useEffect(() => {
    const timer = setInterval(() => {
      if (isPressed) return;
      const gap = Date.now() - lastPressTime.current;

      // Character gap - finalize current character
      if (morseBuffer && gap > charGapThreshold) {
        decodeMorseChar(morseBuffer);
        setMorseBuffer('');
      }

      // Word gap - add a space (8x)
      if (!morseBuffer && decodedText && !decodedText.endsWith(' ') && gap > wordGapThreshold) {
        setDecodedText(prev => prev + ' ');
        setLastMnemonic(''); 
      }
    }, 50);
    return () => clearInterval(timer);
  }, [isPressed, morseBuffer, decodedText, charGapThreshold, wordGapThreshold]);

  // Periodic cleanup of off-screen events to keep memory lean
  useEffect(() => {
    const cleanup = setInterval(() => {
      const now = Date.now();
      const pixelsPerMs = wpm / 150;
      const rightMargin = 100;
      // Remove events that are more than 10 seconds off-screen to the left
      const cutoffTime = now - (12000 / pixelsPerMs); 
      events.current = events.current.filter(ev => (ev.end || now) > cutoffTime);
    }, 5000);
    return () => clearInterval(cleanup);
  }, [wpm]);

  const decodeMorseChar = (buffer) => {
    const char = decodeMorse(buffer, lang, customOverrides);
    const newText = decodedText + char;
    setDecodedText(newText);

    // Check for Q-code meaning in the recently typed text
    const qMeaning = getQCodeMeaning(newText);
    if (qMeaning) {
      setLastMnemonic(qMeaning);
    } else {
      setLastMnemonic(getMnemonic(char, lang, customOverrides));
    }

    setPreviewChar('');
    setPreviewMnemonic(''); // Clear preview when confirmed
  };

  return (
    <>


      <main>

          <section className="scrolling-tape-container">
            <TapeDisplay 
              events={events}
              isPressed={isPressed}
              lastPressTime={lastPressTime}
              wpm={15}
              dashThreshold={dashThreshold}
              lastDotDuration={lastDotDuration.current}
            />
          </section>

          <section className="output-panel">
            <div className="mnemonic-hint">
              {previewMnemonic && <span className="preview-mnemonic">{previewMnemonic}</span>}
              {!previewMnemonic && lastMnemonic && <motion.span initial={{y:10, opacity:0}} animate={{y:0, opacity:1}}>{lastMnemonic}</motion.span>}
              {!lastMnemonic && !previewMnemonic && morseBuffer && <span className="buffer-preview">{morseBuffer}</span>}
            </div>
            <div className="text-scroll-container" ref={textScrollRef}>
              <div className="text-display">
                {decodedText || (!previewChar && (
                  <span className="placeholder">
                    {lang === 'RU' ? 'НАЖМИТЕ ' : 'PRESS '} 
                    <span className="kb-key">{transmissionKey === 'Space' ? (lang === 'RU' ? 'ПРОБЕЛ' : 'SPACE') : transmissionKey.replace('Key', '')}</span>
                  </span>
                ))}
                {previewChar && <span className="preview-char">{previewChar}</span>}
                <motion.span animate={{ opacity: [0, 1, 0] }} transition={{ duration: 0.8, repeat: Infinity }} className="cursor">_</motion.span>
              </div>
            </div>
          </section>
        </main>

      <footer className="trans-footer">
        <div className="transmission-legend">
          <div className="legend-item"><div className="dot-sample dot-color"></div> <span>{lang === 'RU' ? 'ТОЧКА' : 'DOT'}</span></div>
          <div className="legend-item"><div className="dot-sample dash-color"></div> <span>{lang === 'RU' ? 'ТИРЕ' : 'DASH'}</span></div>
          <div className="legend-item"><div className="dot-sample error-color"></div> <span>{lang === 'RU' ? 'ПЕРЕДЕРЖАЛ' : 'TOO LONG'}</span></div>
        </div>
        <button className="clear-btn" onClick={() => { setDecodedText(''); setMorseBuffer(''); setLastMnemonic(''); events.current = []; }}>
          {lang === 'RU' ? 'ОЧИСТИТЬ' : 'CLEAR'}
        </button>
      </footer>
    </>
  );
};
