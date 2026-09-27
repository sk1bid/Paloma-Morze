import React, { useState, useEffect, useRef } from 'react';
import { X, Radio, ArrowLeftRight, Activity, TriangleAlert } from 'lucide-react';
import { TapeDisplay } from './TapeDisplay';
import { audioEngine } from './audio';

// Same fixed timing as local Transmission: 15 WPM, dash from 2 units,
// "too long" judged against the operator's own last dot.
const WPM = 15;
const UNIT = 1200 / WPM;
const DASH_THRESHOLD = UNIT * 2;

// Classify one key press exactly like Transmission.jsx does
const classifyPress = (duration, lastDotDuration) => {
  if (duration >= DASH_THRESHOLD) {
    return (duration > lastDotDuration.current * 4.5) ? 'too-long' : 'dash';
  }
  lastDotDuration.current = duration; // Update rhythm based on last dot
  return 'dot';
};

export const RadioNetwork = ({
  user,
  participants,
  socket,
  ws,
  roomId,
  remoteSignal,
  lang = 'RU',
  transmissionKey = 'Space',
  onCollisionChange,
  onQuit
}) => {
  const [isLocalPressed, setIsLocalPressed] = useState(false);
  const localEvents = useRef([]);
  const remoteEvents = useRef([]);

  const lastLocalPressTime = useRef(Date.now());
  const lastRemotePressTime = useRef(Date.now());
  const localDotDuration = useRef(UNIT);
  const remoteDotDuration = useRef(UNIT);

  const correspondent = participants?.find(p => p.callsign?.toUpperCase() !== user?.callsign?.toUpperCase());
  const correspondentCallsign = correspondent?.callsign || '...';

  // Sync Remote Signal Changes to Remote Timeline
  const prevRemoteSignal = useRef(0);
  useEffect(() => {
    const now = Date.now();
    if (remoteSignal === 1 && prevRemoteSignal.current === 0) {
      lastRemotePressTime.current = now;
    } else if (remoteSignal === 0 && prevRemoteSignal.current === 1) {
      const type = classifyPress(now - lastRemotePressTime.current, remoteDotDuration);
      remoteEvents.current.push({ start: lastRemotePressTime.current, end: now, type });
    }
    prevRemoteSignal.current = remoteSignal;
  }, [remoteSignal]);

  const emitMorse = (value) => {
    if (socket?.current && roomId) {
      socket.current.emit('morse_event', { roomId, value });
    }
  };

  const recordLocalRelease = (now) => {
    const type = classifyPress(now - lastLocalPressTime.current, localDotDuration);
    localEvents.current.push({ start: lastLocalPressTime.current, end: now, type });
  };

  // Handle Local Keyboard Input (SIMPLEX: never blocked, anyone may key at any time)
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.repeat) return;
      if (e.code === transmissionKey) {
        e.preventDefault();
        lastLocalPressTime.current = Date.now();
        setIsLocalPressed(true);
        audioEngine.init();
        audioEngine.keyDown('local');
        emitMorse(1);
      }
    };

    const handleKeyUp = (e) => {
      if (e.code === transmissionKey) {
        e.preventDefault();
        setIsLocalPressed(false);
        audioEngine.keyUp('local');
        emitMorse(0);
        recordLocalRelease(Date.now());
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [transmissionKey, socket, roomId]);

  // Handle Hardware Key Input via WebSocket.
  // Like local Transmission, the tone comes from the native engine sidetone only.
  useEffect(() => {
    // If ws is passed as a ref, pull the current object. If it's the socket itself, use it.
    const hwSocket = ws?.current || ws;
    if (!hwSocket) return;

    const handleHwMessage = (event) => {
      const val = event.data;
      if (val === '1') {
        lastLocalPressTime.current = Date.now();
        setIsLocalPressed(true);
        emitMorse(1);
      } else if (val === '0') {
        setIsLocalPressed(false);
        emitMorse(0);
        recordLocalRelease(Date.now());
      }
    };

    hwSocket.addEventListener('message', handleHwMessage);
    return () => hwSocket.removeEventListener('message', handleHwMessage);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ws, ws?.current, socket, roomId]);

  // SIMPLEX: the key is never blocked, but while the correspondent is on air the
  // hardware sidetone is muted so a collision is heard as the partner's tone only.
  useEffect(() => {
    const bridgeSocket = ws?.current || ws;
    if (bridgeSocket?.readyState === 1) bridgeSocket.send(remoteSignal === 1 ? 'M1' : 'M0');
  }, [ws, ws?.current, remoteSignal]);

  // Unmount only: ensure no sound leaks. Must not depend on ws.current - the bridge
  // reconnects periodically and a re-run would cut the tone while a key is held.
  useEffect(() => {
    return () => {
      audioEngine.keyUp();
      const bridgeSocket = ws?.current || ws;
      if (bridgeSocket?.readyState === 1) bridgeSocket.send('M0');
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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

  // Let the app light up the window frame while both stations key at once
  const isCollisionNow = isLocalPressed && remoteSignal === 1;
  useEffect(() => {
    onCollisionChange?.(isCollisionNow);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isCollisionNow]);
  useEffect(() => () => onCollisionChange?.(false), [onCollisionChange]);

  if (!user || !participants) return null;

  const remoteOn = remoteSignal === 1;
  const isCollision = isCollisionNow;
  const channelState = isCollision ? 'collision' : isLocalPressed ? 'transmitting' : remoteOn ? 'receiving' : 'idle';
  let statusText;
  if (isCollision) {
    statusText = lang === 'RU' ? 'НАКЛАДКА: ВЫ ПЕРЕБИВАЕТЕ ДРУГ ДРУГА!' : 'COLLISION: YOU ARE TALKING OVER EACH OTHER!';
  } else if (isLocalPressed) {
    statusText = lang === 'RU' ? 'ВЫ В ЭФИРЕ (ПЕРЕДАЧА)' : 'YOU ARE ON AIR (TRANSMITTING)';
  } else if (remoteOn) {
    statusText = lang === 'RU' ? `ПРИЕМ: В ЭФИРЕ ${correspondentCallsign}` : `RECEIVING: ${correspondentCallsign} ON AIR`;
  } else {
    statusText = lang === 'RU' ? 'СИМПЛЕКС: ЭФИР СВОБОДЕН' : 'SIMPLEX: CHANNEL CLEAR';
  }

  return (
    <div className="radio-network-mode">
      <div className="network-top-bar">
        <div className="bar-left">
          <Activity size={14} className="pulsing-icon" />
          <span className="network-label-small">{lang === 'RU' ? 'ПРЯМОЙ ЭФИР' : 'LIVE CHANNEL'}</span>
          <div className="bar-separator"></div>
          <Radio size={14} className="dim-icon" />
          <span className="correspondent-name-small">{correspondentCallsign}</span>
        </div>

        <div className="bar-right">
          <button className="quit-network-btn-small" onClick={onQuit} title={lang === 'RU' ? 'Выйти' : 'Exit'}>
            <X size={18} />
          </button>
        </div>
      </div>

      <div className="dual-timeline-container">
        {/* TOP: YOUR TAPE - identical to local Transmission */}
        <section className="scrolling-tape-container">
          <TapeDisplay
            events={localEvents}
            isPressed={isLocalPressed}
            lastPressTime={lastLocalPressTime}
            wpm={WPM}
            dashThreshold={DASH_THRESHOLD}
            label={lang === 'RU' ? 'ВЫ' : 'YOU'}
          />
        </section>

        <div className="timeline-divider">
          <ArrowLeftRight size={24} className="divider-icon" />
        </div>

        {/* BOTTOM: CORRESPONDENT TAPE */}
        <section className="scrolling-tape-container">
          <TapeDisplay
            events={remoteEvents}
            isPressed={remoteOn}
            lastPressTime={lastRemotePressTime}
            wpm={WPM}
            dashThreshold={DASH_THRESHOLD}
            label={correspondentCallsign}
          />
        </section>
      </div>

      <div className={`network-footer-tip ${channelState}`} role="status">
        {isCollision && <TriangleAlert size={16} strokeWidth={2.25} />}
        <span>{statusText}</span>
      </div>
    </div>
  );
};
