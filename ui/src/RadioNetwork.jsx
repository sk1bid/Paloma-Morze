import React, { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, Radio, ArrowLeftRight, Activity } from 'lucide-react';
import { TapeDisplay } from './TapeDisplay';
import { audioEngine } from './audio';
import { decodeMorse } from './utils/morseProvider';

export const RadioNetwork = ({ 
  user, 
  participants, 
  socket, 
  ws,
  roomId, 
  remoteSignal, 
  lang = 'RU',
  transmissionKey = 'Space',
  wpm = 15,
  dashRatio = 3.0,
  initialTurnOwner = null,
  onQuit
}) => {
  const [isLocalPressed, setIsLocalPressed] = useState(false);
  const [turnOwnerId, setTurnOwnerId] = useState(null);
  const localEvents = useRef([]);
  const remoteEvents = useRef([]);
  
  const lastLocalPressTime = useRef(Date.now());
  const lastRemotePressTime = useRef(Date.now());
  const morseBuffer = useRef(''); // Robust buffer like in Transmission
  const turnSwitchTimeout = useRef(null);

  if (!user || !participants) return null;

  // ROBUST ID RESOLUTION: Try to find "me" in participants list first (server ground truth)
  // as user object in localStorage might be old or corrupted.
  const meInRoom = participants.find(p => p.callsign?.toUpperCase() === user.callsign?.toUpperCase());
  const myId = String(meInRoom?.userId || meInRoom?.id || user?.userId || user?.id);

  const correspondent = participants.find(p => p.callsign?.toUpperCase() !== user.callsign?.toUpperCase());

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

  // Sync turn ownership from server
  useEffect(() => {
    if (!socket?.current) return;
    
    // SYNC INITIAL TURN FROM PROP
    if (turnOwnerId === null && initialTurnOwner) {
      console.log(`[RadioNetwork] [SYNC] Setting initial turn owner from prop: ${initialTurnOwner}`);
      setTurnOwnerId(initialTurnOwner);
    }

    const handleTurnUpdate = (data) => {
      setTurnOwnerId(data.turnOwnerId);
      console.log(`[RadioNetwork] [DEBUG] Turn shifted to ${data.turnOwnerId}. Current myId: ${myId} (isMyTurn: ${String(data.turnOwnerId) === myId})`);
    };
    
    socket.current.on('turn_update', handleTurnUpdate);
    return () => socket.current.off('turn_update', handleTurnUpdate);
  }, [socket, initialTurnOwner, myId]);

  // Handle Local Keyboard Input
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.repeat) return;
      if (e.code === transmissionKey) {
        e.preventDefault();
        console.log(`[AUDIO] [LOCAL] KeyDown event detected. Turn owner: ${turnOwnerId}`);
        
        // INTERLOCK: Only transmit if it's your turn
        if (turnOwnerId !== null && String(turnOwnerId) !== myId) {
          console.log(`[AUDIO] [LOCAL] BLOCKED High-Level logic: Not my turn.`);
          return; 
        }

        console.log(`[AUDIO] [LOCAL] Accepting KeyDown. Calling Engines...`);
        if (turnSwitchTimeout.current) clearTimeout(turnSwitchTimeout.current);

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
        console.log(`[AUDIO] [LOCAL] KeyUp event detected. Turn owner: ${turnOwnerId}`);
        
        // Ignore if locked
        if (turnOwnerId !== null && String(turnOwnerId) !== myId) {
          console.log(`[AUDIO] [LOCAL] BLOCKED High-Level logic: Not my turn (for KeyUp). Potential Stick point!`);
          return; 
        }

        console.log(`[AUDIO] [LOCAL] Accepting KeyUp. Calling Engines...`);
        const now = Date.now();
        setIsLocalPressed(false);
        audioEngine.keyUp();
        if (socket?.current && roomId) {
          socket.current.emit('morse_event', { roomId, value: 0 });
        }
        
        const duration = now - lastLocalPressTime.current;
        const unit = 1200 / 15;
        let type = 'dot';
        if (duration >= unit * 2) {
          type = (duration > unit * 4.5) ? 'too-long' : 'dash';
        }
        
        localEvents.current.push({ 
          start: lastLocalPressTime.current, 
          end: now, 
          type 
        });

        // Robust Detection like in Transmission.jsx
        morseBuffer.current += (type === 'dot' ? '.' : '-');
        console.log(`[RadioNetwork] Morse buffer: ${morseBuffer.current}`);

        // After a "letter gap", decode and check for K
        turnSwitchTimeout.current = setTimeout(() => {
          const decoded = decodeMorse(morseBuffer.current, lang);
          console.log(`[RadioNetwork] Decoded char: "${decoded}"`);
          
          if (decoded === 'K' || decoded === 'К') {
            console.log("[RadioNetwork] CRITICAL: 'K' (Invitation to Transmit) detected! Passing turn...");
            socket.current.emit('pass_turn', { roomId });
          }
          
          morseBuffer.current = ''; // Always clear after character completion
        }, 400); // Letter gap threshold
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
      if (turnSwitchTimeout.current) clearTimeout(turnSwitchTimeout.current);
    };
  }, [transmissionKey, socket, roomId, wpm, turnOwnerId, myId]);
  
  // Handle Hardware Key Input via WebSocket
  useEffect(() => {
    // If ws is passed as a ref, pull the current object. If it's the socket itself, use it.
    const hwSocket = ws?.current || ws;
    if (!hwSocket) return;
    
    const handleHwMessage = (event) => {
      const isMyTurn = String(turnOwnerId) === myId;
      if (!isMyTurn) return; // Locked: Not my turn

      const val = event.data;
      const now = Date.now();
      
      if (val === '1') {
        lastLocalPressTime.current = now;
        setIsLocalPressed(true);
        audioEngine.init();
        audioEngine.keyDown();
        if (socket?.current && roomId) {
          socket.current.emit('morse_event', { roomId, value: 1 });
        }
      } else if (val === '0') {
        setIsLocalPressed(false);
        audioEngine.keyUp();
        if (socket?.current && roomId) {
          socket.current.emit('morse_event', { roomId, value: 0 });
        }
        
        const duration = now - lastLocalPressTime.current;
        const unit = 1200 / 15;
        let type = 'dot';
        if (duration >= unit * 2) {
          type = (duration > unit * 4.5) ? 'too-long' : 'dash';
        }
        
        localEvents.current.push({ 
          start: lastLocalPressTime.current, 
          end: now, 
          type 
        });

        morseBuffer.current += (type === 'dot' ? '.' : '-');
        
        // After a "letter gap", decode and check for K
        if (turnSwitchTimeout.current) clearTimeout(turnSwitchTimeout.current);
        turnSwitchTimeout.current = setTimeout(() => {
          const decoded = decodeMorse(morseBuffer.current, lang);
          if (decoded === 'K' || decoded === 'К') {
            socket.current.emit('pass_turn', { roomId });
          }
          morseBuffer.current = ''; 
        }, 400);
      }
    };
    
    hwSocket.addEventListener('message', handleHwMessage);
    return () => hwSocket.removeEventListener('message', handleHwMessage);
  }, [ws, ws?.current, turnOwnerId, myId, socket, roomId, lang]);

  // AUDIO SAFETY INTERLOCK: Stop tones immediately when turn is lost or component unmounts
  useEffect(() => {
    const isMyTurn = String(turnOwnerId) === myId;
    if (!isMyTurn) {
      console.log(`[RadioNetwork] Turn lost or not mine. Safety stop for audio.`);
      audioEngine.keyUp();
      setIsLocalPressed(false);
    }
    
    return () => {
      // Robust unmount cleanup: ensure no sound leaks when exiting the tab
      audioEngine.keyUp();
      setIsLocalPressed(false);
    };
  }, [turnOwnerId, myId]);

  useEffect(() => {
    console.log(`[RadioNetwork] [DEBUG] Turn shifted to ${turnOwnerId}. Current myId: ${myId}`);
  }, [turnOwnerId, myId]);

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
        {(() => {
          const isMyTurn = String(turnOwnerId) === myId;
          return (
            <div className={`timeline-section self ${isMyTurn ? 'is-talking' : 'is-listening'}`}>
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
          );
        })()}

        <div className="timeline-divider">
          <ArrowLeftRight size={24} className="divider-icon" />
        </div>

        {/* BOTTOM: CORRESPONDENT TIMELINE */}
        {(() => {
          const isRemoteTurn = turnOwnerId !== null && String(turnOwnerId) !== myId;
          return (
            <div className={`timeline-section remote ${isRemoteTurn ? 'is-talking' : 'is-listening'}`}>
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
          );
        })()}
      </div>
      
      <div className="network-footer-tip">
        {String(turnOwnerId) === myId 
          ? (lang === 'RU' ? 'ВАШ ВЫХОД. ПЕРЕДАЙТЕ "K" ( - . - ) ДЛЯ СМЕНЫ ОЧЕРЕДИ' : 'YOUR TURN. SEND "K" ( - . - ) TO PASS TURN')
          : (lang === 'RU' ? 'ПРИЕМ. ОЖИДАЙТЕ ВЫЗОВА...' : 'RECEIVING. WAITING FOR CALLSIGN...')
        }
      </div>
    </div>
  );
};
