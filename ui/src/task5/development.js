import { resolveStep } from './domain.js';

export function task5DevelopmentEnabled({ development = false, previewBuild = false, search = '' }) {
  return (development || previewBuild) && new URLSearchParams(search).get('task5dev') === '1';
}

// This history belongs only to an isolated developer session. It resolves the
// same adaptive authentication exchanges as normal operation without keying or
// playing the preceding messages. Paper reception is never marked accurate.
export function developmentPrefix(variant, index) {
  if (!Number.isInteger(index) || index < 0 || index >= variant.steps.length) throw new Error('Выберите существующий этап.');
  const attempts = [], events = [];
  for (const original of variant.steps.slice(0, index)) {
    const step = resolveStep(original, variant, attempts);
    const date = new Date().toISOString();
    if (['administrative', 'pause'].includes(step.kind)) {
      events.push({ date, stepID: step.id, kind: 'developerPrefix', detail: 'Этап пропущен для просмотра интерфейса' });
      continue;
    }
    const input = step.botMessage || step.expectedMessages[0];
    if (!input) continue;
    const received = step.direction === 'receive';
    attempts.push({ date, stepID: step.id, input, correct: true, errors: 0, aided: true, inputMethod: received ? 'bot' : 'development', developerReview: true });
    events.push({ date, stepID: step.id, kind: received ? 'botDone' : 'developerPrefix', detail: 'Синтетическое состояние только для просмотра DEV' });
  }
  return { attempts, events };
}
