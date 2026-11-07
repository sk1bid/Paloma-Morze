import React, { useEffect, useMemo, useRef, useState } from 'react';
import { DevelopmentTools } from './DevelopmentTools';
import '../App.css';
import './task5.css';
import './developmentController.css';

function controllerIPC() {
  try { return window.require?.('electron').ipcRenderer || null; }
  catch { return null; }
}

export function DevelopmentController() {
  const [ipc] = useState(controllerIPC);
  const [state, setState] = useState({ index: 0, status: 'idle', variant: null, blocked: true });
  const [error, setError] = useState('');
  const [automatic, setAutomatic] = useState(false);
  const current = useRef(state);
  useEffect(() => { current.current = state; }, [state]);
  const proxy = useMemo(() => ({
    get state() { return current.current; },
    developmentJump: index => ipc?.send('task5-dev:command', { type: 'jump', index }),
    developmentEnter: () => ipc?.send('task5-dev:command', { type: 'enter' }),
    developmentGroupError: () => ipc?.send('task5-dev:command', { type: 'group-error' })
  }), [ipc]);
  useEffect(() => {
    document.body.classList.add('task5-controller-body');
    const update = (_event, snapshot) => {
      setState(snapshot);
      if (['aborted', 'completed', 'interrupted'].includes(snapshot.status)) setAutomatic(false);
    };
    const failed = (_event, message) => { setError(message); if (message) setAutomatic(false); };
    ipc?.on('task5-dev:state', update);
    ipc?.on('task5-dev:error', failed);
    ipc?.send('task5-dev:controller-ready');
    return () => {
      ipc?.removeListener('task5-dev:state', update);
      ipc?.removeListener('task5-dev:error', failed);
      document.body.classList.remove('task5-controller-body');
    };
  }, [ipc]);
  useEffect(() => { document.documentElement.setAttribute('data-theme', state.theme || 'dark'); }, [state.theme]);
  return (
    <main className="task5-controller-root">
      <DevelopmentTools session={proxy} state={state} active={true} blocked={!ipc || state.blocked} automatic={automatic} setAutomatic={setAutomatic} onError={setError} />
      {!state.variant && <p role="status">Ожидание основного окна…</p>}
      {error && <p className="task5-error" role="alert">{error}</p>}
      <p className="task5-controller-help">Основное окно показывает обычный интерфейс тренировки. Закрытие этого окна останавливает только автопросмотр. Открыть управление снова: меню DEV.</p>
    </main>
  );
}
