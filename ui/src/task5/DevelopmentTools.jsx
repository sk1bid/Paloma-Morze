import React, { useEffect } from 'react';

export function DevelopmentTools({ session, state, active, blocked, automatic, setAutomatic, onError }) {
  const variant = state.variant;
  const last = (variant?.steps.length || 1) - 1;
  const index = Math.min(state.index, last);
  const perform = action => {
    setAutomatic(false);
    try { action(); onError(''); }
    catch (error) { onError(error.message); }
  };
  useEffect(() => {
    if (!automatic || !active || blocked || !variant) return;
    const timer = setInterval(() => {
      if (session.state.index >= variant.steps.length - 1) { setAutomatic(false); return; }
      try { session.developmentJump(session.state.index + 1); }
      catch (error) { onError(error.message); setAutomatic(false); }
    }, 3000);
    return () => clearInterval(timer);
  }, [automatic, active, blocked, session, variant, setAutomatic, onError]);
  return (
    <section className="lesson-header task5-development" aria-label="DEV: просмотр этапов">
      <strong>DEV · ЗАДАЧА №5</strong>
      <p>Изолированный просмотр · настройки и история не сохраняются</p>
      <label className="task5-field">Этап
        <select disabled={!variant || blocked} value={index} onChange={event => perform(() => session.developmentJump(Number(event.target.value)))}>
          {variant?.steps.map((step, i) => <option value={i} key={step.id}>{i + 1}. {step.title} · {step.direction === 'transmit' ? 'Передача' : step.direction === 'receive' ? 'Приём' : 'Действие'} [{step.id}]</option>)}
        </select>
      </label>
      <div className="task5-footer">
        <button className="toggle-btn" disabled={!variant || blocked || index === 0} onClick={() => perform(() => session.developmentJump(index - 1))}>Назад</button>
        <button className="toggle-btn" disabled={!variant || blocked || index === last} onClick={() => perform(() => session.developmentJump(index + 1))}>Далее</button>
        <button className="toggle-btn" disabled={!variant || blocked} onClick={() => perform(() => session.developmentEnter())}>Запустить этап</button>
        <button className={`toggle-btn ${automatic ? 'active' : ''}`} disabled={!variant || blocked} onClick={() => {
          if (automatic) { setAutomatic(false); return; }
          try { session.developmentJump(index === last ? 0 : index); setAutomatic(true); onError(''); }
          catch (error) { onError(error.message); }
        }}>{automatic ? 'Остановить автопросмотр' : 'Автопросмотр'}</button>
        <button className="toggle-btn" disabled={!variant || blocked} onClick={() => perform(() => session.developmentGroupError())}>Ошибка группы</button>
      </div>
      <p>{state.developmentPreview ? 'Просмотр без звука · «Запустить этап» включает обычный ключ и звук' : 'Обычное взаимодействие с выбранного этапа'}</p>
      {state.radiogramRecovery && <p>{state.radiogramRecovery.request}</p>}
    </section>
  );
}
