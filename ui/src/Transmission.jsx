import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Play, Square, RotateCcw, Clock, AlertTriangle } from 'lucide-react';
// eslint-disable-next-line no-unused-vars
import { motion, AnimatePresence } from 'framer-motion';
import { audioEngine } from './audio';
import { decodeMorse, getMnemonic, getQCodeMeaning, getMorsePattern } from './utils/morseProvider';
import { TapeDisplay } from './TapeDisplay';
import { generateSequence } from './Reception';
import './App.css';

// External helper to bypass React compiler strict purity rules for Date.now
const getNow = () => Date.now();

export const Transmission = (props) => {
  const { 
    lang, ws, transmissionKey, disabled, 
    customOverrides = {}, roomId, socketRef 
  } = props;

  const [isPressed, setIsPressed] = useState(false);
  const [decodedText, setDecodedText] = useState('');
  const [lastMnemonic, setLastMnemonic] = useState('');
  const [morseBuffer, setMorseBuffer] = useState('');
  
  const wpm = 15; // Reverted to fixed 15 for stability
  const isPressedRef = useRef(false); // Ref for stable animation loop
  
  const lastPressTime = useRef(getNow());
  const lastDotDuration = useRef(1200 / wpm);
  const [lastDotDurationVal, setLastDotDurationVal] = useState(1200 / wpm);
  
  const textScrollRef = useRef(null);
  const events = useRef([]); // {start, end, type}

  // WPM determines thresholds: 1 unit = 1200 / wpm (ms)
  const unit = 1200 / wpm;
  const dashThreshold = unit * 2; // Halfway between 1x and 3x
  const charGapThreshold = unit * 2.5; // Halfway between 1x and 3x (for gap)
  const wordGapThreshold = unit * 8; // User requested 8x standard
  const [previewChar, setPreviewChar] = useState('');
  const [previewMnemonic, setPreviewMnemonic] = useState('');

  // New Radiogram States
  const [isRadiogramMode, setIsRadiogramMode] = useState(false);
  const [isSessionRunning, setIsSessionRunning] = useState(false);
  const [radiogramType, setRadiogramType] = useState('letters'); // 'letters' or 'digits'
  const [groupCount, setGroupCount] = useState(5);
  const [fullSequence, setFullSequence] = useState([]);
  const [currentPortionIndex, setCurrentPortionIndex] = useState(0);
  const [currentTargetIndex, setCurrentTargetIndex] = useState(0);
  const [portionStates, setPortionStates] = useState([]);
  const [currentPortion, setCurrentPortion] = useState([]);
  const [errorCount, setErrorCount] = useState(0);
  const [elapsedTime, setElapsedTime] = useState(0);
  const [showReport, setShowReport] = useState(false);

  // Refs for timer and active state
  const timerRef = useRef(null);
  const startTimeRef = useRef(null);

  // State Caching in Refs to prevent Gaps useEffect interval from restarting on every keypress
  const isRadiogramModeRef = useRef(isRadiogramMode);
  const isSessionRunningRef = useRef(isSessionRunning);
  const currentPortionRef = useRef(currentPortion);
  const currentTargetIndexRef = useRef(currentTargetIndex);
  const currentPortionIndexRef = useRef(currentPortionIndex);
  const fullSequenceRef = useRef(fullSequence);
  const decodedTextRef = useRef(decodedText);

  useEffect(() => { isRadiogramModeRef.current = isRadiogramMode; }, [isRadiogramMode]);
  useEffect(() => { isSessionRunningRef.current = isSessionRunning; }, [isSessionRunning]);
  useEffect(() => { currentPortionRef.current = currentPortion; }, [currentPortion]);
  useEffect(() => { currentTargetIndexRef.current = currentTargetIndex; }, [currentTargetIndex]);
  useEffect(() => { currentPortionIndexRef.current = currentPortionIndex; }, [currentPortionIndex]);
  useEffect(() => { fullSequenceRef.current = fullSequence; }, [fullSequence]);
  useEffect(() => { decodedTextRef.current = decodedText; }, [decodedText]);

  const getBasePool = useCallback(() => {
    if (radiogramType === 'digits') {
      return '0123456789'.split('');
    } else {
      if (lang === 'RU') {
        return 'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ'.split('');
      } else {
        return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
      }
    }
  }, [radiogramType, lang]);

  const loadNextPortion = useCallback((nextPortionIdx) => {
    const seq = fullSequenceRef.current;
    const startIdx = nextPortionIdx * 25;
    if (startIdx >= seq.length) {
      setIsSessionRunning(false);
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      setShowReport(true);
    } else {
      setCurrentPortionIndex(nextPortionIdx);
      setCurrentTargetIndex(0);
      const endIdx = Math.min(startIdx + 25, seq.length);
      const nextPortion = seq.slice(startIdx, endIdx);
      setCurrentPortion(nextPortion);
      setPortionStates(new Array(nextPortion.length).fill(undefined));
    }
  }, []);

  const decodeMorseChar = useCallback((buffer) => {
    const char = decodeMorse(buffer, lang, customOverrides);

    if (isRadiogramModeRef.current && isSessionRunningRef.current) {
      const portion = currentPortionRef.current;
      const targetIdx = currentTargetIndexRef.current;
      const targetChar = portion[targetIdx];
      if (!targetChar) return;

      const keyedPattern = getMorsePattern(char, customOverrides);
      const targetPattern = getMorsePattern(targetChar, customOverrides);

      if (keyedPattern === targetPattern) {
        setPortionStates(prev => {
          const next = [...prev];
          next[targetIdx] = 'correct';
          return next;
        });

        const nextIndex = targetIdx + 1;
        if (nextIndex >= portion.length) {
          loadNextPortion(currentPortionIndexRef.current + 1);
        } else {
          setCurrentTargetIndex(nextIndex);
        }
      } else {
        setPortionStates(prev => {
          const next = [...prev];
          next[targetIdx] = 'wrong';
          return next;
        });
        setErrorCount(prev => prev + 1);
      }

      setPreviewChar('');
      setPreviewMnemonic('');
      return;
    }

    setDecodedText(prev => {
      const nextText = prev + char;
      const qMeaning = getQCodeMeaning(nextText);
      if (qMeaning) {
        setLastMnemonic(qMeaning);
      } else {
        setLastMnemonic(getMnemonic(char, lang, customOverrides));
      }
      return nextText;
    });

    setPreviewChar('');
    setPreviewMnemonic(''); // Clear preview when confirmed
  }, [lang, customOverrides, loadNextPortion]);

  const startRadiogramSession = () => {
    if (isSessionRunning) {
      setIsSessionRunning(false);
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      return;
    }

    const pool = getBasePool();
    if (!pool || pool.length === 0) return;

    const totalCount = groupCount * 5;
    const sequence = generateSequence(pool, totalCount, 2, 5);
    
    setFullSequence(sequence);
    setCurrentPortionIndex(0);
    setCurrentTargetIndex(0);
    setErrorCount(0);
    setElapsedTime(0);
    setShowReport(false);

    const initialPortion = sequence.slice(0, 25);
    setCurrentPortion(initialPortion);
    setPortionStates(new Array(initialPortion.length).fill(undefined));

    setIsSessionRunning(true);
    startTimeRef.current = getNow();
  };

  const stopSessionCleanly = () => {
    setIsSessionRunning(false);
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  };

  // Auto-scroll text to bottom/right
  useEffect(() => {
    if (textScrollRef.current) {
      textScrollRef.current.scrollLeft = textScrollRef.current.scrollWidth;
    }
  }, [decodedText, morseBuffer]);

  // Multiplayer signaling
  useEffect(() => {
    if (socketRef && roomId) {
      socketRef.current?.emit('morse_event', { roomId, value: isPressed ? 1 : 0 });
    }
  }, [isPressed, roomId, socketRef]);

  // Serial Hardware connection logic
  useEffect(() => {
    const socket = ws?.current || ws;
    if (!socket) return;
    
    const handleMessage = (event) => {
      // INTERLOCK: Ignore hardware signals if the component is disabled
      if (disabled) return;
      
      const val = event.data;
      const now = getNow();
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
          setLastDotDurationVal(duration);
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
  }, [lang, dashThreshold, charGapThreshold, ws, ws?.current, disabled, customOverrides]);

  // Keyboard Handling
  useEffect(() => {
    if (disabled) return; // Completely ignore shortcuts when disabled
    
    const handleKeyDown = (e) => {
      if (e.repeat) return;
      if (e.code === transmissionKey) {
        e.preventDefault();
        const now = getNow();
        lastPressTime.current = now;
        isPressedRef.current = true;
        setIsPressed(true);
        audioEngine.init();
        audioEngine.keyDown();
      }
    };

    const handleKeyUp = (e) => {
      if (e.code === transmissionKey) {
        e.preventDefault();
        const now = getNow();
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
          setLastDotDurationVal(duration);
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
  }, [transmissionKey, dashThreshold, lang, disabled, customOverrides]);

  // Safety Reset when Transmission is disabled or hidden
  useEffect(() => {
    if (disabled) {
      isPressedRef.current = false;
      audioEngine.keyUp();
      setTimeout(() => {
        setIsPressed(false);
      }, 0);
    }
  }, [disabled]);

  // Handle Gaps (Characters and Words)
  useEffect(() => {
    const timer = setInterval(() => {
      if (isPressed) return;
      const gap = getNow() - lastPressTime.current;

      // Character gap - finalize current character
      if (morseBuffer && gap > charGapThreshold) {
        decodeMorseChar(morseBuffer);
        setMorseBuffer('');
      }

      // Word gap - add a space (8x) (only in free keying mode)
      const txt = decodedTextRef.current;
      if (!isRadiogramMode && !morseBuffer && txt && !txt.endsWith(' ') && gap > wordGapThreshold) {
        setDecodedText(prev => prev + ' ');
        setLastMnemonic(''); 
      }
    }, 50);
    return () => clearInterval(timer);
  }, [isPressed, morseBuffer, charGapThreshold, wordGapThreshold, isRadiogramMode, decodeMorseChar]);

  // Periodic cleanup of off-screen events to keep memory lean
  useEffect(() => {
    const cleanup = setInterval(() => {
      const now = getNow();
      const pixelsPerMs = wpm / 150;
      const cutoffTime = now - (12000 / pixelsPerMs); 
      events.current = events.current.filter(ev => (ev.end || now) > cutoffTime);
    }, 5000);
    return () => clearInterval(cleanup);
  }, [wpm]);

  // Timer Effect for Radiogram Mode
  useEffect(() => {
    if (isSessionRunning) {
      timerRef.current = setInterval(() => {
        setElapsedTime(Math.round((getNow() - startTimeRef.current) / 1000));
      }, 1000);
    } else {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    }
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [isSessionRunning]);

  // Safety cleanup on unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      audioEngine.keyUp();
    };
  }, []);

  return (
    <div className="transmission-container">
      {/* Sidebar Controls */}
      <div className="transmission-sidebar">
        <button
          className={`toggle-btn main-select ${isRadiogramMode ? 'active' : ''}`}
          onClick={() => {
            if (isSessionRunning) stopSessionCleanly();
            setIsRadiogramMode(!isRadiogramMode);
            setShowReport(false);
          }}
          style={{ marginBottom: '12px', padding: '12px 0' }}
        >
          {lang === 'RU' ? 'РАДИОГРАММА' : 'RADIOGRAM'}
        </button>

        {/* Character Type Toggle (Letters vs Digits) */}
        <div className="control-group" style={{ opacity: isRadiogramMode ? 1 : 0.3, marginBottom: '12px' }}>
          <label>{lang === 'RU' ? 'ТИП СИМВОЛОВ' : 'CHAR TYPE'}</label>
          <div className="lang-toggle" style={{ width: '100%', padding: '2px', background: 'rgba(0,0,0,0.3)', border: '1px solid var(--glass-border)', borderRadius: '10px', display: 'flex' }}>
            <button
              disabled={!isRadiogramMode || isSessionRunning}
              className={radiogramType === 'letters' ? 'active' : ''}
              onClick={() => setRadiogramType('letters')}
              style={{ flex: 1, padding: '8px 0', fontSize: '0.65rem', textTransform: 'uppercase', letterSpacing: '1px' }}
            >
              {lang === 'RU' ? 'БУКВЫ' : 'LETTERS'}
            </button>
            <button
              disabled={!isRadiogramMode || isSessionRunning}
              className={radiogramType === 'digits' ? 'active' : ''}
              onClick={() => setRadiogramType('digits')}
              style={{ flex: 1, padding: '8px 0', fontSize: '0.65rem', textTransform: 'uppercase', letterSpacing: '1px' }}
            >
              {lang === 'RU' ? 'ЦИФРЫ' : 'DIGITS'}
            </button>
          </div>
        </div>

        <div className="control-group" style={{ opacity: isRadiogramMode ? 1 : 0.3, marginBottom: '16px' }}>
          <label>{lang === 'RU' ? 'ГРУПП' : 'GROUPS'}</label>
          <div className="number-stepper">
            <button
              disabled={!isRadiogramMode || isSessionRunning}
              onClick={() => setGroupCount(Math.max(5, groupCount - 5))}
            >-</button>
            <span>{groupCount}</span>
            <button
              disabled={!isRadiogramMode || isSessionRunning}
              onClick={() => setGroupCount(Math.min(100, groupCount + 5))}
            >+</button>
          </div>
        </div>

        {isRadiogramMode && (
          <button
            className={`start-btn ${isSessionRunning ? 'stop' : ''}`}
            onClick={startRadiogramSession}
          >
            {isSessionRunning ? (
              <><Square size={16} /> {lang === 'RU' ? 'СТОП' : 'STOP'}</>
            ) : (
              <><Play size={16} /> {lang === 'RU' ? 'СТАРТ' : 'START'}</>
            )}
          </button>
        )}
      </div>

      {/* Main Area */}
      <div className="transmission-main">
        <main style={{ flexGrow: 1, display: 'flex', flexDirection: 'column' }}>
          <section className="scrolling-tape-container">
            <TapeDisplay 
              events={events}
              isPressed={isPressed}
              lastPressTime={lastPressTime}
              wpm={15}
              dashThreshold={dashThreshold}
              lastDotDuration={lastDotDurationVal}
            />
          </section>

          <section className="output-panel">
            {isRadiogramMode ? (
              !isSessionRunning ? (
                <div className="radiogram-placeholder">
                  <span className="start-hint">
                    {lang === 'RU' ? 'Нажмите СТАРТ для начала' : 'Press START to begin'}
                  </span>
                  <div style={{ fontSize: '14px', opacity: 0.5 }}>
                    {lang === 'RU' 
                      ? `Будет сгенерировано ${groupCount} групп по 5 символов`
                      : `Will generate ${groupCount} groups of 5 characters`
                    }
                  </div>
                </div>
              ) : (
                <div style={{ width: '100%', height: '100%', padding: '18px 24px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', justifyContent: 'space-between', alignItems: 'center' }}>
                  {/* Radiogram Stats Header */}
                  <div className="radiogram-stats-header">
                    <div className="radiogram-stat-item">
                      <span className="radiogram-stat-label">{lang === 'RU' ? 'Порция' : 'Chunk'}</span>
                      <span className="radiogram-stat-value">
                        {currentPortionIndex + 1} / {Math.ceil(fullSequence.length / 25)}
                      </span>
                    </div>
                    <div className="radiogram-stat-item">
                      <span className="radiogram-stat-label">{lang === 'RU' ? 'Время' : 'Time'}</span>
                      <span className="radiogram-stat-value">
                        {Math.floor(elapsedTime / 60)}:{(elapsedTime % 60).toString().padStart(2, '0')}
                      </span>
                    </div>
                    <div className="radiogram-stat-item">
                      <span className="radiogram-stat-label">{lang === 'RU' ? 'Ошибки' : 'Errors'}</span>
                      <span className="radiogram-stat-value" style={{ color: errorCount > 0 ? '#ff5555' : '#50fa7b' }}>
                        {errorCount}
                      </span>
                    </div>
                  </div>

                  {/* Radiogram Active Group Display */}
                  <div className="radiogram-display">
                    {(() => {
                      const groups = [];
                      for (let i = 0; i < currentPortion.length; i += 5) {
                        groups.push(currentPortion.slice(i, i + 5));
                      }
                      return groups.map((group, gIdx) => (
                        <div key={gIdx} className="radiogram-group">
                          {group.map((char, cIdx) => {
                            const globalIdx = gIdx * 5 + cIdx;
                            const state = portionStates[globalIdx]; // 'correct', 'wrong', undefined
                            const isCurrent = globalIdx === currentTargetIndex;
                            return (
                              <span key={cIdx} className={`radiogram-char ${state || ''} ${isCurrent ? 'current' : ''}`}>{char}</span>
                            );
                          })}
                        </div>
                      ));
                    })()}
                  </div>

                  {/* Radiogram Progress Bar */}
                  <div className="radiogram-progress-container">
                    <div 
                      className="radiogram-progress-bar" 
                      style={{ 
                        width: `${((currentPortionIndex * 25 + currentTargetIndex) / fullSequence.length) * 100}%` 
                      }} 
                    />
                  </div>
                </div>
              )
            ) : (
              // Free keying mode
              <>
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
              </>
            )}
          </section>
        </main>

        <footer className="trans-footer">
          <div className="transmission-legend">
            <div className="legend-item"><div className="dot-sample dot-color"></div> <span>{lang === 'RU' ? 'ТОЧКА' : 'DOT'}</span></div>
            <div className="legend-item"><div className="dot-sample dash-color"></div> <span>{lang === 'RU' ? 'ТИРЕ' : 'DASH'}</span></div>
            <div className="legend-item"><div className="dot-sample error-color"></div> <span>{lang === 'RU' ? 'ПЕРЕДЕРЖАЛ' : 'TOO LONG'}</span></div>
          </div>
          {!isRadiogramMode ? (
            <button className="clear-btn" onClick={() => { setDecodedText(''); setMorseBuffer(''); setLastMnemonic(''); events.current = []; }}>
              {lang === 'RU' ? 'ОЧИСТИТЬ' : 'CLEAR'}
            </button>
          ) : (
            <div style={{ fontSize: '11px', color: 'var(--text-secondary)', opacity: 0.6 }}>
              {isSessionRunning && (
                lang === 'RU' 
                  ? `Передавайте символы по очереди с помощью клавиши ${transmissionKey === 'Space' ? 'ПРОБЕЛ' : transmissionKey.replace('Key', '')} или ключа` 
                  : `Transmit characters one-by-one using the ${transmissionKey === 'Space' ? 'SPACE' : transmissionKey.replace('Key', '')} key or hardware key`
              )}
            </div>
          )}
        </footer>
      </div>

      {/* Radiogram Report Modal */}
      <AnimatePresence>
        {showReport && (
          <div className="report-overlay" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'fixed', inset: 0, zIndex: 9999 }}>
            <motion.div
              className="report-card glass-panel"
              initial={{ scale: 0.9, y: 20, opacity: 0 }}
              animate={{ scale: 1, y: 0, opacity: 1 }}
              exit={{ scale: 0.9, y: 20, opacity: 0 }}
              style={{ width: '400px', height: 'auto', maxHeight: '90vh', display: 'flex', flexDirection: 'column' }}
            >
              <h3 style={{ textTransform: 'uppercase', letterSpacing: '2px', color: 'var(--accent-color)', textAlign: 'center', marginBottom: '20px' }}>
                {lang === 'RU' ? 'РЕЗУЛЬТАТЫ ПЕРЕДАЧИ' : 'TRANSMISSION REPORT'}
              </h3>
              
              <div className="report-content" style={{ display: 'flex', flexDirection: 'column', gap: '16px', margin: '20px 0', flexGrow: 1 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '8px' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>{lang === 'RU' ? 'Всего символов' : 'Total characters'}:</span>
                  <span style={{ fontWeight: 'bold' }}>{fullSequence.length}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '8px' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>{lang === 'RU' ? 'Затраченное время' : 'Time elapsed'}:</span>
                  <span style={{ fontWeight: 'bold', fontFamily: 'JetBrains Mono, monospace' }}>
                    {Math.floor(elapsedTime / 60)}:{(elapsedTime % 60).toString().padStart(2, '0')}
                  </span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '8px' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>{lang === 'RU' ? 'Количество ошибок' : 'Error count'}:</span>
                  <span style={{ fontWeight: 'bold', color: errorCount > 0 ? '#ff5555' : '#50fa7b' }}>{errorCount}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '8px' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>{lang === 'RU' ? 'Точность' : 'Accuracy'}:</span>
                  <span style={{ fontWeight: 'bold', color: 'var(--accent-color)' }}>
                    {(() => {
                      const total = fullSequence.length;
                      if (total === 0) return '100%';
                      const acc = Math.max(0, Math.round(((total - errorCount) / total) * 100));
                      return `${acc}%`;
                    })()}
                  </span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '8px' }}>
                  <span style={{ color: 'var(--text-secondary)' }}>{lang === 'RU' ? 'Скорость передачи' : 'Transmission speed'}:</span>
                  <span style={{ fontWeight: 'bold', color: '#50fa7b' }}>
                    {(() => {
                      const mins = elapsedTime / 60;
                      if (mins <= 0) return '0 CPM';
                      const cpm = Math.round(fullSequence.length / mins);
                      const wpmValue = Math.round(cpm / 5);
                      return `${cpm} CPM (${wpmValue} WPM)`;
                    })()}
                  </span>
                </div>
              </div>

              <div style={{ display: 'flex', gap: '12px', marginTop: '20px' }}>
                <button 
                  className="start-btn" 
                  onClick={() => {
                    setShowReport(false);
                    startRadiogramSession();
                  }}
                  style={{ flex: 1 }}
                >
                  <RotateCcw size={16} /> {lang === 'RU' ? 'ПОВТОРИТЬ' : 'RETRY'}
                </button>
                <button 
                  className="start-btn stop" 
                  onClick={() => setShowReport(false)}
                  style={{ flex: 1 }}
                >
                  {lang === 'RU' ? 'ЗАКРЫТЬ' : 'CLOSE'}
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};
