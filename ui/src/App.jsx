import React, { useState, useRef, useEffect } from 'react';
import { Zap, Speaker, Radio, Headphones } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { Transmission } from './Transmission';
import { Reception } from './Reception';
import { UpdateChecker } from './UpdateChecker';
import { sounds } from './utils/sounds';
import './App.css';

function App() {
  const [activeTab, setActiveTab] = useState('transmission'); // 'transmission' or 'reception'
  const [frequency, setFrequency] = useState(700);
  const [volume, setVolume] = useState(50);
  const [lang, setLang] = useState('RU');
  const [keyConnected, setKeyConnected] = useState(false);
  const [keyPressed, setKeyPressed] = useState(false);
  const [wsNode, setWsNode] = useState(null);
  const [isLoaded, setIsLoaded] = useState(false);
  const [showToast, setShowToast] = useState(false);
  
  const ws = useRef(null);

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
              <span className="label"><Speaker size={14} style={{marginBottom:'-2px'}}/> {volume}%</span>
              <input type="range" min="0" max="100" step="1" value={volume} onChange={(e) => updateVolume(parseInt(e.target.value))} />
            </div>

            <div className="lang-toggle">
              <button className={lang === 'RU' ? 'active' : ''} onClick={() => setLang('RU')}>RU</button>
              <button className={lang === 'EN' ? 'active' : ''} onClick={() => setLang('EN')}>EN</button>
            </div>

            <UpdateChecker />
          </div>
        </header>

        {/* Huge Tab Selection Overlay */}
        <div className="tab-selector">
          <button 
            className={`tab-btn ${activeTab === 'transmission' ? 'active' : ''}`}
            onClick={() => setActiveTab('transmission')}
          >
            <Radio size={18} /> ПЕРЕДАЧА
          </button>
          <button 
            className={`tab-btn ${activeTab === 'reception' ? 'active' : ''}`}
            onClick={() => setActiveTab('reception')}
          >
            <Headphones size={18} /> ПРИЕМ
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
            <Transmission frequency={frequency} volume={volume} lang={lang} ws={wsNode} />
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
            <Reception frequency={frequency} volume={volume} lang={lang} />
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
