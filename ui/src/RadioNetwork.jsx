import React, { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, Radio, ArrowLeftRight, Activity } from 'lucide-react';
import { TapeDisplay } from './TapeDisplay';
import { audioEngine } from './audio';

export const RadioNetwork = ({ 
  user, 
  participants, 
  socket, 
  roomId, 
  remoteSignal, 
  lang = 'RU',
  transmissionKey = 'Space',
  wpm = 15,
  dashRatio = 3.0,
  onQuit
}) => {
  const [isLocalPressed, setIsLocalPressed] = useState(false);
  const localEvents = useRef([]);
  const remoteEvents = useRef([]);
  
  const lastLocalPressTime = useRef(Date.now());
  const lastRemotePressTime = useRef(Date.now());
  
  const correspondent = participants.find(p => p.callsign !== user.callsign);

  // Sync Remote Signal Changes to Remote Timeline
  const prevRemoteSignal = useRef(0);
  useEffect(() => {
    const now = Date.now();
    if (remoteSignal === 1 && prevRemoteSignal.current === 0) {
      lastRemotePressTime.current = now;
    } else if (remoteSignal === 0 && prevRemoteSignal.current === 1) {
      const duration = now - lastRemotePressTime.current;
      const unit = 1200 / 15; // Standard 15 WPM unit
      let type = 'dot';
      if (duration >= unit * 2) {
        type = (duration > unit * 4.5) ? 'too-long' : 'dash';
      }
      
      remoteEvents.current.push({ 
        start: lastRemotePressTime.current, 
        end: now, 
        type 
      });
    }
    prevRemoteSignal.current = remoteSignal;
  }, [remoteSignal]);

  // Handle Local Keyboard Input
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.repeat) return;
      if (e.code === transmissionKey) {
        e.preventDefault();
        const now = Date.now();
        lastLocalPressTime.current = now;
        setIsLocalPressed(true);
        audioEngine.init();
        audioEngine.keyDown();
        if (socket?.current && roomId) {
          socket.current.emit('morse_event', { roomId, value: 1 });
        }
      }
    };

    const handleKeyUp = (e) => {
      if (e.code === transmissionKey) {
        e.preventDefault();
        const now = Date.now();
        setIsLocalPressed(false);
        audioEngine.keyUp();
        if (socket?.current && roomId) {
          socket.current.emit('morse_event', { roomId, value: 0 });
        }
        
        const duration = now - lastLocalPressTime.current;
        const unit = 1200 / 15; // Standard 15 WPM visual unit
        let type = 'dot';
        if (duration >= unit * 2) {
          type = (duration > unit * 4.5) ? 'too-long' : 'dash';
        }
        
        localEvents.current.push({ 
          start: lastLocalPressTime.current, 
          end: now, 
          type 
        });
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, [transmissionKey, socket, roomId, wpm]);

  // Cleanup old events
  useEffect(() => {
    const cleanup = setInterval(() => {
      const now = Date.now();
      const cutoff = now - 15000;
      localEvents.current = localEvents.current.filter(ev => (ev.end || now) > cutoff);
      remoteEvents.current = remoteEvents.current.filter(ev => (ev.end || now) > cutoff);
    }, 5000);
    return () => clearInterval(cleanup);
  }, []);

  return (
    <div className="radio-network-mode">
      <div className="network-top-bar">
        <div className="bar-left">
          <Activity size={14} className="pulsing-icon" />
          <span className="network-label-small">{lang === 'RU' ? 'ПРЯМОЙ ЭФИР' : 'LIVE CHANNEL'}</span>
          <div className="bar-separator"></div>
          <Radio size={14} className="dim-icon" />
          <span className="correspondent-name-small">{correspondent?.callsign || '...'}</span>
        </div>
        
        <div className="bar-right">
          <button className="quit-network-btn-small" onClick={onQuit} title={lang === 'RU' ? 'Выйти' : 'Exit'}>
            <X size={18} />
          </button>
        </div>
      </div>

      <div className="dual-timeline-container">
        {/* TOP: YOUR TIMELINE */}
        <div className="timeline-section self">
          <div className="timeline-meta">
            <span className="owner-label">{lang === 'RU' ? 'ВЫ' : 'YOU'}</span>
            <div className={`active-indicator ${isLocalPressed ? 'on' : ''}`}></div>
          </div>
          <TapeDisplay 
            events={localEvents}
            isPressed={isLocalPressed}
            lastPressTime={lastLocalPressTime}
            wpm={15}
            height={140}
            colorMode="local"
          />
        </div>

        <div className="timeline-divider">
          <ArrowLeftRight size={24} className="divider-icon" />
        </div>

        {/* BOTTOM: CORRESPONDENT TIMELINE */}
        <div className="timeline-section remote">
          <div className="timeline-meta">
            <span className="owner-label">{correspondent?.callsign || '...'}</span>
            <div className={`active-indicator remote ${remoteSignal === 1 ? 'on' : ''}`}></div>
          </div>
          <TapeDisplay 
            events={remoteEvents}
            isPressed={remoteSignal === 1}
            lastPressTime={lastRemotePressTime}
            wpm={15}
            height={140}
            colorMode="remote"
          />
        </div>
      </div>
      
      <div className="network-footer-tip">
        {lang === 'RU' 
          ? 'НАЖИМАЙТЕ ПРОБЕЛ ДЛЯ ПЕРЕДАЧИ В ЭФИР' 
          : 'USE SPACEBAR TO TRANSMIT TO AIR'}
      </div>
    </div>
  );
};
