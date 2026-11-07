import React, { useEffect, useRef, useState } from 'react';
import { Play, Square, X } from 'lucide-react';
import { audioEngine } from '../audio';
import { getMorsePattern, decodeMorse } from '../utils/morseProvider';
import { TapeDisplay } from '../TapeDisplay';
import { Task5Session } from './session';
import { task5ViewConfiguration, task5CorrectionNotice } from './viewSettings';
import { Task5Exchange } from './Task5Exchange';
import { currentRadiogramGroup } from './radiogramView';
import reference from './tdr.json';
import './task5.css';
const SETTINGS = 'paloma_task5_settings_v1',
  ARCHIVE = 'paloma_task5_session_v1';
function saved(key, fallback) {
  try {
    return JSON.parse(localStorage.getItem(key)) || fallback;
  } catch {
    return fallback;
  }
}
const clock = s => `${Math.floor(s / 60).toString().padStart(2, '0')}:${Math.floor(s % 60).toString().padStart(2, '0')}`;
function Stepper({
  label,
  value,
  onChange,
  min,
  max,
  step = 5,
  disabled
}) {
  return <div className="control-group"><label>{label}</label><div className="number-stepper"><button aria-label={`${label}: уменьшить`} disabled={disabled || value <= min} onClick={() => onChange(Math.max(min, value - step))}>-</button><span>{value}</span><button aria-label={`${label}: увеличить`} disabled={disabled || value >= max} onClick={() => onChange(Math.min(max, value + step))}>+</button></div></div>;
}
function Dialog({
  title,
  close,
  children
}) {
  const box = useRef(null);
  useEffect(() => {
    const previous = document.activeElement;
    box.current?.focus();
    const key = e => {
      if (e.key === 'Escape') {
        e.preventDefault();
        close();
      }
      if (e.key === 'Tab') {
        const focusable = [...box.current.querySelectorAll('button,input,textarea,select,[tabindex="0"]')].filter(x => !x.disabled);
        const first = focusable[0],
          last = focusable.at(-1);
        if (e.shiftKey && (document.activeElement === first || document.activeElement === box.current)) {
          e.preventDefault();
          last?.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first?.focus();
        }
      }
    };
    window.addEventListener('keydown', key);
    return () => {
      window.removeEventListener('keydown', key);
      previous?.focus();
    };
  }, [close]);
  return <div className="report-overlay task5-overlay" onMouseDown={e => {
    if (e.target === e.currentTarget) close();
  }}><section className="report-card glass-panel task5-dialog" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} ref={box}><div className="settings-header"><h3>{title}</h3><button className="close-btn" aria-label="Закрыть" onClick={close}><X size={20} /></button></div>{children}</section></div>;
}
function CallsignEditor({ configuration, variant, save }) {
  const [own, setOwn] = useState(configuration.ownCallsign || variant?.ownCallsign || '');
  const [bot, setBot] = useState(configuration.botCallsign || variant?.botCallsign || '');
  return <form onSubmit={event => { event.preventDefault(); save(own.trim().toUpperCase(), bot.trim().toUpperCase()); }}>
    <label className="task5-field">Вы<input autoFocus maxLength={8} value={own} onChange={event => setOwn(event.target.value.toUpperCase())} /></label>
    <label className="task5-field">Бот<input maxLength={8} value={bot} onChange={event => setBot(event.target.value.toUpperCase())} /></label>
    <button type="submit" className="toggle-btn">Готово</button>
  </form>;
}
export function Task5({
  active,
  disabled,
  ws,
  transmissionKey,
  customOverrides,
  development = false
}) {
  const [configuration, configure] = useState(() => task5ViewConfiguration(development ? {} : saved(SETTINGS, {})));
  const [state, setState] = useState(null);
  const [modal, showModal] = useState(null);
  const [uiError, setUIError] = useState('');
  const [developmentIPC] = useState(() => {
    if (!development) return null;
    try { return globalThis.window?.require?.('electron').ipcRenderer || null; }
    catch { return null; }
  });
  const keyDisplay = useRef(null);
  const pausedForTab = useRef(false);
  const overrides = useRef(customOverrides);
  useEffect(() => { overrides.current = customOverrides; }, [customOverrides]);
  // The constructor stores these providers; audio calls them after rendering.
  const [session] = useState(() => new Task5Session({
    cells: reference.cells,
    development,
    audio: audioEngine,
    pattern: c => c === '0' ? '-----' : getMorsePattern(c, overrides.current),
    decodePattern: p => decodeMorse(p, 'RU', overrides.current) === '?' && p !== '..--..' ? '�' : decodeMorse(p, 'RU', overrides.current),
    changed: setState,
    persist: data => {
      if (development) return;
      try {
        if (data.variant && data.status !== 'idle') localStorage.setItem(ARCHIVE, JSON.stringify(data));
      } catch { setUIError('Не удалось сохранить тренировку. Освободите место.'); }
    }
  }));
  const s = state || session.state,
    step = session.step,
    variant = s.variant;
  const running = session.active;
  const publishDevelopmentState = React.useCallback(() => {
    if (!developmentIPC) return;
    const current = session.state;
    developmentIPC.send('task5-dev:state', {
      index: current.index, status: current.status,
      developmentPreview: current.developmentPreview === true,
      variant: current.variant ? { steps: current.variant.steps.map(({ id, title, direction }) => ({ id, title, direction })) } : null,
      radiogramRecovery: current.radiogramRecovery ? { request: current.radiogramRecovery.request } : null,
      blocked: !active || disabled || !!modal,
      theme: document.documentElement.getAttribute('data-theme') || 'dark'
    });
  }, [developmentIPC, session, active, disabled, modal]);
  useEffect(() => {
    if (!development || !developmentIPC) return;
    const command = (_event, value) => {
      try {
        if (!active || disabled || modal) throw new Error('Закройте настройки и откройте вкладку задачи №5.');
        if (value?.type === 'jump' && Number.isInteger(value.index)) session.developmentJump(value.index);
        else if (value?.type === 'enter') session.developmentEnter();
        else if (value?.type === 'group-error') session.developmentGroupError();
        else throw new Error('Неизвестная команда DEV.');
        developmentIPC.send('task5-dev:error', '');
      } catch (error) { developmentIPC.send('task5-dev:error', error.message); }
      publishDevelopmentState();
    };
    const request = () => publishDevelopmentState();
    developmentIPC.on('task5-dev:command', command);
    developmentIPC.on('task5-dev:request-state', request);
    publishDevelopmentState();
    return () => {
      developmentIPC.removeListener('task5-dev:command', command);
      developmentIPC.removeListener('task5-dev:request-state', request);
    };
  }, [development, developmentIPC, session, active, disabled, modal, publishDevelopmentState]);
  useEffect(() => {
    publishDevelopmentState();
  }, [publishDevelopmentState, s.index, s.status, s.developmentPreview, s.radiogramRecovery, variant]);
  useEffect(() => {
    const panel = keyDisplay.current;
    if (panel) panel.scrollTop = panel.scrollHeight;
  }, [s.input, s.buffer]);
  useEffect(() => {
    if (session.state.variant) return;
    try { session.prepare(configuration); if (development) session.developmentJump(0); }
    catch (error) { setUIError(error.message); }
  }, [configuration, session, development]);
  useEffect(() => {
    if (development) return;
    try { localStorage.setItem(SETTINGS, JSON.stringify(configuration)); }
    catch { setUIError('Не удалось сохранить настройки. Освободите место.'); }
  }, [configuration, development]);
  useEffect(() => {
    const timer = setInterval(() => session.tick(), 30);
    return () => {
      clearInterval(timer);
      session.cancel();
    };
  }, [session]);
  useEffect(() => {
    if (!active && session.active && session.state.status !== 'paused') {
      session.pause();
      pausedForTab.current = true;
    } else if (active && pausedForTab.current) {
      session.resume();
      if (session.state.status !== 'paused') pausedForTab.current = false;
    }
  }, [active, session]);
  useEffect(() => {
    const message = event => {
      if (!active || disabled || modal) return;
      if (event.data === '1') session.down('hardware');
      if (event.data === '0') session.up('hardware');
      if (event.data === 'STATUS:DISCONNECTED') session.release();
    };
    ws?.addEventListener('message', message);
    return () => ws?.removeEventListener('message', message);
  }, [ws, active, disabled, modal, session]);
  useEffect(() => {
    const editable = e => /INPUT|TEXTAREA|SELECT/.test(e.target?.tagName) || e.target?.isContentEditable;
    const down = e => {
      if (!active || disabled || modal || editable(e) || e.code !== transmissionKey) return;
      e.preventDefault();
      if (!e.repeat) session.down('keyboard');
    };
    const up = e => {
      if (e.code === transmissionKey) session.up('keyboard');
    };
    const blur = () => {
      session.release();
      if (session.active) session.log('focusLost', 'Окно потеряло фокус; обмен продолжается');
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('blur', blur);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('blur', blur);
      session.release();
    };
  }, [active, disabled, modal, transmissionKey, session]);
  const updateConfiguration = next => {
    const updated = task5ViewConfiguration(next);
    configure(updated);
    try {
      session.prepare(updated, session.state.variant?.seed || String(Date.now()));
      setUIError('');
      return true;
    } catch (error) { setUIError(error.message); return false; }
  };
  const change = (key, value) => updateConfiguration({ ...configuration, [key]: value });
  const open = name => {
    session.release();
    showModal(name);
  };
  const close = React.useCallback(() => {
    showModal(null);
  }, []);
  const start = () => {
    try {
      setUIError('');
      session.start(task5ViewConfiguration(configuration), session.state.variant?.seed || String(Date.now()));
    } catch (e) {
      setUIError(e.message);
    }
  };
  const errors = s.attempts.filter(a => a.inputMethod !== 'bot' && !a.correct).reduce((sum, a) => sum + (a.errors || 1), 0);
  const summary = session.summary;
  const codeMessage = session.outgoingCodeMessage;
  const correctionNotice = task5CorrectionNotice(s.notice);
  const showingRadiogram = step?.direction === 'transmit' && step.bodyGroups > 0;
  return (
    <div className="reception-container task5-container">
      <aside className="reception-sidebar">
        <div className="reception-controls">
          <div className="control-group">
            <label>ВАША СТАНЦИЯ</label>
            <button className="toggle-btn" disabled={running} onClick={() => change('role', configuration.role === 'main' ? 'subordinate' : 'main')}>{configuration.role === 'main' ? 'ГЛАВНАЯ' : 'ПОДЧИНЁННАЯ'}</button>
          </div>
          <div className="control-group">
            <label>ТЕКСТ РАДИОГРАММЫ</label>
            <button className="toggle-btn" disabled={running} onClick={() => change('charset', configuration.charset === 'letters' ? 'digits' : 'letters')}>{configuration.charset === 'letters' ? 'БУКВЫ' : 'ЦИФРЫ'}</button>
          </div>
          <Stepper label="ПЕРЕДАТЬ ГРУПП" value={configuration.groups} min={30} max={60} step={30} disabled={running} onChange={n => change('groups', n)} />
          <div className="sidebar-separator" role="separator" />
          <Stepper label="СКОРОСТЬ БОТА" value={configuration.botSpeed} min={30} max={150} disabled={running} onChange={n => change('botSpeed', n)} />
          <div className="sidebar-separator" role="separator" />
          <div className="control-group">
            <label>ПОЗЫВНЫЕ</label>
            <button className="toggle-btn active" disabled={running} onClick={() => open('callsigns')}>ВЫ · {variant?.ownCallsign || configuration.ownCallsign}</button>
            <button className="toggle-btn" disabled={running} onClick={() => open('callsigns')}>БОТ · {variant?.botCallsign || configuration.botCallsign}</button>
          </div>
        </div>
        <button className={`start-btn ${running ? 'stop' : ''}`} onClick={() => running ? session.stop() : start()}>{running ? <Square size={16} /> : <Play size={16} />}{running ? 'СТОП' : 'СТАРТ'}</button>
      </aside>
      <main className={`reception-main task5-main${showingRadiogram ? ' task5-radiogram-main' : ''}`}>
        <section className="scrolling-tape-container" aria-label="Лента передачи">
          <TapeDisplay events={s.tape} isPressed={s.pressed} lastPressTime={session.pressedDate || 0} wpm={(variant?.configuration.keySpeed || configuration.keySpeed) / 5} dashThreshold={12000 / (variant?.configuration.keySpeed || configuration.keySpeed)} height={showingRadiogram ? 60 : 100} />
        </section>
        <div className="lesson-header task5-key-display" aria-label="Переданный текст" ref={keyDisplay}>
          <p className="task5-input" aria-live="off">{s.input}{s.buffer && <span> {s.buffer}</span>}</p>
        </div>
        {(uiError || s.error) && <p className="task5-error" role="alert">{uiError || s.error}</p>}
        <div className="task5-workspace">
          {running ? <Task5Exchange step={step} variant={variant} recovery={s.radiogramRecovery} codeMessage={codeMessage} decodedReceivedCodes={s.decodedReceivedCodes} correctionNotice={correctionNotice} status={s.status} response={session.target?.expectedMessages[0]} currentGroup={showingRadiogram && !s.radiogramRecovery ? currentRadiogramGroup(s.input, step.bodyGroups) : null} /> : s.status === 'idle' ? <div className="task5-idle">Нажмите Старт</div> : <div className="task5-result">
            <h3>{s.status === 'completed' ? 'Обмен завершён' : s.status === 'interrupted' ? 'Обмен прерван' : 'Тренировка остановлена'}</h3>
            <p>{clock(s.elapsed)}</p>
            <p>Передано групп: {summary.transmittedGroups} / {summary.totalTransmitGroups} · Принято без ошибок: {variant?.configuration.receptionMode === 'paper' ? 'Не проверено' : `${summary.receivedGroups} / ${summary.totalReceiveGroups}`}</p>
            <p>Пройдено этапов: {summary.completedSteps} / {summary.totalSteps}</p>
            <p>Ошибок: {errors} · Повторов: {s.repeats}</p>
            <button className="toggle-btn" onClick={() => {
              const next = task5ViewConfiguration(variant.configuration);
              configure(next);
              try { session.start(next, variant.seed); }
              catch (error) { setUIError(error.message); }
            }}>Повторить этот вариант</button>
          </div>}
        </div>
        <div className="task5-footer">
          {running && <button className={`toggle-btn task5-key ${s.pressed ? 'active' : ''}`} disabled={s.status !== 'running' || !!s.remaining || disabled} aria-label="Телеграфный ключ" aria-pressed={s.pressed} onPointerDown={event => {
            event.preventDefault(); event.currentTarget.setPointerCapture(event.pointerId); session.down('pointer');
          }} onPointerUp={() => session.up('pointer')} onPointerCancel={() => session.release()} onLostPointerCapture={() => session.up('pointer')}>КЛЮЧ · {transmissionKey}</button>}
        </div>
      </main>
      {modal && <Dialog title="Позывные" close={close}>
        <CallsignEditor configuration={configuration} variant={variant} save={(ownCallsign, botCallsign) => {
          updateConfiguration({ ...configuration, ownCallsign, botCallsign }); close();
        }} />
      </Dialog>}
    </div>
  );
}
