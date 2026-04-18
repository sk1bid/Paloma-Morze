import { MORSE_RU, MORSE_EN, MNEMONICS_RU, MNEMONICS_EN } from '../constants';
import { Q_MAP } from './q_codes';

/**
 * Unified provider for Morse patterns and mnemonics.
 * Handles Paloma-specific defaults (like 0 = dash) and user overrides.
 */

export const getMorsePattern = (char, overrides = {}) => {
  // 1. User Overrides take highest priority
  if (overrides[char]?.pattern) return overrides[char].pattern;
  
  // 2. Paloma-specific Defaults (Single Source of Truth)
  if (char === '0') return '-';

  // 3. Multi-character handling (e.g., Q-codes)
  if (char.length > 1) {
    return char.split('').map(c => getMorsePattern(c, overrides)).filter(p => p).join(' ');
  }

  // 4. Standard Dictionaries (RU then EN)
  const dicts = [MORSE_RU, MORSE_EN];
  for (const dict of dicts) {
    const pattern = Object.keys(dict).find(k => dict[k] === char);
    if (pattern) return pattern;
  }
  
  return '';
};

export const getMnemonic = (char, lang = 'RU', overrides = {}) => {
  // 1. User Overrides
  if (overrides[char]?.mnemonic) return overrides[char].mnemonic;
  
  // 2. Q-code logic
  if (Q_MAP[char]) return Q_MAP[char];

  // 3. Paloma-specific Defaults
  if (char === '0') return lang === 'RU' ? 'НОЛЬ' : 'ZERO';

  const pattern = getMorsePattern(char, overrides);
  if (!pattern) return '';

  const mnemDict = lang === 'RU' ? MNEMONICS_RU : MNEMONICS_EN;
  return mnemDict[pattern] || MNEMONICS_RU[pattern] || MNEMONICS_EN[pattern] || '';
};

export const getQCodeMeaning = (text) => {
  if (!text) return '';
  // Check for 3-letter Q-code at the end of the string
  const upper = text.toUpperCase().replace(/ /g, '');
  for (let len = 3; len <= 4; len++) {
    const candidate = upper.slice(-len);
    if (Q_MAP[candidate]) return Q_MAP[candidate];
  }
  return '';
};

export const decodeMorse = (pattern, lang = 'RU', overrides = {}) => {
  // Build lookup map from base dictionary + overrides
  const lookup = {};
  
  // 1. Base dictionary (Pattern -> Char)
  const baseDict = lang === 'RU' ? MORSE_RU : MORSE_EN;
  Object.assign(lookup, baseDict);
  
  // 2. Overrides (Pattern -> Char)
  Object.keys(overrides).forEach(char => {
    if (overrides[char].pattern) {
      lookup[overrides[char].pattern] = char;
    }
  });

  // 3. Collision Resolution (Single Source of Truth)
  // Even if '0' is mapped to '-', standard 'T'/'Т' takes priority in Transmission to avoid confusion.
  if (pattern === '-') return lang === 'RU' ? 'Т' : 'T';

  return lookup[pattern] || '?';
};
