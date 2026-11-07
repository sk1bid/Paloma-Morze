// Classroom profile v8. References: native Domain/Task5 and docs/task-5/14.
export const defaults = {
  ownCallsign: '',
  botCallsign: '',
  role: 'main',
  charset: 'letters',
  groups: 60,
  botSpeed: 50,
  keySpeed: 75,
  receptionMode: 'paper',
  category: 'first'
};
const alphabet = [...'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ'];
const aliases = Object.fromEntries([...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'].map((c, i) => [c, [...'АБЦДЕФГХИЙКЛМНОПЩРСТУЖВЬЫЗ'][i]]));
export const tokens = text => String(text).toUpperCase().split('').map(c => aliases[c] || c).join('').replaceAll('=', ' = ').trim().split(/\s+/).filter(Boolean);
export const canonical = text => tokens(text).join(' ');
export const answer = n => Math.abs(50 - Number(n));
const number = n => String(n).padStart(2, '0');
export function codes(tdr, cell) {
  return [...tdr.rowKeys[cell.row]].flatMap(r => [...tdr.columnKeys[cell.column]].map(c => `З${r}${c}`));
}
export function decode(tdr, code) {
  const c = [...canonical(code)];
  if (c.length !== 3 || c[0] !== 'З') return null;
  return tdr.cells.find(cell => tdr.rowKeys[cell.row].includes(c[1]) && tdr.columnKeys[cell.column].includes(c[2])) || null;
}
export const encode = (tdr, value) => codes(tdr, tdr.cells.find(c => c.number === number(value)))[0];
export function generate(config, seed, cells) {
  if (!/^\d+$/.test(String(seed)) || BigInt(seed) > (1n << 64n) - 1n) {
    throw new Error('Номер варианта: целое число от 0 до 18446744073709551615.');
  }
  const configuration = {
    ...defaults,
    ...config
  };
  if (!['main', 'subordinate'].includes(configuration.role) || !['letters', 'digits'].includes(configuration.charset) || !['typed', 'paper'].includes(configuration.receptionMode)) throw new Error('Проверьте роль станции, текст и способ приёма.');
  if (!Array.isArray(cells) || cells.length !== 100 || new Set(cells.map(c => c.number)).size !== 100) throw new Error('Нужна полная таблица ТДР 00–99.');
  if (![30, 60].includes(configuration.groups)) throw new Error('Выберите 30 или 60 групп');
  for (const key of ['botSpeed', 'keySpeed']) if (!Number.isInteger(configuration[key]) || configuration[key] < 30 || configuration[key] > 150 || configuration[key] % 5 !== 0) throw new Error('Скорость: 30–150 знаков/мин с шагом 5');
  // SplitMix64 matches the native stable generator, without JS float truncation.
  let state = BigInt(seed);
  const mask = (1n << 64n) - 1n;
  const next = () => {
    state = state + 0x9E3779B97F4A7C15n & mask;
    let z = state;
    z = (z ^ z >> 30n) * 0xBF58476D1CE4E5B9n & mask;
    z = (z ^ z >> 27n) * 0x94D049BB133111EBn & mask;
    return (z ^ z >> 31n) & mask;
  };
  const int = n => Number(next() % BigInt(n));
  const pick = a => a[int(a.length)];
  const digits = n => Array.from({
    length: n
  }, () => int(10)).join('');
  const shuffle = a => {
    const b = [...a];
    for (let i = b.length - 1; i > 0; i--) {
      const j = int(i + 1);
      [b[i], b[j]] = [b[j], b[i]];
    }
    return b;
  };
  const call = () => {
    const a = Array.from({
      length: 4
    }, () => pick(alphabet));
    a[int(4)] = digits(1);
    return a.join('');
  };
  const calls = ['ownCallsign', 'botCallsign'].map(key => canonical(configuration[key]));
  for (const c of calls) if (c && (!/^[АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЬЭЮЯ0-9]{3,8}$/.test(c) || (c.match(/[0-9]/g) || []).length !== 1)) throw new Error('Позывной: 3–8 знаков Морзе, ровно одна цифра');
  if (!calls[0]) do {
    calls[0] = call();
  } while (calls[0] === calls[1]);
  if (!calls[1]) do {
    calls[1] = call();
  } while (calls[0] === calls[1]);
  if (calls[0] === calls[1]) throw new Error('Позывные должны различаться в Морзе');
  const [ownCallsign, botCallsign] = calls;
  const axis = exclude => {
    const a = shuffle(alphabet.filter(c => !exclude || c !== 'З'));
    return Array.from({
      length: 10
    }, (_, i) => a.slice(i * 2, i * 2 + 2).join(''));
  };
  const tdr = {
    cells,
    rowKeys: axis(true),
    columnKeys: axis(false)
  };
  const radioData = {
    mainFrequency: String(4000 + int(2000)),
    reserveFrequency: String(6500 + int(1500)),
    networkNumber: digits(3),
    operatorName: 'Радист'
  };
  const dateTime = `${number(1 + int(28))} ${number(int(24))} ${number(int(60))}`;
  const main = configuration.role === 'main';
  const radiograms = [];
  const used = new Set();
  for (let i = 0; i < 2; i++) {
    const transmit = i % 2 === 0 === main;
    let nr;
    do {
      nr = digits(3);
    } while (used.has(nr));
    used.add(nr);
    const urgency = pick(['monolith', 'air', 'rocket', 'plane']);
    const categoryCodes = cells.filter(c => c.expressionId === urgency).flatMap(c => codes(tdr, c));
    if (!categoryCodes.length) throw new Error('Неполная таблица ТДР');
    const groups = Array.from({
      length: configuration.groups
    }, () => configuration.charset === 'digits' ? digits(5) : Array.from({
      length: 5
    }, () => pick(alphabet)).join(''));
    const rg = {
      id: `rg-${i}`,
      number: nr,
      groups,
      direction: transmit ? 'transmit' : 'receive',
      urgency: { monolith: 'Монолит', air: 'Воздух', rocket: 'Ракета', plane: 'Самолёт' }[urgency],
      urgencyCode: pick(categoryCodes),
      address: `${digits(6)} ${digits(3)}`,
      originCallsign: transmit ? ownCallsign : botCallsign,
      recipientCallsign: transmit ? botCallsign : ownCallsign,
      dateTime
    };
    rg.header = `${rg.originCallsign} ${nr} ${groups.length + 2} ${dateTime} ${nr}`;
    rg.wireText = `${rg.header} = ${rg.urgencyCode} ${rg.address} = ${groups.join(' ')} К`;
    rg.receipt = `Р ${nr} К`;
    radiograms.push(rg);
  }
  let network;
  do {
    network = call();
  } while (calls.includes(network));
  const signals = Array.from({
    length: 2
  }, (_, i) => {
    const tx = i === 0 === main;
    const group = digits(5);
    const part = `ЬЬЬ ЬЬЬ ${network} ${network} ${group} ${group} К`;
    return {
      id: `signal-${i}`,
      direction: tx ? 'transmit' : 'receive',
      group,
      firstPart: part,
      secondPart: part,
      wireText: `${part}\n${part}`,
      receipt: `${tx ? botCallsign : ownCallsign} Р ${group} К`
    };
  });
  const steps = [];
  const add = (id, title, tx, message, extra = {}) => {
    const step = {
      id,
      title,
      kind: tx ? 'transmit' : 'listen',
      direction: tx ? 'transmit' : 'receive',
      expectedMessages: message ? [message] : [],
      ...extra
    };
    if (!tx && message) step.botMessage = message;
    steps.push(step);
    return step;
  };
  add('duty', 'Принять дежурство', false, null, {
    kind: 'administrative'
  });
  add('setup', 'Подготовить рабочее место', false, null, {
    kind: 'administrative'
  });
  add('call', 'Вызов', main, main ? `${botCallsign} ДЕ ${ownCallsign} К` : `${ownCallsign} ДЕ ${botCallsign} К`);
  add('call-reply', 'Ответ на вызов', !main, main ? `${ownCallsign} ДЕ ${botCallsign} К` : `${botCallsign} ДЕ ${ownCallsign} К`);
  add('quality', 'Запрос силы сигналов', main, 'ЩСА? К');
  add('quality-reply', 'Оценка и встречный запрос', !main, `ЩСА ${Number(BigInt(seed) % 5n) + 1} К ЩСА? К`);
  add('quality-report', 'Ответ о силе сигналов', main, `ЩСА ${Number(BigInt(seed) % 5n) + 1} К`);
  const p = pick(cells.filter(c => c.expressionId === 'password'));
  if (!p) throw new Error('В ТДР нет пароля');
  const first = int(100),
    second = int(100);
  const password = codes(tdr, p)[0];
  const exchange = [['auth-peer', true, 'Запрос пароля', ['password', number(first)]], ['auth-request-echo', false, 'Проверка запроса', ['password', number(first), 'Ц?', 'К']], ['auth-request-confirm', true, 'Подтверждение запроса', ['Ц', 'К']], ['auth-request-wait', false, 'Запрос принят', null], ['auth-counter', false, 'Ответ и встречный запрос', ['password', number(answer(first)), number(second)]], ['auth-counter-echo', true, 'Проверка встречного запроса', ['password', number(answer(first)), number(second), 'Ц?', 'К']], ['auth-peer-reply', false, 'Подтверждение встречного запроса', ['Ц', 'К']], ['auth-counter-wait', true, 'Встречный запрос принят', null], ['auth-self', true, 'Ответ на встречный пароль', ['password', number(answer(second)), 'К']]];
  for (const [id, mainTx, title, originalRules] of exchange) {
    const tx = mainTx === main;
    if (!originalRules) {
      const minutes = 1;
      add(id, title, tx, `ОК АС ${minutes} К`);
      add(`${id}-pause`, 'Ожидание по АС', false, null, {
        kind: 'pause',
        requiredPauseSeconds: minutes * 60
      });
    } else {
      const rules = [...originalRules];
      if (rules.at(-1) !== 'К') rules.push('К');
      add(id, title, tx, rules.map(r => r === 'password' ? password : /^\d+$/.test(r) ? encode(tdr, r) : r).join(' '), {
        authenticationTokens: rules
      });
    }
  }
  for (const rg of radiograms) {
    const tx = rg.direction === 'transmit';
    add(`${rg.id}-offer`, 'Предложение радиограммы', tx, `ЩТЦ ${rg.urgencyCode} К`, {
      radiogramID: rg.id
    });
    add(`${rg.id}-ready`, 'Готовность к приёму', !tx, 'ЩРЖ К');
    add(rg.id, tx ? 'Передача радиограммы' : 'Приём радиограммы', tx, rg.wireText, {
      kind: tx ? 'transmit' : 'receive',
      radiogramID: rg.id,
      bodyGroups: rg.groups.length
    });
    add(`${rg.id}-receipt`, 'Квитанция радиограммы', !tx, rg.receipt, {
      radiogramID: rg.id
    });
  }
  for (const signal of signals) {
    const tx = signal.direction === 'transmit';
    add(`${signal.id}-first`, 'Первая часть сигнала', tx, signal.firstPart, {
      kind: tx ? 'signal' : 'listen'
    });
    add(`${signal.id}-pause`, 'Пауза между частями', false, null, {
      kind: 'pause',
      requiredPauseSeconds: 10
    });
    add(`${signal.id}-second`, 'Вторая часть сигнала', tx, tx ? signal.secondPart : signal.wireText, {
      kind: tx ? 'signal' : 'receive',
      botMessage: tx ? undefined : signal.secondPart
    });
    add(`${signal.id}-receipt`, 'Квитанция сигнала', !tx, signal.receipt);
    add(`${signal.id}-report`, 'Доклад по сигналу', false, null, {
      kind: 'administrative'
    });
  }
  add('close', 'Выключение по приказу', main, 'ЩБЕ К');
  add('close-reply', 'Подтверждение окончания работы', !main, 'ОК ЩБЕ К');
  add('journal', 'Сдать дежурство', false, null, {
    kind: 'administrative'
  });
  return {
    seed: String(seed),
    profileID: 'task5.photos.v8.final-k',
    configuration,
    ownCallsign,
    botCallsign,
    radioData,
    tdr,
    radiograms,
    signals,
    steps
  };
}
export function resolveStep(original, variant, attempts) {
  const s = structuredClone(original);
  const tdr = variant.tdr;
  if (['auth-request-wait', 'auth-counter-wait'].includes(s.id) && s.direction === 'receive') {
    s.expectedMessages = ['ОК АС 1 К'];
    s.botMessage = 'ОК АС 1 К';
  }
  const sent = id => {
    const a = attempts.findLast(a => a.stepID === id && a.correct && a.inputMethod !== 'service');
    return a ? tokens(a.input).slice(0, -1) : null;
  };
  if (!s.authenticationTokens) return s;
  const request = sent('auth-peer'),
    counter = sent('auth-counter');
  let wire = tokens(s.expectedMessages[0]);
  const requestCell = request?.length === 2 && decode(tdr, request[1]);
  const counterAnswer = counter?.length === 3 && decode(tdr, counter[1]);
  const counterChallenge = counter?.length === 3 && decode(tdr, counter[2]);
  if (s.id === 'auth-request-echo' && requestCell) {
    wire = [...request, 'Ц?', 'К'];
    s.authenticationTokens[1] = requestCell.number;
  }
  if (['auth-counter', 'auth-counter-echo'].includes(s.id) && requestCell) {
    const n = answer(requestCell.number);
    s.authenticationTokens[1] = number(n);
    wire[1] = encode(tdr, n);
  }
  if (s.id === 'auth-counter-echo' && counterAnswer && counterChallenge) {
    wire = [...counter, 'Ц?', 'К'];
    s.authenticationTokens[1] = counterAnswer.number;
    s.authenticationTokens[2] = counterChallenge.number;
  }
  if (s.id === 'auth-self' && counterChallenge) {
    const n = answer(counterChallenge.number);
    s.authenticationTokens[1] = number(n);
    wire[1] = encode(tdr, n);
  }
  s.expectedMessages = [wire.join(' ')];
  if (s.botMessage) s.botMessage = s.expectedMessages[0];
  return s;
}
export function waitMinutes(text) {
  const t = tokens(text);
  return t.length === 4 && t[0] === 'ОК' && t[1] === 'АС' && t[3] === 'К' && /^\d{1,2}$/.test(t[2]) && +t[2] >= 1 && +t[2] <= 99 ? +t[2] : null;
}

export function codeMeanings(text, step, variant) {
  return tokens(text).flatMap((code, index) => {
    const cell = decode(variant.tdr, code);
    if (!cell) return [];
    const rule = step.authenticationTokens?.[index];
    const meaning = rule && /^\d+$/.test(rule) ? cell.number : cell.expression || `Число ${cell.number}`;
    return [{ code, meaning }];
  });
}

export function authenticationWait(step, previousStep, random = Math.random) {
  if (!step.id.endsWith('-wait-pause')) return null;
  return previousStep?.direction === 'receive' ? 55000 + random() * 10000 : 0;
}
export function validateStrict(text, step, variant) {
  const input = tokens(text),
    tdr = variant.tdr;
  const wrong = (message, errors = 1) => ({
    correct: false,
    message,
    errors
  });
  if (input.at(-1) !== 'К') return wrong('Завершите сообщение знаком К.');
  if (['auth-request-wait', 'auth-counter-wait'].includes(step.id)) return waitMinutes(text) ? {
    correct: true,
    errors: 0
  } : wrong('Передайте ОК АС <1–99 минут> К.');
  if (['quality-report', 'quality-reply'].includes(step.id) && step.direction === 'transmit') {
    const expression = step.id === 'quality-report' ? /^ЩСА [1-5] К$/ : /^ЩСА [1-5] К ЩСА(?:\?| \?) К$/;
    return expression.test(input.join(' ')) ? {
      correct: true,
      errors: 0
    } : wrong('Оценка силы: целое число 1–5. Проверьте форму и конечную К.');
  }
  if (step.authenticationTokens) {
    if (input.length !== step.authenticationTokens.length) return wrong('Проверьте число групп паролирования.');
    for (let i = 0; i < input.length; i++) {
      const rule = step.authenticationTokens[i],
        cell = decode(tdr, input[i]);
      const free = step.direction === 'transmit' && (step.id === 'auth-peer' && i === 1 || step.id === 'auth-counter' && i === 2);
      if (rule === 'password' ? cell?.expressionId !== 'password' : /^\d+$/.test(rule) ? !cell || !free && cell.number !== rule : input[i] !== rule) return wrong(`Группа ${i + 1}: проверьте кодовые группы. Ответ на пароль — |50 − принятое число|.`);
    }
    return {
      correct: true,
      errors: 0
    };
  }
  const rg = variant.radiograms.find(r => r.id === step.radiogramID);
  if (rg && step.id.endsWith('-offer')) return input.length === 3 && input[0] === 'ЩТЦ' && decode(tdr, input[1])?.expressionId === decode(tdr, rg.urgencyCode)?.expressionId ? {
    correct: true,
    errors: 0
  } : wrong('Проверьте ЩТЦ, код категории и К.');
  let expected = tokens(step.expectedMessages[0] || '');
  if (rg && step.bodyGroups) {
    const separators = input.flatMap((c, i) => c === '=' ? [i] : []);
    if (separators.length !== 2) return wrong('Нужны два раздела =.');
    const [a, b] = separators;
    if (input.slice(0, a).join(' ') !== rg.header) return wrong('Проверьте позывной, номер, число групп (+2 адресные), дату и время.');
    if (b - a !== 4 || decode(tdr, input[a + 1])?.expressionId !== decode(tdr, rg.urgencyCode)?.expressionId || input.slice(a + 2, b).join(' ') !== rg.address) return wrong('Проверьте категорию и адресные группы.');
    const groups = input.slice(b + 1, -1);
    if (groups.length !== rg.groups.length) return wrong('Число групп не совпадает с заголовком.', Math.abs(groups.length - rg.groups.length));
    if (groups.some(g => g.length !== 5)) return wrong('В каждой группе должно быть пять знаков.');
    const errors = groups.reduce((sum, group, i) => sum + [...group].filter((sign, j) => sign !== rg.groups[i][j]).length, 0);
    if (errors) {
      const first = groups.findIndex((group, i) => group !== rg.groups[i]);
      return wrong(`Ошибка в группе текста ${first + 1}. Несовпадений знаков: ${errors}.`, errors);
    }
    return { correct: true, errors: 0 };
  }
  const errors = Array.from({
    length: Math.max(input.length, expected.length)
  }, (_, i) => input[i] === expected[i] ? 0 : 1).reduce((a, b) => a + b, 0);
  const index = input.findIndex((g, i) => g !== expected[i]);
  return errors ? wrong(`Ошибка в группе ${index >= 0 ? index + 1 : input.length + 1}. Проверьте сообщение и повторите.`, errors) : {
    correct: true,
    errors: 0
  };
}
export function normalizeTransmission(text, step, variant) {
  const original = canonical(text);
  if (validateStrict(original, step, variant).correct) return original;
  const compact = tokens(original).join('');
  const candidates = [original.replace(/\s*\?\s*/g, '? ')];
  if (original.endsWith('К')) candidates.push(`${original.slice(0, -1)} К`);
  if (!step.bodyGroups) {
    candidates.push(...step.expectedMessages.filter(e => tokens(e).join('') === compact));
    candidates.push(compact.replace(/^ОКАС(\d{1,2})К$/, 'ОК АС $1 К'), compact.replace(/^ЩСА([1-5])К(ЩСА\?К)?$/, 'ЩСА $1 К $2').replace('?К', '? К'));
    if (step.authenticationTokens) {
      let offset = 0;
      const groups = step.authenticationTokens.map(r => {
        const n = r === 'password' || /^\d+$/.test(r) ? 3 : r.length;
        const group = compact.slice(offset, offset + n);
        offset += n;
        return group;
      });
      if (offset === compact.length) candidates.push(groups.join(' '));
    }
  }
  return canonical(candidates.find(c => validateStrict(c, step, variant).correct) || original);
}
export function validate(text, step, variant) {
  return validateStrict(normalizeTransmission(text, step, variant), step, variant);
}
export function repeatReply(text, rg, lastMessage) {
  const words = tokens(text);
  if (words.pop() !== 'К' || words.shift() !== 'РПТ') return null;
  if (!words.length || words.join(' ') === 'АЛ') return rg?.wireText || lastMessage;
  if (!rg) return null;
  if (words.join(' ') === 'ПБЛ') return `${rg.header} = ${rg.urgencyCode} ${rg.address} = К`;
  if (words.join(' ') === 'НР') return `НР ${rg.number} К`;
  const index = locator => {
    const matches = rg.groups.flatMap((g, i) => g === locator ? [i] : []);
    if (matches.length) return matches.length === 1 ? matches[0] : -1;
    return /^\d{1,3}$/.test(locator) && +locator >= 1 && +locator <= rg.groups.length ? +locator - 1 : -1;
  };
  const a = index(words[1]),
    b = index(words[2]);
  let groups;
  if (words.length === 2 && a >= 0) {
    if (words[0] === 'ГР') groups = [rg.groups[a]];
    if (words[0] === 'АА') groups = rg.groups.slice(a + 1);
    if (words[0] === 'АБ') groups = rg.groups.slice(0, a);
  }
  if (words.length === 3 && words[0] === 'БН' && a >= 0 && b > a + 1) groups = rg.groups.slice(a + 1, b);
  return groups?.length ? `${groups.join(' ')} К` : null;
}
export function botDelay(step, repeating = false, random = Math.random) {
  if (!repeating && /^signal-\d-second$/.test(step.id)) return 0;
  return !repeating && (step.id.startsWith('auth-') || step.id.endsWith('-receipt')) ? 2500 + random() * 2500 : 1000 + random() * 2000;
}
export function timeBand(category, seconds) {
  const bands = {
    first: [50, 55, 60],
    second: [40, 45, 50],
    thirdToFifth: [35, 40, 45],
    officers: [35, 40, 45]
  };
  const i = (bands[category] || bands.first).findIndex(m => seconds <= m * 60);
  return ['Отлично по времени', 'Хорошо по времени', 'Удовлетворительно по времени'][i] || 'Время превышено';
}
