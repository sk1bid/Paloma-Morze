import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, Users, Lock, Unlock, LogOut, RefreshCw, X, Zap, Globe } from 'lucide-react';
import './App.css';
import { RELAY_URL } from './relayConfig';

const API_URL = `${RELAY_URL}/api`;

const LobbyBrowser = ({ 
  user, 
  onJoinRoom, 
  onLogout, 
  activeRoomId, 
  onLeaveRoom, 
  lang = 'RU',
  participants = [],
  currentRoomOwner,
  onStartSession,
  socketRef
}) => {
  const [lobbies, setLobbies] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [isPrivate, setIsPrivate] = useState(false);
  const [newRoomName, setNewRoomName] = useState('');
  const [newRoomPassword, setNewRoomPassword] = useState('');
  const [latency, setLatency] = useState(0);
  const [totalOnline, setTotalOnline] = useState(0);

  const fetchLobbies = async () => {
    // Only show loading on initial fetch to avoid flickering
    if (lobbies.length === 0) setLoading(true);
    try {
      const startTime = performance.now();
      const response = await axios.get(`${API_URL}/lobbies`);
      const endTime = performance.now();
      setLatency(endTime - startTime);
      setLobbies(response.data);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const getSignalBars = (ms) => {
    if (ms === 0) return 0;
    if (ms < 150) return 3;
    if (ms < 400) return 2;
    return 1;
  };

  useEffect(() => {
    fetchLobbies();

    const socket = socketRef?.current;
    if (socket) {
      socket.on('lobby_update', fetchLobbies);
      socket.on('global_online', (count) => {
        console.log('[Lobby] Global online updated:', count);
        setTotalOnline(count);
      });
    }

    // Safety polling every 15s
    const interval = setInterval(fetchLobbies, 15000);

    return () => {
      if (socket) {
        socket.off('lobby_update', fetchLobbies);
        socket.off('global_online');
      }
      clearInterval(interval);
    };
  }, [socketRef, socketRef?.current]);

  const [showPasswordPrompt, setShowPasswordPrompt] = useState(false);
  const [promptPassword, setPromptPassword] = useState('');
  const [joiningRoomId, setJoiningRoomId] = useState(null);

  const handleCreateRoom = async (e) => {
    e.preventDefault();
    const token = localStorage.getItem('paloma_token');
    try {
      const resp = await axios.post(`${API_URL}/lobbies`, {
        name: newRoomName,
        password: isPrivate ? newRoomPassword : '',
        owner: user.callsign,
        token
      });
      setShowCreateModal(false);
      onJoinRoom(resp.data.id, newRoomPassword);
    } catch (e) {
      alert('Ошибка при создании комнаты');
    }
  };

  const handleJoinClick = (lobby) => {
    if (lobby.hasPassword && activeRoomId !== lobby.id) {
      setJoiningRoomId(lobby.id);
      setShowPasswordPrompt(true);
      setPromptPassword('');
    } else {
      onJoinRoom(lobby.id);
    }
  };

  const handleJoinWithPassword = (e) => {
    e.preventDefault();
    onJoinRoom(joiningRoomId, promptPassword);
    setShowPasswordPrompt(false);
  };

  return (
    <div className="lobby-browser-tab">
      <motion.div 
        className="lobby-header-compact"
        initial={{ y: -10, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
      >
        <div className="active-user-status">
          <div className="status-dot pulsed"></div>
          <span className="user-callsign">{user.callsign}</span>
          {totalOnline > 0 && (
            <div className="online-tag">
              <span className="online-sep">/</span>
              {lang === 'RU' ? 'В СЕТИ' : 'ONLINE'}: {totalOnline}
            </div>
          )}
        </div>
        
        <div className="header-actions">
          {activeRoomId && (
            <button onClick={onLeaveRoom} className="action-btn-icon" title={lang === 'RU' ? 'Покинуть канал' : 'Leave Channel'}>
              <LogOut size={18} style={{ color: '#ff5555' }} />
            </button>
          )}
          <button onClick={fetchLobbies} className="action-btn-icon" title={lang === 'RU' ? 'Обновить' : 'Refresh'}>
            <RefreshCw size={18} className={loading ? 'spinning' : ''} />
          </button>
          {!activeRoomId && (
            <button onClick={() => setShowCreateModal(true)} className="create-channel-btn">
              <Plus size={16} /> {lang === 'RU' ? 'НОВЫЙ КАНАЛ' : 'NEW CHANNEL'}
            </button>
          )}
        </div>
      </motion.div>

      {activeRoomId ? (
        <div className="active-room-overlay">
          <motion.div 
            className="room-presence-card glass-panel"
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
          >
            <div className="presence-header">
              <Users size={20} className="glow-icon" />
              <h3>{lobbies.find(l => l.id === activeRoomId)?.name || (lang === 'RU' ? 'КАНАЛ' : 'CHANNEL')}</h3>
            </div>
            
            <div className="participants-list">
              {console.log('[LobbyBrowser] Rendering participants:', participants)}
              {participants.map(p => (
                <div key={p.id} className="participant-item">
                  <div className="participant-dot"></div>
                  <span className={`participant-callsign ${p.callsign === user?.callsign ? 'self-highlight' : ''}`}>
                    {p.callsign || 'UNKNOWN'}
                  </span>
                </div>
              ))}
              {participants.length < 2 && (
                <div className="waiting-placeholder">
                  <RefreshCw className="spinning" size={16} />
                  <span>{lang === 'RU' ? 'ОЖИДАНИЕ КОРРЕСПОНДЕНТА...' : 'WAITING FOR CORRESPONDENT...'}</span>
                </div>
              )}
            </div>

            {participants.length === 2 ? (
              user.callsign === currentRoomOwner ? (
                <motion.button 
                  className="launch-session-btn glow-button"
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={onStartSession}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                >
                  <Zap size={18} />
                  {lang === 'RU' ? 'ЗАПУСТИТЬ СЕССИЮ' : 'LAUNCH SESSION'}
                </motion.button>
              ) : (
                <div className="waiting-placeholder owner-waiting">
                  <RefreshCw className="spinning" size={16} />
                  <span>{lang === 'RU' ? 'ОЖИДАНИЕ ЗАПУСКА МАСТЕРОМ...' : 'WAITING FOR MASTER TO START...'}</span>
                </div>
              )
            ) : null}
          </motion.div>
        </div>
      ) : (
        <div className="lobbies-scroll-container">
          <div className="scanner-list">
            <div className="scanner-header">
              <span className="col-main">{lang === 'RU' ? 'АКТИВНЫЕ КАНАЛЫ' : 'ACTIVE CHANNELS'}</span>
              <span className="col-meta">{lang === 'RU' ? 'СТАТУС' : 'STATUS'}</span>
            </div>

            {loading ? (
              <div className="scanner-status-msg">
                <RefreshCw size={24} className="spinning" />
                <span>{lang === 'RU' ? 'СКАНИРОВАНИЕ ЭФИРА...' : 'SCANNING AIR...'}</span>
              </div>
            ) : lobbies.length === 0 ? (
              <div className="scanner-status-msg">
                <Users size={24} style={{ opacity: 0.3 }} />
                <span>{lang === 'RU' ? 'СИГНАЛОВ НЕ ОБНАРУЖЕНО' : 'NO SIGNALS DETECTED'}</span>
              </div>
            ) : (
              lobbies.map(lobby => (
                <motion.div 
                  key={lobby.id} 
                  className={`scanner-row ${activeRoomId === lobby.id ? 'active' : ''}`}
                  whileHover={{ x: 4, backgroundColor: 'rgba(255,255,255,0.05)' }}
                  onClick={() => handleJoinClick(lobby)}
                >
                  <div className="lobby-info">
                    <div className="room-name">{lobby.name}</div>
                    <div className="room-operator">{lang === 'RU' ? 'ОПЕРАТОР' : 'OPERATOR'}: {lobby.owner}</div>
                  </div>
                  <div className="lobby-meta-signals">
                    {lobby.hasPassword ? <Lock size={14} className="lock-icon" /> : <Unlock size={14} className="unlock-icon" />}
                    <div className="signal-bars" title={`Latency: ${Math.round(latency)}ms`}>
                      <div className={`bar ${getSignalBars(latency) >= 1 ? 'active' : ''}`}></div>
                      <div className={`bar ${getSignalBars(latency) >= 2 ? 'active' : ''}`}></div>
                      <div className={`bar ${getSignalBars(latency) >= 3 ? 'active' : ''}`}></div>
                    </div>
                  </div>
                </motion.div>
              ))
            )}
          </div>
        </div>
      )}

      <AnimatePresence>
        {showPasswordPrompt && (
          <div className="modal-overlay">
            <motion.div 
              className="modal-content-glass glass-panel"
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.9, opacity: 0 }}
              style={{ maxWidth: '320px' }}
            >
              <div className="modal-header">
                <h3>{lang === 'RU' ? 'ВХОД В КАНАЛ' : 'JOIN CHANNEL'}</h3>
                <button className="close-btn" onClick={() => setShowPasswordPrompt(false)}><X size={20} /></button>
              </div>
              <form onSubmit={handleJoinWithPassword} className="auth-form-compact">
                <p style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.5)', marginBottom: '15px' }}>
                  {lang === 'RU' ? 'ДАННЫЙ КАНАЛ ЗАЩИЩЕН ПАРОЛЕМ' : 'THIS CHANNEL IS PASSWORD PROTECTED'}
                </p>
                <input 
                  type="password" 
                  autoFocus
                  placeholder={lang === 'RU' ? 'ПАРОЛЬ' : 'PASSWORD'} 
                  value={promptPassword}
                  onChange={(e) => setPromptPassword(e.target.value)}
                  className="industrial-input"
                  required
                />
                <div className="modal-footer" style={{ marginTop: '20px', width: '100%' }}>
                  <button type="submit" className="confirm-btn glow-button">{lang === 'RU' ? 'ПОДКЛЮЧИТЬСЯ' : 'CONNECT'}</button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {showCreateModal && (
          <div className="modal-overlay">
            <motion.div 
              className="modal-content-glass glass-panel"
              initial={{ scale: 0.9, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.9, opacity: 0 }}
            >
              <div className="modal-header">
                <h3>{lang === 'RU' ? 'СОЗДАТЬ КАНАЛ' : 'CREATE CHANNEL'}</h3>
                <button className="close-btn" onClick={() => setShowCreateModal(false)}><X size={20} /></button>
              </div>

              <form onSubmit={handleCreateRoom} className="auth-form-compact">
                <input 
                  type="text" 
                  placeholder={lang === 'RU' ? 'НАЗВАНИЕ' : 'NAME'}
                  value={newRoomName}
                  onChange={(e) => setNewRoomName(e.target.value)}
                  className="industrial-input"
                  required
                />
                
                <div className="toggle-setting-row" style={{ margin: '15px 0' }}>
                  <label className="toggle-label">{lang === 'RU' ? 'ЗАКРЫТЫЙ КАНАЛ' : 'PRIVATE CHANNEL'}</label>
                  <div 
                    className={`industrial-toggle ${isPrivate ? 'active' : ''}`}
                    onClick={() => setIsPrivate(!isPrivate)}
                  >
                    <div className="toggle-slider"></div>
                  </div>
                </div>

                <AnimatePresence>
                  {isPrivate && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      style={{ overflow: 'hidden', width: '100%' }}
                    >
                      <input 
                        type="password" 
                        placeholder={lang === 'RU' ? 'ПАРОЛЬ' : 'PASSWORD'} 
                        value={newRoomPassword}
                        onChange={(e) => setNewRoomPassword(e.target.value)}
                        className="industrial-input"
                        required={isPrivate}
                      />
                    </motion.div>
                  )}
                </AnimatePresence>

                <div className="modal-footer" style={{ marginTop: '20px', width: '100%' }}>
                  <button type="submit" className="confirm-btn glow-button">{lang === 'RU' ? 'ЗАПУСТИТЬ' : 'LAUNCH'}</button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};

export default LobbyBrowser;
