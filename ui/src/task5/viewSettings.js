import { defaults } from './domain.js';

// Reception is written on paper. Retain the other saved choices while moving
// older typed-input settings to the current paper-only Electron view.
export function task5ViewConfiguration(saved) {
  const values = saved && typeof saved === 'object' && !Array.isArray(saved) ? saved : {};
  return { ...defaults, ...values, receptionMode: 'paper' };
}

export function task5CorrectionNotice(notice) {
  if (!notice || notice.startsWith('Продолжайте передачу.') || notice.startsWith('Корреспондент')) return '';
  return notice;
}
