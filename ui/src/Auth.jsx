import React, { useState } from 'react';
import axios from 'axios';
import { motion, AnimatePresence } from 'framer-motion';
import { User, Lock, ArrowRight } from 'lucide-react';
import './App.css';

const API_URL = 'http://5.128.203.189:3001/api/auth'; // Remote VPS IP

const Auth = ({ onAuthSuccess }) => {
  const [isLogin, setIsLogin] = useState(true);
  const [callsign, setCallsign] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const endpoint = isLogin ? '/login' : '/register';
      const response = await axios.post(`${API_URL}${endpoint}`, {
        callsign: callsign.toUpperCase(),
        password
      });

      const { token, user } = response.data;
      localStorage.setItem('paloma_token', token);
      localStorage.setItem('paloma_user', JSON.stringify(user));
      onAuthSuccess(user, token);
    } catch (err) {
      setError(err.response?.data?.error || 'Authentication failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-tab-wrapper">
      <motion.div 
        className="auth-card-premium"
        initial={{ y: 20, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.5 }}
      >
        <div className="auth-header">
          <h2 className="glow-text">{isLogin ? 'АВТОРИЗАЦИЯ' : 'РЕГИСТРАЦИЯ'}</h2>
          <p className="auth-subtitle">{isLogin ? 'ВВЕДИТЕ ВАШ ПОЗЫВНОЙ ДЛЯ ВЫХОДА В ЭФИР' : 'СОЗДАЙТЕ УЧЕТНУЮ ЗАПИСЬ ОПЕРАТОРА'}</p>
        </div>

        <form onSubmit={handleSubmit} className="auth-form" style={{ marginTop: '20px' }}>
          <div className="input-field">
            <User size={18} className="icon-accent" />
            <input 
              type="text" 
              placeholder="ПОЗЫВНОЙ" 
              value={callsign}
              onChange={(e) => setCallsign(e.target.value.toUpperCase())}
              className="industrial-input"
              required
            />
          </div>

          <div className="input-field">
            <Lock size={18} className="icon-accent" />
            <input 
              type="password" 
              placeholder="ПАРОЛЬ" 
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="industrial-input"
              required
            />
          </div>

          <AnimatePresence>
            {error && (
              <motion.div 
                className="auth-error"
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: 'auto', opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                style={{ overflow: 'hidden' }}
              >
                {error}
              </motion.div>
            )}
          </AnimatePresence>

          <button type="submit" className="auth-submit glow-button" disabled={loading} style={{ marginTop: '10px' }}>
            {loading ? 'СОЕДИНЕНИЕ...' : (isLogin ? 'ВОЙТИ' : 'ЗАРЕГИСТРИРОВАТЬ')}
            {!loading && <ArrowRight size={18} />}
          </button>
        </form>

        <div className="auth-footer" style={{ marginTop: '20px' }}>
          <button onClick={() => setIsLogin(!isLogin)} className="secondary-link">
            {isLogin ? 'НЕТ ПОЗЫВНОГО? РЕГИСТРАЦИЯ' : 'УЖЕ ЕСТЬ АККАУНТ? ВХОД'}
          </button>
        </div>
      </motion.div>
    </div>
  );
};

export default Auth;
