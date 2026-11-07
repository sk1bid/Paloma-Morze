export function radiogramRows(groups) {
  const rows = [];
  for (let index = 0; index < groups.length; index += 5) rows.push(groups.slice(index, index + 5));
  return rows;
}

export function radiogramHeaderFields(gram) {
  const [day, hour, minute] = gram.dateTime.split(' ');
  return [
    { label: 'Из', value: gram.originCallsign },
    { label: '№', value: gram.number },
    { label: 'Групп', value: String(gram.groups.length + 2) },
    { label: 'День', value: day },
    { label: 'Время', value: `${hour} ${minute}` },
    { label: 'Повтор №', value: `${gram.number} =` }
  ];
}

export function requestedRadiogramGroup(recovery) {
  const match = /^РПТ ГР ([1-9]\d*) К$/.exec(recovery?.request || '');
  return match ? Number(match[1]) : null;
}

export function currentRadiogramGroup(input, count) {
  const first = input.indexOf('='), second = input.indexOf('=', first + 1);
  if (first < 0 || second < 0) return null;
  const body = input.slice(second + 1);
  const groups = body.trim().split(/\s+/).filter(Boolean);
  if (!groups.length) return 1;
  if (groups.at(-1) === 'К' && groups.length > count) return count + 1;
  return Math.min(count, groups.length + (/\s$/.test(body) ? 1 : 0));
}

// Entries here have already passed the model's valid ОК АС acknowledgment gate.
// Presentation narrows that existing history; it never decodes incoming data.
export function visibleDecodedCodes(step, entries) {
  if (!step) return [];
  if (step.id.startsWith('auth-')) return entries.filter(entry => entry.stepID.startsWith('auth-')).slice(-1);
  const offer = /^(rg-\d+)-(?:offer|ready)$/.exec(step.id);
  return offer ? entries.filter(entry => entry.stepID === `${offer[1]}-offer`).slice(-1) : [];
}
