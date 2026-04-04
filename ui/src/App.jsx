import React, { useState, useRef, useEffect } from 'react';
import { Zap, Speaker, Radio, Headphones, Settings, X } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { Transmission } from './Transmission';
import { Reception } from './Reception';
import { UpdateChecker } from './UpdateChecker';
import { sounds } from './utils/sounds';
import './App.css';

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
  const [pauseFactor, setPauseFactor] = useState(() => loadSetting('pauseFactor', 1.0));

  const [showSettings, setShowSettings] = useState(false);
  const [keyConnected, setKeyConnected] = useState(false);
  const [keyPressed, setKeyPressed] = useState(false);
  const [wsNode, setWsNode] = useState(null);
  const [isLoaded, setIsLoaded] = useState(false);
  const [showToast, setShowToast] = useState(false);

  const ws = useRef(null);

  // Persistence Sync Effect
  useEffect(() => {
    const settings = { frequency, volume, lang, wpm, transWpm, dashRatio, pauseFactor };
    localStorage.setItem('paloma_morse_v1', JSON.stringify(settings));
  }, [frequency, volume, lang, wpm, transWpm, dashRatio, pauseFactor]);

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
      window.location.reload(); // Refresh to clean engine state
    }
  };

  // Initialize generic WebSocket for sending global audio settings to C++ engine
  useEffect(() => {
    ws.current = new WebSocket('ws://127.0.0.1:8080');

    // Safety fallback: Show UI after 2.5s even if WS is slow
    const loadTimeout = setTimeout(() => {
      setIsLoaded(true);
    }, 2500);

    ws.current.onopen = () => {
      console.log('Connected to Morse Engine via WebSocket');
      ws.current.send('F' + frequency);
      ws.current.send('V' + volume);
      clearTimeout(loadTimeout);
      setIsLoaded(true);
    };

    const handleAppMessage = (event) => {
      if (typeof event.data === 'string') {
        if (event.data === 'STATUS:CONNECTED') setKeyConnected(true);
        else if (event.data === 'STATUS:DISCONNECTED') { setKeyConnected(false); setKeyPressed(false); }
        else if (event.data === '1') setKeyPressed(true);
        else if (event.data === '0') setKeyPressed(false);
      }
    };
    ws.current.addEventListener('message', handleAppMessage);

    setWsNode(ws.current);

    return () => {
      if (ws.current) {
        ws.current.removeEventListener('message', handleAppMessage);
        ws.current.close();
      }
    };
  }, []);
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
      onClick={() => sounds.init()}
      onMouseDown={() => sounds.init()}
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
    </motion.div>
  );
}

export default App;
