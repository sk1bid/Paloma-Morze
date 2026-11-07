import { readFileSync } from 'node:fs';
import { jest } from '@jest/globals';
import { generate, codes, decode, encode, tokens, answer, codeMeanings, validate, resolveStep, normalizeTransmission, waitMinutes, authenticationWait, repeatReply, botDelay, timeBand } from '../src/task5/domain.js';
import { Task5Session } from '../src/task5/session.js';
import { task5ViewConfiguration, task5CorrectionNotice } from '../src/task5/viewSettings.js';
import { cancelLastRadiogramGroup, radiogramRecovery } from '../src/task5/radiogramRecovery.js';
import { MORSE_RU } from '../src/constants.js';

const cells = JSON.parse(readFileSync(new URL('../src/task5/tdr.json', import.meta.url))).cells;
const make = (config = {}, seed = '42') => generate({ groups: 30, ...config }, seed, cells);
const step = (v, id) => v.steps.find(s => s.id === id);

describe('Task5 simplified Electron view', () => {
  test('saved typed mode migrates to paper reception without resetting other choices', () => {
    const saved = { receptionMode: 'typed', role: 'subordinate', groups: 30, botSpeed: 85, ownCallsign: 'АБ1В' };
    expect(task5ViewConfiguration(saved)).toMatchObject({ ...saved, receptionMode: 'paper' });
    expect(saved.receptionMode).toBe('typed');
    expect(task5ViewConfiguration(null).receptionMode).toBe('paper');
    expect(task5ViewConfiguration({ ...saved, receptionMode: 'unknown' }).receptionMode).toBe('paper');
  });
  test('routine transmission guidance stays hidden while correction notices remain visible', () => {
    expect(task5CorrectionNotice('Продолжайте передачу. Сообщение завершается К; перебой — восемь точек.')).toBe('');
    expect(task5CorrectionNotice('Корреспондент готовит ответ')).toBe('');
    expect(task5CorrectionNotice('Перебой принят. Передайте сообщение заново.')).toBe('Перебой принят. Передайте сообщение заново.');
  });
});
function harness(config = {}) {
  let now = 0;
  const audio = { ready: true, setCharWpm: jest.fn(), keyDown: jest.fn(), keyUp: jest.fn(), stopAll: jest.fn(), playSequence: jest.fn(async () => ({ cancelled: false })) };
  const persist = jest.fn();
  const session = new Task5Session({ cells, audio, pattern: () => '.', decodePattern: p => MORSE_RU[p], now: () => now, random: () => 0, persist });
  session.start({ groups: 30, receptionMode: 'typed', ...config }, '42');
  const advanceClock = async ms => { now += ms; session.tick(); await Promise.resolve(); await Promise.resolve(); };
  return { session, audio, persist, advanceClock, now: () => now };
}

async function keyText(h, text) {
  const unit = 6000 / h.session.state.variant.configuration.keySpeed;
  for (const char of text) {
    if (char === ' ') { await h.advanceClock(unit * 8); continue; }
    const pattern = Object.keys(MORSE_RU).find(pattern => MORSE_RU[pattern] === char);
    for (const pulse of pattern) {
      h.session.down('keyboard');
      await h.advanceClock(unit * (pulse === '.' ? 1 : 3));
      h.session.up('keyboard');
      await h.advanceClock(unit);
    }
    await h.advanceClock(unit * 3);
  }
  await h.advanceClock(unit * 8);
}

function brokenGroup(group) { return (group[0] === 'А' ? 'Б' : 'А') + group.slice(1); }
function gramWire(gram, groups, header = gram.header, address = `${gram.urgencyCode} ${gram.address}`) {
  return `${header} = ${address} = ${groups.join(' ')} К`;
}
function enterOutgoing(h) {
  const gram = h.session.state.variant.radiograms.find(gram => gram.direction === 'transmit');
  h.session.cancel();
  h.session.state.index = h.session.state.variant.steps.findIndex(step => step.id === gram.id);
  h.session.enter();
  return gram;
}

describe('Task5 radiogram correction', () => {
  test.each(['main', 'subordinate'])('requests only erroneous groups, keeps good parts and counts only the merged radiogram (%s)', async role => {
    const h = harness({ role }), gram = enterOutgoing(h), groups = [...gram.groups];
    groups[2] = brokenGroup(groups[2]); groups[7] = brokenGroup(groups[7]);
    const failed = gramWire(gram, groups); h.session.submit(failed);
    expect(h.session.state.radiogramRecovery.request).toBe('РПТ ГР 3 К');
    expect(h.session.target.expectedMessages).toEqual([`${gram.groups[2]} К`]);
    expect(h.session.summary.transmittedGroups).toBe(0);
    await h.advanceClock(5000);
    h.session.submit(`${brokenGroup(gram.groups[2])} К`);
    expect(h.session.state.radiogramRecovery.transmission).toBe(failed);
    expect(h.session.state.radiogramRecovery.request).toBe('РПТ ГР 3 К');
    await h.advanceClock(5000);
    h.session.submit(`${gram.groups[2]} К`);
    const corrected = [...groups]; corrected[2] = gram.groups[2];
    expect(h.session.state.radiogramRecovery.transmission).toBe(gramWire(gram, corrected));
    expect(h.session.state.radiogramRecovery.request).toBe('РПТ ГР 8 К');
    expect(h.session.summary.transmittedGroups).toBe(0);
    await h.advanceClock(5000); await keyText(h, `${gram.groups[7]} К`);
    expect(h.session.state.radiogramRecovery).toBeNull();
    expect(h.session.step.id).toBe(`${gram.id}-receipt`);
    expect(h.session.summary.transmittedGroups).toBe(30);
    expect(h.session.state.attempts.filter(a => a.stepID === gram.id && a.correct && a.inputMethod !== 'correction')).toEqual([expect.objectContaining({ input: gram.wireText, inputMethod: 'key' })]);
    expect(h.session.state.attempts.find(a => a.input === failed).correct).toBe(false);
  });
  test('repairs header/address before the remaining body error using the existing PBL fragment', async () => {
    const h = harness(), gram = enterOutgoing(h), groups = [...gram.groups]; groups[3] = brokenGroup(groups[3]);
    h.session.submit(gramWire(gram, groups, gram.header.replace(gram.number, '9999')));
    expect(h.session.state.radiogramRecovery.request).toBe('РПТ ПБЛ К');
    await h.advanceClock(5000);
    h.session.submit(`НЕВЕРНО = ${gram.urgencyCode} ${gram.address} = К`);
    expect(h.session.state.radiogramRecovery.request).toBe('РПТ ПБЛ К');
    await h.advanceClock(5000);
    h.session.submit(repeatReply('РПТ ПБЛ К', gram));
    expect(h.session.state.radiogramRecovery.request).toBe('РПТ ГР 4 К');
    expect(h.session.state.radiogramRecovery.transmission).toBe(gramWire(gram, groups));
    expect(h.session.summary.transmittedGroups).toBe(0);
    await h.advanceClock(5000); h.session.submit(`${gram.groups[3]} К`);
    expect(h.session.summary.transmittedGroups).toBe(30);
  });
  test('ambiguous missing/extra groups or separators request AL rather than guessing alignment', async () => {
    for (const mutate of [gram => gramWire(gram, gram.groups.slice(1)), gram => gramWire(gram, [...gram.groups, 'ААААА']), gram => gram.wireText.replace(' = ', ' '), gram => gramWire(gram, gram.groups.slice(1), 'НЕВЕРНЫЙ ЗАГОЛОВОК')]) {
      const h = harness(), gram = enterOutgoing(h); h.session.submit(mutate(gram));
      expect(h.session.state.radiogramRecovery.request).toBe('РПТ АЛ К');
      expect(h.session.target.bodyGroups).toBe(gram.groups.length);
      await h.advanceClock(5000); h.session.submit(mutate(gram)); expect(h.session.summary.transmittedGroups).toBe(0);
      await h.advanceClock(5000); h.session.submit(gram.wireText); expect(h.session.summary.transmittedGroups).toBe(30);
    }
  });
  test.each(['ABCDE', 'ABCDE ', 'ABC'])('eight keyed dots cancel only the current/last lexical group (%s)', async suffix => {
    const h = harness(), gram = enterOutgoing(h);
    const prefix = `${gram.header} = ${gram.urgencyCode} ${gram.address} = ${gram.groups[0]} `;
    h.session.setInput(prefix + suffix);
    const unit = 6000 / h.session.state.variant.configuration.keySpeed;
    for (let i = 0; i < 8; i++) { h.session.down(); await h.advanceClock(unit); h.session.up(); await h.advanceClock(unit); }
    await h.advanceClock(unit * 3);
    expect(h.session.state.input).toBe(prefix); expect(h.session.state.buffer).toBe(''); expect(h.session.state.attempts).toHaveLength(0);
    expect(h.session.state.notice).toContain('последнюю группу');
  });
  test('group rollback respects section boundaries and never removes an equals separator', () => {
    expect(cancelLastRadiogramGroup('HEADER = ADDRESS = ')).toBe('HEADER = ADDRESS = ');
    expect(cancelLastRadiogramGroup('HEADER = ADDRESS =ABCDE')).toBe('HEADER = ADDRESS = ');
    expect(cancelLastRadiogramGroup('HEADER = ADDRESS = ABCDE  ФЫВ')).toBe('HEADER = ADDRESS = ABCDE  ');
  });
  test('pending request survives a fresh-session restore and clears rejected input on the first key', async () => {
    const h = harness(), gram = enterOutgoing(h), groups = [...gram.groups]; groups[0] = brokenGroup(groups[0]); h.session.submit(gramWire(gram, groups)); h.session.pause();
    const archive = structuredClone(h.session.archive()); h.session.stop();
    const fresh = new Task5Session({ cells, audio: h.audio, pattern: () => '.', decodePattern: p => MORSE_RU[p], now: h.now, random: () => 0 });
    fresh.restore(archive); fresh.resume(); await h.advanceClock(5000); fresh.tick(); await Promise.resolve(); await Promise.resolve();
    expect(fresh.target.expectedMessages).toEqual([`${gram.groups[0]} К`]);
    fresh.down(); expect(fresh.state.input).toBe(''); fresh.up();
    fresh.state.input = gram.groups[0].slice(0, 2); fresh.state.buffer = ''; fresh.pause();
    const partial = structuredClone(fresh.archive()); fresh.stop();
    const again = new Task5Session({ cells, audio: h.audio, pattern: () => '.', decodePattern: p => MORSE_RU[p], now: h.now, random: () => 0 });
    again.restore(partial); again.resume(); again.down();
    expect(again.state.input).toBe(gram.groups[0].slice(0, 2)); again.release();
  });
  test('corrupt pending requests cannot target another gram or falsely credit a valid draft', () => {
    const h = harness(), gram = enterOutgoing(h), groups = [...gram.groups]; groups[0] = brokenGroup(groups[0]); h.session.submit(gramWire(gram, groups)); h.session.pause();
    const archive = structuredClone(h.session.archive()); h.session.stop(); archive.radiogramRecovery.request = 'РПТ ГР 9 К';
    expect(() => h.session.restore(archive)).toThrow('повреждённый');
    archive.radiogramRecovery = { radiogramID: gram.id, transmission: gram.wireText, request: 'РПТ ГР 1 К' };
    expect(() => h.session.restore(archive)).toThrow('повреждённый');
    expect(radiogramRecovery(gram.wireText, gram, h.session.state.variant.tdr)).toBeNull();
  });
  test('default paper reception records the receipt without assigning received-text accuracy', async () => {
    const h = harness(task5ViewConfiguration({ receptionMode: 'typed' }));
    expect(make().configuration.receptionMode).toBe('paper');
    h.session.cancel(); h.session.state.index = h.session.state.variant.steps.findIndex(step => step.kind === 'receive' && step.bodyGroups); h.session.enter(); await h.advanceClock(5000);
    const receipt = h.session.receipt; h.session.submit(receipt.expectedMessages[0]);
    expect(h.session.state.attempts.find(a => a.stepID === receipt.id && a.inputMethod !== 'bot').correct).toBe(true);
    expect(h.session.state.attempts.some(a => a.inputMethod === 'reception')).toBe(false);
    expect(h.session.summary.receivedGroups).toBe(0);
    expect(h.session.state.events.some(e => e.kind === 'paperUnverified')).toBe(true);
  });
});

describe('Task5 classroom v8 domain', () => {
  test('Electron reference resources are identical to the native resources', () => {
    for (const [electron, native] of [['tdr.json', 'task5-tdr.v1.json'], ['serviceCodes.json', 'task5-service-radiocodes.v1.json']]) {
      const a = JSON.parse(readFileSync(new URL(`../src/task5/${electron}`, import.meta.url)));
      const b = JSON.parse(readFileSync(new URL(`../../apps/macos/PalomaMorse/PalomaMorse/Resources/${native}`, import.meta.url)));
      expect(a).toEqual(b);
    }
  });
  test('seeds are decimal UInt64 and speed uses the native engine step', () => {
    for (const seed of ['-1', '0x10', '18446744073709551616', 'abc', '1.5']) expect(() => make({}, seed)).toThrow('Номер варианта');
    expect(make({}, '0').seed).toBe('0');
    expect(make({}, '18446744073709551615').seed).toBe('18446744073709551615');
    expect(() => make({ botSpeed: 71 })).toThrow('шагом 5');
  });
  test('stable variants and two roles share the same generated TDR/radio material', () => {
    const a = make(), b = make(), subordinate = make({ role: 'subordinate' });
    expect(a).toEqual(b);
    expect(a.tdr).toEqual(subordinate.tdr);
    expect(a.radiograms.map(r => r.groups)).toEqual(subordinate.radiograms.map(r => r.groups));
    expect(a.radiograms.map(r => r.direction)).toEqual(['transmit', 'receive']);
    expect(subordinate.radiograms.map(r => r.direction)).toEqual(['receive', 'transmit']);
    expect(step(a, 'auth-peer').direction).toBe('transmit');
    expect(step(subordinate, 'auth-peer').direction).toBe('receive');
    expect(make({}, '43')).not.toEqual(a);
  });
  test.each([30, 60])('%i body groups, exactly two address groups and a final K', groups => {
    const v = make({ groups });
    expect(v.radiograms).toHaveLength(2);
    for (const rg of v.radiograms) {
      expect(rg.groups).toHaveLength(groups);
      expect(tokens(rg.header)[2]).toBe(String(groups + 2));
      expect(validate(rg.wireText, step(v, rg.id), v).correct).toBe(true);
    }
    for (const s of v.steps) {
      for (const text of [...s.expectedMessages, ...(s.botMessage ? [s.botMessage] : [])]) expect(tokens(text).at(-1)).toBe('К');
    }
    expect(v.signals.every(s => s.firstPart.endsWith(' К') && s.secondPart.endsWith(' К'))).toBe(true);
    expect(step(v, 'signal-0-pause').requiredPauseSeconds).toBe(10);
  });
  test('all 400 codes decode; axes never ambiguously reuse a letter', () => {
    const { tdr } = make();
    expect(tdr.rowKeys.join('')).not.toContain('З');
    expect(new Set(tdr.rowKeys.join('')).size).toBe(20);
    for (const cell of cells) for (const code of codes(tdr, cell)) expect(decode(tdr, code)).toEqual(cell);
    expect(decode(tdr, 'З??')).toBeNull();
  });
  test('Morse aliases, valid callsign digits and unsupported signs', () => {
    expect(tokens('ABCVWXYZ')).toEqual(['АБЦЖВЬЫЗ']);
    expect(make({ ownCallsign: 'AB1C', botCallsign: 'DE2F' }).ownCallsign).toBe('АБ1Ц');
    expect(() => make({ ownCallsign: 'АБВГ' })).toThrow();
    expect(() => make({ ownCallsign: 'АБ12' })).toThrow();
    expect(() => make({ ownCallsign: 'АЁ1Г' })).toThrow();
    expect(() => make({ ownCallsign: 'AB1C', botCallsign: 'АБ1Ц' })).toThrow();
  });
  test.each(['main', 'subordinate'])('arbitrary challenges resolve echoes and abs50 answers for %s', role => {
    const v = make({ role }); const attempts = [];
    for (const original of v.steps.filter(s => s.id.startsWith('auth-') && s.kind !== 'pause')) {
      const s = resolveStep(original, v, attempts); let text = s.expectedMessages[0];
      if (s.direction === 'transmit' && ['auth-peer', 'auth-counter'].includes(s.id)) {
        const groups = tokens(text); groups[s.id === 'auth-peer' ? 1 : 2] = encode(v.tdr, 99); text = groups.join(' ');
      }
      expect(validate(text, s, v).correct).toBe(true);
      attempts.push({ stepID: s.id, input: text, correct: true });
    }
    const last = resolveStep(step(v, 'auth-self'), v, attempts);
    const counter = attempts.find(a => a.stepID === 'auth-counter');
    expect(decode(v.tdr, tokens(last.expectedMessages[0])[1]).number).toBe(String(answer(decode(v.tdr, tokens(counter.input)[2]).number)).padStart(2, '0'));
    expect(answer(0)).toBe(50); expect(answer(50)).toBe(0); expect(answer(99)).toBe(49);
  });
  test('auth wrong response rejected while equivalent password and axis codes accepted', () => {
    const v = make(), s = step(v, 'auth-counter-echo'), groups = tokens(s.expectedMessages[0]);
    groups[1] = encode(v.tdr, (Number(s.authenticationTokens[1]) + 1) % 100);
    expect(validate(groups.join(' '), s, v).correct).toBe(false);
    groups[1] = codes(v.tdr, cells.find(c => c.number === s.authenticationTokens[1]))[3];
    groups[0] = codes(v.tdr, cells.find(c => c.expressionId === 'password'))[3];
    expect(validate(groups.join(' '), s, v).correct).toBe(true);
  });
  test('numeric authentication codes show the number even when their cell has a command expression', () => {
    const v = make(), s = step(v, 'auth-peer'), cell = cells.find(c => c.expressionId === 'monolith');
    const groups = tokens(s.expectedMessages[0]); groups[1] = encode(v.tdr, cell.number);
    const meanings = codeMeanings(groups.join(' '), s, v);
    expect(meanings[1].meaning).toBe(cell.number); expect(meanings[1].meaning).not.toBe(cell.expression);
    expect(codeMeanings(`ЩТЦ ${groups[1]} К`, step(v, 'rg-0-offer'), v)[0].meaning).toBe(cell.expression);
  });
  test('spacing repair never adds missing K or hides radiogram boundaries', () => {
    const v = make(), s = step(v, 'call');
    expect(normalizeTransmission(s.expectedMessages[0].replaceAll(' ', ''), s, v)).toBe(s.expectedMessages[0]);
    expect(validate(s.expectedMessages[0].slice(0, -2), s, v).correct).toBe(false);
    const rg = v.radiograms[0]; expect(validate(rg.wireText.replace(`${rg.groups[0]} ${rg.groups[1]}`, rg.groups[0] + rg.groups[1]), step(v, rg.id), v).correct).toBe(false);
  });
  test('quality accepts operator rating 1–5 and internal K is preserved', () => {
    const v = make({ role: 'subordinate' }), s = step(v, 'quality-reply');
    expect(validate('ЩСА 1 К ЩСА? К', s, v).correct).toBe(true);
    expect(validate('ЩСА 6 К ЩСА? К', s, v).correct).toBe(false);
    expect(validate('ЩСА 1 К', s, v).correct).toBe(false);
    expect(validate('ЩСА 1 К ЩСА К', s, v).correct).toBe(false);
    expect(validate('ЩСА1КЩСА?К', s, v).correct).toBe(true);
  });
  test('AS accepts 1–99 and separates hidden bot wait from immediate operator acknowledgment', () => {
    const v = make();
    expect(waitMinutes('ОК АС 99 К')).toBe(99);
    for (const text of ['ОК АС 0 К', 'ОК АС 100 К', 'ОК АС 1', 'ОК АС -1 К']) expect(waitMinutes(text)).toBeNull();
    expect(authenticationWait(step(v, 'auth-counter-wait-pause'), step(v, 'auth-counter-wait'))).toBe(0);
    expect(authenticationWait(step(v, 'auth-request-wait-pause'), step(v, 'auth-request-wait'), () => 0)).toBe(55000);
    expect(authenticationWait(step(v, 'auth-request-wait-pause'), step(v, 'auth-request-wait'), () => 1)).toBe(65000);
    expect(resolveStep({ ...step(v, 'auth-request-wait'), botMessage: 'ОК АС 2 К' }, v, []).botMessage).toBe('ОК АС 1 К');
  });
  test('repeat fragments enforce unique locators and nonempty boundaries', () => {
    const rg = { ...make().radiograms[0], groups: ['ААААА','БББББ','ВВВВВ','ГГГГГ'] };
    expect(repeatReply('РПТ ГР 2 К', rg)).toBe('БББББ К');
    expect(repeatReply('РПТ АА БББББ К', rg)).toBe('ВВВВВ ГГГГГ К');
    expect(repeatReply('РПТ АБ 3 К', rg)).toBe('ААААА БББББ К');
    expect(repeatReply('РПТ БН 1 4 К', rg)).toBe('БББББ ВВВВВ К');
    expect(repeatReply('РПТ БН 1 2 К', rg)).toBeNull();
    expect(repeatReply('РПТ НР К', rg)).toBe(`НР ${rg.number} К`);
    expect(repeatReply('РПТ К', null, 'Ц К')).toBe('Ц К');
  });
  test('bot delays distinguish authentication/receipts and exact second signal gap', () => {
    expect(botDelay({ id: 'auth-self' }, false, () => 0)).toBe(2500);
    expect(botDelay({ id: 'rg-0-receipt' }, false, () => 1)).toBe(5000);
    expect(botDelay({ id: 'call' }, false, () => 1)).toBe(3000);
    expect(botDelay({ id: 'auth-self' }, true, () => 0)).toBe(1000);
    expect(botDelay({ id: 'signal-0-second' }, false)).toBe(0);
    expect(timeBand('first', 3000)).toContain('Отлично');
    expect(timeBand('first', 3000.001)).toContain('Хорошо');
  });
});

describe('Task5 real-time session', () => {
  test('preparing a variant needs no audio and the same seed starts the displayed table', () => {
    const { session, audio, persist } = harness(); session.stop(); audio.ready = false;
    const savedCount = persist.mock.calls.length;
    session.prepare({ groups: 30, role: 'subordinate' }, '99');
    expect(persist.mock.calls.length).toBe(savedCount);
    const prepared = structuredClone(session.state.variant);
    expect(session.state.status).toBe('idle'); expect(session.state.index).toBe(0);
    audio.ready = true; session.start(prepared.configuration, prepared.seed);
    expect(session.state.variant).toEqual(prepared);
  });
  test('bad seed does not cancel or replace the current running exchange', () => {
    const { session, audio } = harness(); const calls = audio.stopAll.mock.calls.length;
    expect(() => session.start({ groups: 30 }, '-1')).toThrow();
    expect(session.state.status).toBe('running'); expect(session.state.variant.seed).toBe('42'); expect(audio.stopAll.mock.calls.length).toBe(calls);
  });
  test.each(['main', 'subordinate'])('full %s exchange completes through audio/receipts without confirmation steps', async role => {
    const { session, audio, advanceClock } = harness({ role });
    let guard = 0;
    while (session.active && guard++ < 150) {
      if (session.state.status === 'playing') await advanceClock(5000);
      else if (session.step.kind === 'pause') await advanceClock(session.state.remaining * 1000);
      else {
        if (session.receipt) session.setDraft(session.step.expectedMessages[0]);
        session.submit(session.target.expectedMessages[0]);
      }
    }
    expect(session.state.status).toBe('completed');
    expect(session.state.attempts.filter(a => a.inputMethod !== 'bot').every(a => a.correct)).toBe(true);
    expect(audio.playSequence).toHaveBeenCalled();
    for (const call of audio.playSequence.mock.calls) expect(call[4]).toEqual({ spacing: 'text', protectedFromKey: true, speed: 50 });
    expect(audio.setCharWpm).not.toHaveBeenCalled();
    expect(session.state.events.some(e => e.kind === 'operatorDuty')).toBe(true);
  });
  test('bot AS causes one hidden ~minute wait and pause/resume preserves its remainder', async () => {
    const { session, advanceClock } = harness();
    session.state.index = session.state.variant.steps.findIndex(s => s.id === 'auth-request-wait'); session.enter();
    await advanceClock(2500); expect(session.state.remaining).toBe(55);
    await advanceClock(10000); expect(session.state.remaining).toBe(45);
    session.pause(); await advanceClock(120000); session.resume();
    await advanceClock(44999); expect(session.step.kind).toBe('pause');
    await advanceClock(1); expect(session.step.id).toBe('auth-counter-echo');
  });
  test.each(['main', 'subordinate'])('valid operator AS immediately releases the key and reveals received codes only after acknowledgment (%s)', async role => {
    const { session, advanceClock } = harness({ role });
    const incomingID = role === 'main' ? 'auth-counter' : 'auth-peer';
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === incomingID); session.enter();
    expect(session.state.decodedReceivedCodes).toEqual([]); expect(session.pendingReceivedCodes).toEqual([]);
    await advanceClock(5000);
    expect(session.state.decodedReceivedCodes).toEqual([]); expect(session.pendingReceivedCodes.length).toBe(1);
    expect(session.outgoingCodeMessage.text).toContain('З');
    expect(session.outgoingCodeMessage.groups).toEqual([]); // An echo must not disclose incoming meanings.
    session.submit(session.target.expectedMessages[0]); await advanceClock(5000);
    expect(session.step.id).toBe(role === 'main' ? 'auth-counter-wait' : 'auth-request-wait');
    session.submit('ОК АС 0 К'); expect(session.state.decodedReceivedCodes).toEqual([]); await advanceClock(5000);
    const pending = structuredClone(session.pendingReceivedCodes);
    session.submit('ОК АС 17 К');
    expect(session.state.remaining).toBe(0); expect(session.step.kind).toBe('transmit'); expect(session.state.status).toBe('running');
    expect(session.state.decodedReceivedCodes).toEqual(pending); expect(session.pendingReceivedCodes).toEqual([]);
    session.down('keyboard'); expect(session.state.pressed).toBe(true); session.release();
    session.pause(); const archive = structuredClone(session.archive()); session.stop(); session.restore(archive);
    expect(session.state.decodedReceivedCodes).toEqual(pending);
  });
  test.each(['main', 'subordinate'])('bot AS wait stays within 55–65s in role %s', async role => {
    const { session, audio, advanceClock } = harness({ role }); session.random = () => 1;
    const id = role === 'main' ? 'auth-request-wait' : 'auth-counter-wait';
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === id); session.enter();
    await advanceClock(5000); expect(session.state.remaining).toBe(65);
    const calls = audio.playSequence.mock.calls.length; await advanceClock(64999); expect(audio.playSequence.mock.calls.length).toBe(calls);
    await advanceClock(1); expect(audio.playSequence.mock.calls.length).toBe(calls + 1);
  });
  test('legacy AS archives apply the new policy while ten-second signal gaps are unchanged', async () => {
    const { session, advanceClock } = harness(); session.stop();
    const archive = structuredClone(session.archive()); delete archive.waitPolicy; archive.status = 'paused'; archive.remaining = 120;
    archive.index = archive.variant.steps.findIndex(s => s.id === 'auth-counter-wait-pause');
    session.restore(archive); session.resume(); expect(session.step.id).toBe('auth-self'); expect(session.state.remaining).toBe(0); session.stop();
    archive.index = archive.variant.steps.findIndex(s => s.id === 'auth-request-wait-pause'); session.restore(archive); expect(session.state.remaining).toBe(55); session.resume(); await advanceClock(55000); expect(session.step.id).toBe('auth-counter-echo'); session.stop();
    session.state.index = session.state.variant.steps.findIndex(s => s.id === 'signal-0-pause'); session.enter(); await advanceClock(9999); expect(session.step.kind).toBe('pause'); await advanceClock(1); expect(session.step.id).toBe('signal-0-second');
  });
  test('optional AS decodes an urgency offer without advancing or locking the operator', async () => {
    const { session, advanceClock } = harness();
    const gram = session.state.variant.radiograms.find(r => r.direction === 'receive');
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === `${gram.id}-offer`); session.enter();
    await advanceClock(5000); const index = session.state.index;
    expect(session.step.id).toBe(`${gram.id}-ready`); expect(session.state.decodedReceivedCodes).toEqual([]);
    session.submit('ОК АС 1 К');
    expect(session.state.index).toBe(index); expect(session.state.status).toBe('running'); expect(session.state.remaining).toBe(0);
    expect(session.state.decodedReceivedCodes[0].groups[0]).toEqual({ code: gram.urgencyCode, meaning: decode(session.state.variant.tdr, gram.urgencyCode).expression });
    session.submit('ЩРЖ К'); await advanceClock(5000);
    session.setDraft('ПРИНЯТЫЙ ЧЕРНОВИК'); const receiveIndex = session.state.index, receipt = session.receipt.id;
    session.submit('ОК АС 99 К');
    expect(session.state.index).toBe(receiveIndex); expect(session.state.draft).toBe('ПРИНЯТЫЙ ЧЕРНОВИК'); expect(session.receipt.id).toBe(receipt); expect(session.summary.receivedGroups).toBe(0);
    session.pause(); const archive = structuredClone(session.archive()); session.stop(); session.restore(archive);
    expect(session.state.decodedReceivedCodes).toHaveLength(2); expect(session.state.draft).toBe('ПРИНЯТЫЙ ЧЕРНОВИК');
  });
  test('legacy malformed successful AS and injected revealed meanings cannot bypass acknowledgment', async () => {
    const { session, advanceClock } = harness({ role: 'subordinate' });
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === 'auth-peer'); session.enter(); await advanceClock(5000); session.pause();
    const archive = structuredClone(session.archive()); session.stop();
    archive.decodedReceivedCodes = [{ stepID: 'auth-peer', groups: [{ code: 'З??', meaning: 'ПОДДЕЛКА' }] }];
    session.restore(archive); expect(session.state.decodedReceivedCodes).toEqual([]); session.stop();
    archive.attempts.push({ stepID: 'auth-request-wait', input: 'ОК АС 0 К', correct: true });
    expect(() => session.restore(archive)).toThrow('повреждённый');
  });
  test('eight dots reset all transmission and do not create an error attempt', () => {
    const { session } = harness(); session.state.input = 'НЕВЕРНО'; session.state.buffer = '........'; session.commit();
    expect(session.state.input).toBe(''); expect(session.state.buffer).toBe(''); expect(session.state.attempts).toHaveLength(0);
    expect(session.state.events.at(-1).kind).toBe('operatorCorrection');
  });
  test('keyboard/hardware sources never double-sound hardware and release correctly', async () => {
    const { session, audio, advanceClock } = harness();
    session.down('hardware'); session.down('keyboard'); await advanceClock(80); session.up('keyboard');
    expect(session.state.pressed).toBe(true); session.up('hardware'); expect(session.state.pressed).toBe(false);
    expect(audio.keyDown).not.toHaveBeenCalled(); expect(session.state.buffer).toBe('.');
    session.down('keyboard'); session.release(); expect(audio.keyDown).toHaveBeenCalledWith('local'); expect(audio.keyUp).toHaveBeenCalledWith('local');
  });
  test('internal K does not prematurely submit and silence never invents K', async () => {
    const { session, advanceClock } = harness({ role: 'subordinate' });
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === 'quality-reply'); session.enter();
    session.state.input = 'ЩСА 3 К'; session.releasedAt = 0; await advanceClock(1000);
    expect(session.step.id).toBe('quality-reply'); expect(session.state.attempts).toHaveLength(0);
    session.state.input = 'ЩСА 3 К ЩСА?'; session.releasedAt = 1000; await advanceClock(10000);
    expect(session.state.attempts).toHaveLength(0); expect(session.state.input).toContain('ЩСА?');
  });
  test('wrong transmission requests RPT, then first new key starts clean', async () => {
    const { session, advanceClock } = harness(); session.submit('ЩСА К');
    expect(session.state.attempts.at(-1).correct).toBe(false); expect(session.state.status).toBe('playing');
    await advanceClock(3000); session.down('keyboard'); expect(session.state.input).toBe(''); expect(session.step.id).toBe('call');
  });
  test('typed reception errors are recorded independently of correct receipt; paper is unverified', async () => {
    for (const receptionMode of ['typed', 'paper']) {
      const { session, advanceClock } = harness({ receptionMode });
      session.state.index = session.state.variant.steps.findIndex(s => s.kind === 'receive' && s.bodyGroups); session.enter(); await advanceClock(5000);
      const receiptID = session.receipt.id; session.setDraft('ОШИБОЧНО К'); session.submit(session.receipt.expectedMessages[0]);
      expect(session.state.attempts.find(a => a.stepID === receiptID)?.correct).toBe(true);
      if (receptionMode === 'typed') expect(session.state.attempts.find(a => a.inputMethod === 'reception')?.correct).toBe(false);
      else { expect(session.state.attempts.some(a => a.inputMethod === 'reception')).toBe(false); expect(session.state.events.some(e => e.kind === 'paperUnverified')).toBe(true); }
    }
  });
  test('resume restored transmit never skips the unfinished step', async () => {
    const { session, advanceClock } = harness(); session.state.input = 'АБ'; session.stop(); const archive = session.archive(); archive.status = 'running';
    session.restore(archive); expect(session.state.status).toBe('paused'); session.resume(); await advanceClock(5000);
    expect(session.step.id).toBe('call'); expect(session.state.input).toBe('АБ');
  });
  test('cancelled audio completion cannot advance a paused or stopped session', async () => {
    const { session, audio, advanceClock } = harness(); let complete;
    audio.playSequence.mockImplementation(() => new Promise(resolve => { complete = resolve; }));
    session.submit(session.target.expectedMessages[0]); await advanceClock(5000); const index = session.state.index;
    session.pause(); complete({ cancelled: false }); await Promise.resolve(); expect(session.state.index).toBe(index); expect(session.state.status).toBe('paused');
  });
  test('a paused pending bot response survives an archive round trip', async () => {
    const { session, audio, advanceClock } = harness();
    session.submit(session.target.expectedMessages[0]); session.pause();
    const archive = structuredClone(session.archive());
    expect(archive.pendingReply.text).toBe(session.step.botMessage);
    session.stop(); session.restore(archive); session.resume(); await advanceClock(5000);
    expect(audio.playSequence).toHaveBeenCalled(); expect(session.step.id).toBe('quality'); expect(session.state.status).toBe('running');
  });
  test('keyed service commands work at internal-K steps, and invalid service input resets cleanly', async () => {
    const { session, advanceClock } = harness({ role: 'subordinate' });
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === 'quality-reply'); session.enter();
    session.state.input = 'ЩРС 10 К'; session.releasedAt = 0; await advanceClock(1000);
    expect(session.state.input).toBe(''); expect(session.state.variant.configuration.botSpeed).toBe(50); expect(session.step.id).toBe('quality-reply');
    session.state.input = 'ЩРС А К'; session.releasedAt = 1000; await advanceClock(1000);
    expect(session.state.error).toContain('6–30'); session.down('keyboard'); expect(session.state.input).toBe(''); expect(session.state.error).toBe('');
  });
  test('malformed accepted auth attempts and pending replies cannot poison archive restore', () => {
    const { session } = harness(); session.stop(); const archive = structuredClone(session.archive()); const original = session.state;
    archive.index = archive.variant.steps.findIndex(s => s.id === 'auth-request-echo');
    archive.attempts.push({ stepID: 'auth-peer', input: 'BAD BAD К', correct: true });
    expect(() => session.restore(archive)).toThrow('повреждённый'); expect(session.state).toBe(original);
    archive.attempts = []; archive.pendingReply = { text: {}, repeating: false };
    expect(() => session.restore(archive)).toThrow('повреждённый'); expect(session.state).toBe(original);
  });
  test('archive validation rejects incomplete nested objects and keeps current state intact', () => {
    const { session } = harness(); session.stop(); const original = session.archive();
    for (const mutate of [a => { a.variant.tdr.rowKeys = []; }, a => { a.variant.steps[0] = {}; }, a => { a.variant.radiograms[0].groups = null; }, a => { a.decodedReceivedCodes = [{}]; }, a => { a.attempts = [{}]; }]) { const corrupt = structuredClone(original); mutate(corrupt); expect(() => session.restore(corrupt)).toThrow('повреждённый'); expect(session.state.variant.seed).toBe('42'); }
    expect(() => session.restore(original)).not.toThrow();
  });
  test('old virtual journal fields are ignored and never exported or checked', () => {
    const { session } = harness(); session.stop(); const archive = session.archive(); archive.journal = [{ arbitrary: 'legacy data' }];
    expect(() => session.restore(archive)).not.toThrow(); expect(session.archive().journal).toBeUndefined();
    expect(session.journalIssues).toBeUndefined(); expect(session.journal).toBeUndefined();
    session.hint(true); expect(session.state.hints).toBe(1);
  });
  test('portable export hides unfinished incoming material and restores the same variant', () => {
    const { session } = harness(); const incoming = session.state.variant.radiograms.find(r => r.direction === 'receive');
    session.stop(); const exported = session.exportData();
    expect(exported.variant).toBeUndefined(); expect(exported.reviewVariant).toBeNull();
    expect(JSON.stringify(exported)).not.toContain(incoming.wireText);
    const original = structuredClone(session.state.variant); session.restore(JSON.parse(JSON.stringify(exported)));
    expect(session.state.variant).toEqual(original);
  });
  test('event log never exposes a bot message before it has finished sounding', async () => {
    const { session, audio, advanceClock } = harness();
    audio.playSequence.mockImplementation(() => new Promise(() => {}));
    session.submit(session.target.expectedMessages[0]); const incoming = session.step.botMessage; await advanceClock(5000);
    expect(session.state.events.findLast(e => e.kind === 'bot').detail).toBe('Корреспондент начал передачу');
    expect(session.state.events.some(e => e.detail === incoming)).toBe(false);
    session.stop(); expect(JSON.stringify(session.exportData())).not.toContain(incoming);
  });
  test('summary separates correctly copied reception and transmitted groups without journal requirements', async () => {
    const { session, advanceClock } = harness();
    const outgoing = session.state.variant.radiograms.find(r => r.direction === 'transmit');
    const incoming = session.state.variant.radiograms.find(r => r.direction === 'receive');
    session.state.index = session.state.variant.steps.findIndex(s => s.id === outgoing.id); session.enter(); session.submit(outgoing.wireText);
    expect(session.summary.transmittedGroups).toBe(30); expect(session.summary.receivedGroups).toBe(0);
    session.cancel(); session.state.index = session.state.variant.steps.findIndex(s => s.id === incoming.id); session.enter(); await advanceClock(5000);
    session.setDraft('ОШИБОЧНО К'); session.submit(session.receipt.expectedMessages[0]);
    expect(session.summary.receivedGroups).toBe(0); expect(session.summary.failedChecks).toBe(1);
    session.stop(); expect(() => session.restore(session.archive())).not.toThrow();
  });
});
