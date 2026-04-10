import React, { useState, useRef, useEffect } from 'react';
import { Zap, Speaker, Radio, Headphones, Settings, X } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { Transmission } from './Transmission';
import { Reception } from './Reception';
import { MORSE_RU, MORSE_EN, MNEMONICS_RU, MNEMONICS_EN } from './constants';
import { UpdateChecker } from './UpdateChecker';
import { sounds } from './utils/sounds';
import { audioEngine } from './audio';
import './App.css';

const CHARACTER_SETS = {
  'РУССКИЙ (RU)': 'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ'.split(''),
  'ENGLISH (EN)': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
  'ЦИФРЫ (DIGITS)': '0123456789'.split(''),
  'СИМВОЛЫ (SYMBOLS)': '/=?'.split('')
};

function App() {
  const [activeTab, setActiveTab] = useState('transmission'); // 'transmission' or 'reception'

  // Persistence Initialization
  const loadSetting = (key, defaultValue) => {
    const saved = localStorage.getItem('paloma_morse_v1');
    if (saved) {
      try {
        const parsed = JSON.parse(saved);
        let val = parsed[key] !== undefined ? parsed[key] : defaultValue;
        // Migration: if wpm is < 20, it's likely old WPM scale, convert to CPM (x5)
        if (key === 'wpm' && val < 20) val *= 5;
        return val;
      } catch (e) { console.error('Settings load error:', e); }
    }
    return defaultValue;
  };

  const [frequency, setFrequency] = useState(() => loadSetting('frequency', 700));
  const [volume, setVolume] = useState(() => loadSetting('volume', 50));
  const [lang, setLang] = useState(() => loadSetting('lang', 'RU'));
  const [wpm, setWpm] = useState(() => loadSetting('wpm', 50)); // Default to 50 Signs Per Minute (CPM) for Reception
  const [transWpm, setTransWpm] = useState(() => loadSetting('transWpm', 50)); // Independent Transmission WPM (reverted to 1200/wpm scale)
  const [dashRatio, setDashRatio] = useState(() => loadSetting('dashRatio', 3.0));
  const [pauseFactor, setPauseFactor] = useState(() => loadSetting('pauseFactor', 3.0));
  const [transmissionKey, setTransmissionKey] = useState(() => loadSetting('transmissionKey', 'Space'));
  const [customOverrides, setCustomOverrides] = useState(() => loadSetting('customOverrides', {}));
  const [isBindingKey, setIsBindingKey] = useState(false);

  const [showSettings, setShowSettings] = useState(false);
  const [keyConnected, setKeyConnected] = useState(false);
  const [keyPressed, setKeyPressed] = useState(false);
  const [wsNode, setWsNode] = useState(null);
  const [isLoaded, setIsLoaded] = useState(false);
  const [showToast, setShowToast] = useState(false);
  const [showCustomizer, setShowCustomizer] = useState(false);
  const [focusedField, setFocusedField] = useState(null); // Tracks which field is currently being edited

  const ws = useRef(null);
  const reconnectTimer = useRef(null);

  // Initialize generic WebSocket for sending global audio settings to C++ engine
  const connectWebSocket = () => {
    if (ws.current && (ws.current.readyState === WebSocket.OPEN || ws.current.readyState === WebSocket.CONNECTING)) return;
    
    console.log('[App] Connecting to Morse Engine...');
    const socket = new WebSocket('ws://127.0.0.1:8080');
    ws.current = socket;

    socket.onopen = () => {
      console.log('[App] Connected to Morse Engine');
      setKeyConnected(true);
      // Sync current settings immediately on connection
      socket.send('F' + frequency);
      socket.send('V' + volume);
      if (reconnectTimer.current) {
        clearTimeout(reconnectTimer.current);
        reconnectTimer.current = null;
      }
      setIsLoaded(true);
    };

    socket.onmessage = (event) => {
      if (typeof event.data === 'string') {
        if (event.data === 'STATUS:CONNECTED') setKeyConnected(true);
        else if (event.data === 'STATUS:DISCONNECTED') { setKeyConnected(false); setKeyPressed(false); }
        else if (event.data === '1') setKeyPressed(true);
        else if (event.data === '0') setKeyPressed(false);
      }
    };

    socket.onclose = () => {
      console.log('[App] WebSocket closed. Reconnecting in 2s...');
      setKeyConnected(false);
      setKeyPressed(false);
      scheduleReconnect();
    };

    socket.onerror = (err) => {
      console.error('[App] WebSocket error:', err);
      socket.close();
    };

    setWsNode(socket);
  };

  const scheduleReconnect = () => {
    if (reconnectTimer.current) return;
    reconnectTimer.current = setTimeout(() => {
      reconnectTimer.current = null;
      connectWebSocket();
    }, 2000);
  };

  useEffect(() => {
    connectWebSocket();

    // Listen for power resume from main process
    const { ipcRenderer } = window.require('electron');
    const handleResume = () => {
      console.log('[App] Received power-resume, checking connection...');
      if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
        connectWebSocket();
      }
    };
    ipcRenderer.on('power-resume', handleResume);

    // Safety fallback: Show UI after 2.5s even if WS is slow
    const loadTimeout = setTimeout(() => {
      setIsLoaded(true);
    }, 2500);

    return () => {
      ipcRenderer.removeListener('power-resume', handleResume);
      if (ws.current) {
        ws.current.onclose = null; // Prevent reconnect on intentional unmount
        ws.current.close();
      }
      if (reconnectTimer.current) clearTimeout(reconnectTimer.current);
    };
  }, []);

  // Global Key Binding Listener
  useEffect(() => {
    if (!isBindingKey) return;
    
    const handleKeyBind = (e) => {
      e.preventDefault();
      e.stopPropagation();
      setTransmissionKey(e.code);
      setIsBindingKey(false);
    };

    window.addEventListener('keydown', handleKeyBind, true);
    return () => window.removeEventListener('keydown', handleKeyBind, true);
  }, [isBindingKey]);

  // Persistence Sync Effect
  useEffect(() => {
    const settings = { frequency, volume, lang, wpm, transWpm, dashRatio, pauseFactor, transmissionKey, customOverrides };
    localStorage.setItem('paloma_morse_v1', JSON.stringify(settings));
  }, [frequency, volume, lang, wpm, transWpm, dashRatio, pauseFactor, transmissionKey, customOverrides]);

  const resetSettings = () => {
    if (confirm(lang === 'RU' ? 'СБРОСИТЬ ВСЕ НАСТРОЙКИ?' : 'RESET ALL SETTINGS?')) {
      localStorage.removeItem('paloma_morse_v1');
      setFrequency(700);
      setVolume(50);
      setLang('RU');
      setWpm(50);
      setTransWpm(50);
      setDashRatio(3.0);
      setPauseFactor(1.0);
      setTransmissionKey('Space');
      window.location.reload(); // Refresh to clean engine state
    }
  };

  // Play sounds and show toast on connection changes
  useEffect(() => {
    if (!isLoaded) return; // Don't play on initial load
    if (keyConnected) {
      sounds.playConnect();
      setShowToast(true);
      const timer = setTimeout(() => setShowToast(false), 3000);
      return () => clearTimeout(timer);
    } else {
      sounds.playDisconnect();
    }
  }, [keyConnected]);

  const freqTimer = useRef(null);
  const volTimer = useRef(null);

  const updateFrequency = (val) => {
    setFrequency(val);
    clearTimeout(freqTimer.current);
    freqTimer.current = setTimeout(() => {
      if (ws.current && ws.current.readyState === 1) ws.current.send('F' + val);
    }, 50);
  };

  const updateVolume = (val) => {
    setVolume(val);
    clearTimeout(volTimer.current);
    volTimer.current = setTimeout(() => {
      if (ws.current && ws.current.readyState === 1) ws.current.send('V' + val);
    }, 50);
  };

  return (
    <motion.div
      className="app-container"
      onClick={() => { sounds.init(); audioEngine.init(); }}
      onMouseDown={() => { sounds.init(); audioEngine.init(); }}
      initial={{ opacity: 0 }}
      animate={{ opacity: isLoaded ? 1 : 0 }}
      transition={{ duration: 0.8, ease: "easeOut" }}
    >
      <div className="glass-panel main-panel">

        {/* Global Settings Header */}
        <header className="main-header">
          <div className="logo">
            <Zap size={20} className="icon-zap" />
            <span>PALOMA MORSE</span>
            <div
              className={`connection-badge ${keyConnected ? (keyPressed ? 'active' : 'connected') : 'disconnected'}`}
              title={lang === 'RU'
                ? (keyConnected ? 'КЛЮЧ ПОДКЛЮЧЕН' : 'КЛЮЧ ОТКЛЮЧЕН')
                : (keyConnected ? 'KEY CONNECTED' : 'KEY DISCONNECTED')
              }
            >
              <div className="conn-dot"></div>
            </div>
          </div>

          <div className="header-controls">
            <div className="freq-control" title="Pitch (Tone Frequency)">
              <span className="label">{frequency} HZ</span>
              <input type="range" min="200" max="2000" step="25" value={frequency} onChange={(e) => updateFrequency(parseInt(e.target.value))} />
            </div>

            <div className="freq-control" title="Output Volume">
              <span className="label"><Speaker size={14} style={{ marginBottom: '-2px' }} /> {volume}%</span>
              <input type="range" min="0" max="100" step="1" value={volume} onChange={(e) => updateVolume(parseInt(e.target.value))} />
            </div>

            <button className={`gear-btn ${showSettings ? 'active' : ''}`} onClick={() => setShowSettings(!showSettings)}>
              <Settings size={20} />
            </button>

            <UpdateChecker />
          </div>
        </header>

        <AnimatePresence>
          {showSettings && (
            <motion.div
              className="settings-panel glass-panel"
              initial={{ x: 300, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              exit={{ x: 300, opacity: 0 }}
              transition={{ type: "spring", damping: 25, stiffness: 200 }}
            >
              <div className="settings-header">
                <h3>{lang === 'RU' ? 'НАСТРОЙКИ' : 'SETTINGS'}</h3>
                <button className="close-btn" onClick={() => setShowSettings(false)}><X size={20} /></button>
              </div>

              <div className="settings-content">
                <div className="setting-row">
                  <label>{lang === 'RU' ? 'ЯЗЫК ИНТЕРФЕЙСА' : 'LANGUAGE'}</label>
                  <div className="lang-toggle">
                    <button className={lang === 'RU' ? 'active' : ''} onClick={() => setLang('RU')}>RU</button>
                    <button className={lang === 'EN' ? 'active' : ''} onClick={() => setLang('EN')}>EN</button>
                  </div>
                </div>

                <div className="setting-row">
                  <label>{lang === 'RU' ? 'КЛАВИША ПЕРЕДАЧИ' : 'TRANSMISSION KEY'}</label>
                  <button 
                    className={`key-bind-btn ${isBindingKey ? 'binding' : ''}`}
                    onClick={() => setIsBindingKey(true)}
                  >
                    {isBindingKey 
                      ? (lang === 'RU' ? 'ОЖИДАНИЕ...' : 'WAITING...') 
                      : (transmissionKey === 'Space' ? 'SPACE' : transmissionKey.replace('Key', ''))
                    }
                  </button>
                </div>

                <div className="sidebar-separator" style={{ margin: '20px 0' }}></div>
                
                <div className="sidebar-separator" style={{ margin: '20px 0' }}></div>
                
                <button 
                  className="open-customizer-btn" 
                  onClick={() => setShowCustomizer(true)}
                >
                  <Zap size={16} />
                  {lang === 'RU' ? 'РЕДАКТОР КОДОВ' : 'MORSE EDITOR'}
                </button>

                <div className="sidebar-separator" style={{ margin: '20px 0' }}></div>

                <button className="reset-btn" onClick={resetSettings}>
                  {lang === 'RU' ? 'СБРОСИТЬ ВСЕ НАСТРОЙКИ' : 'RESET ALL SETTINGS'}
                </button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Huge Tab Selection Overlay */}
        <div className="tab-selector">
          <button
            className={`tab-btn ${activeTab === 'transmission' ? 'active' : ''}`}
            onClick={() => setActiveTab('transmission')}
          >
            <Radio size={18} /> {lang === 'RU' ? 'ПЕРЕДАЧА' : 'TRANSMISSION'}
          </button>
          <button
            className={`tab-btn ${activeTab === 'reception' ? 'active' : ''}`}
            onClick={() => setActiveTab('reception')}
          >
            <Headphones size={18} /> {lang === 'RU' ? 'ПРИЕМ' : 'RECEPTION'}
          </button>
        </div>

        {/* Persistent Content (Keep-alive) */}
        <div className="tab-content">
          <motion.div
            animate={{
              opacity: activeTab === 'transmission' ? 1 : 0,
              x: activeTab === 'transmission' ? 0 : -20,
              pointerEvents: activeTab === 'transmission' ? 'auto' : 'none'
            }}
            transition={{ duration: 0.3, ease: "easeInOut" }}
            className="tab-motion-wrapper"
          >
            <Transmission
              frequency={frequency}
              volume={volume}
              lang={lang}
              ws={wsNode}
              wpm={transWpm}
              setWpm={setTransWpm}
              dashRatio={dashRatio}
              pauseFactor={pauseFactor}
              transmissionKey={transmissionKey}
              disabled={showSettings}
              customOverrides={customOverrides}
            />
          </motion.div>

          <motion.div
            animate={{
              opacity: activeTab === 'reception' ? 1 : 0,
              x: activeTab === 'reception' ? 0 : 20,
              pointerEvents: activeTab === 'reception' ? 'auto' : 'none'
            }}
            transition={{ duration: 0.3, ease: "easeInOut" }}
            className="tab-motion-wrapper"
          >
            <Reception
              frequency={frequency}
              volume={volume}
              lang={lang}
              wpm={wpm}
              setWpm={setWpm}
              dashRatio={dashRatio}
              setDashRatio={setDashRatio}
              pauseFactor={pauseFactor}
              setPauseFactor={setPauseFactor}
              customOverrides={customOverrides}
            />
          </motion.div>
        </div>

      </div>

      {/* Connection Toast */}
      <AnimatePresence>
        {showToast && (
          <motion.div
            className="connection-toast"
            initial={{ opacity: 0, y: 50, scale: 0.9 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, scale: 0.9, transition: { duration: 0.2 } }}
          >
            <div className="toast-content">
              <Zap size={16} className="icon-zap" />
              <span>{lang === 'RU' ? 'КЛЮЧ ПОДКЛЮЧЕН' : 'KEY CONNECTED'}</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      {/* Morse Customizer Modal */}
      <AnimatePresence>
        {showCustomizer && (
          <motion.div 
            className="customizer-modal-overlay"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setShowCustomizer(false)}
          >
            <motion.div 
              className="customizer-modal"
              initial={{ scale: 0.9, opacity: 0, y: 20 }}
              animate={{ scale: 1, opacity: 1, y: 0 }}
              exit={{ scale: 0.9, opacity: 0, y: 20 }}
              onClick={(e) => e.stopPropagation()}
            >
              <div className="customizer-modal-header">
                <h2>{lang === 'RU' ? 'РЕДАКТОР КОДОВ И НАПЕВОВ' : 'MORSE & MNEMONIC EDITOR'}</h2>
                <button className="close-btn" onClick={() => setShowCustomizer(false)}><X size={24} /></button>
              </div>
              
              <div className="customizer-modal-content">
                <div className="customizer-table-header">
                  <div className="header-item" style={{ width: '40px', textAlign: 'center' }}>{lang === 'RU' ? 'ЗНАК' : 'CHAR'}</div>
                  <div style={{ width: '24px' }}></div> {/* Gap Match */}
                  <div className="header-item" style={{ width: '120px' }}>{lang === 'RU' ? 'КОД' : 'CODE'}</div>
                  <div style={{ width: '16px' }}></div> {/* Gap Match */}
                  <div className="header-item" style={{ flex: 1 }}>{lang === 'RU' ? 'НАПЕВ' : 'MNEMONIC'}</div>
                  <div className="header-item" style={{ width: '80px', textAlign: 'right' }}></div>
                </div>

                <div className="customizer-scroll-area">
                  {Object.entries(CHARACTER_SETS).map(([category, chars]) => (
                    <div key={category} className="customizer-category">
                      <div className="category-title">{category}</div>
                        {chars.map(char => {
                          // Determine language for placeholders
                          const isENRoot = category.includes('ENGLISH');
                          const isRURoot = category.includes('РУССКИЙ');
                          // For Digits/Symbols, follow global lang
                          const currentIsRU = isRURoot || (!isENRoot && lang === 'RU');
                          
                          const morseDict = currentIsRU ? MORSE_RU : MORSE_EN;
                          const mnemDict = currentIsRU ? MNEMONICS_RU : MNEMONICS_EN;
                          
                          const defaultCode = Object.keys(morseDict).find(k => morseDict[k] === char) || '';
                          const defaultMnemonic = mnemDict[defaultCode] || '';

                          return (
                            <div key={char} className="customizer-row">
                              <div className="row-char">{char}</div>
                              <div className="row-inputs">
                                <input 
                                  className="input-pattern"
                                  placeholder={defaultCode || '.-.-'}
                                  value={customOverrides[char]?.pattern !== undefined 
                                    ? customOverrides[char].pattern 
                                    : (focusedField === `${char}-code` ? defaultCode : '')}
                                  onFocus={() => setFocusedField(`${char}-code`)}
                                  onBlur={() => setFocusedField(null)}
                                  onChange={(e) => {
                                    const val = e.target.value.replace(/[^.-]/g, '');
                                    setCustomOverrides(prev => ({
                                      ...prev,
                                      [char]: { ...prev[char], pattern: val }
                                    }));
                                  }}
                                />
                                <input 
                                  className="input-mnemonic"
                                  placeholder={defaultMnemonic || '...'}
                                  value={customOverrides[char]?.mnemonic !== undefined 
                                    ? customOverrides[char].mnemonic 
                                    : (focusedField === `${char}-mnem` ? defaultMnemonic : '')}
                                  onFocus={() => setFocusedField(`${char}-mnem`)}
                                  onBlur={() => setFocusedField(null)}
                                  onChange={(e) => {
                                    // Space to Hyphen conversion and filtering
                                    const val = e.target.value.replace(/ /g, '-').replace(/[^a-zA-Zа-яА-ЯёЁ-]/g, '');
                                    setCustomOverrides(prev => ({
                                      ...prev,
                                      [char]: { ...prev[char], mnemonic: val }
                                    }));
                                  }}
                                />
                              </div>
                              <div className="row-actions">
                                {(customOverrides[char]?.pattern || customOverrides[char]?.mnemonic) && (
                                  <button 
                                    className="reset-row-btn"
                                    onClick={() => {
                                      const next = { ...customOverrides };
                                      delete next[char];
                                      setCustomOverrides(next);
                                    }}
                                  >
                                    {lang === 'RU' ? 'СБРОС' : 'RESET'}
                                  </button>
                                )}
                              </div>
                            </div>
                          );
                        })}
                    </div>
                  ))}
                </div>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

export default App;
