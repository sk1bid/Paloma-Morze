import { canonical, decode, repeatReply, tokens } from './domain.js';

function parts(text) {
  const words = tokens(text);
  const separators = words.flatMap((word, i) => word === '=' ? [i] : []);
  if (words.at(-1) !== 'К' || separators.length !== 2) return null;
  const [first, second] = separators;
  return {
    header: words.slice(0, first),
    address: words.slice(first + 1, second),
    groups: words.slice(second + 1, -1)
  };
}

function validHeader(parsed, gram, tdr) {
  const category = decode(tdr, parsed.address[0] || '');
  return parsed.header.join(' ') === gram.header
    && parsed.address.length === 3
    && category?.expressionId != null
    && category.expressionId === decode(tdr, gram.urgencyCode)?.expressionId
    && parsed.address.slice(1).join(' ') === gram.address;
}

export function radiogramRecovery(text, gram, tdr) {
  const parsed = parts(text);
  let request = 'РПТ АЛ К';
  if (parsed && parsed.groups.length === gram.groups.length) {
    if (!validHeader(parsed, gram, tdr)) request = 'РПТ ПБЛ К';
    else {
      const wrong = parsed.groups.findIndex((group, i) => group !== gram.groups[i]);
      if (wrong < 0) return null;
      request = `РПТ ГР ${wrong + 1} К`;
    }
  }
  return { radiogramID: gram.id, transmission: canonical(text), request };
}

export function recoveryTarget(recovery, original, gram) {
  return {
    ...original,
    bodyGroups: recovery.request === 'РПТ АЛ К' ? original.bodyGroups : 0,
    expectedMessages: [repeatReply(recovery.request, gram)],
    kind: 'transmit'
  };
}

export function mergeRadiogramCorrection(recovery, response, gram, tdr) {
  const words = tokens(response);
  if (words.at(-1) !== 'К') return null;
  if (recovery.request === 'РПТ АЛ К') return canonical(response);
  const current = parts(recovery.transmission);
  if (!current) return null;
  if (recovery.request === 'РПТ ПБЛ К') {
    const header = parts(response);
    if (!header || header.groups.length || !validHeader(header, gram, tdr)) return null;
    return `${header.header.join(' ')} = ${header.address.join(' ')} = ${current.groups.join(' ')} К`;
  }
  const index = Number(tokens(recovery.request)[2]) - 1;
  if (words.length !== 2 || words[0] !== gram.groups[index]) return null;
  current.groups[index] = words[0];
  return `${current.header.join(' ')} = ${current.address.join(' ')} = ${current.groups.join(' ')} К`;
}

export function cancelLastRadiogramGroup(text) {
  const trimmed = text.trimEnd();
  if (trimmed.endsWith('=')) return text;
  let boundary = -1;
  for (let i = trimmed.length - 1; i >= 0; i--) {
    if (/\s/.test(trimmed[i]) || trimmed[i] === '=') { boundary = i; break; }
  }
  if (boundary < 0) return '';
  return trimmed[boundary] === '=' ? `${trimmed.slice(0, boundary + 1)} ` : text.slice(0, boundary + 1);
}
