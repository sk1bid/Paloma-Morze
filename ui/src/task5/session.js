import { generate, resolveStep, validate, normalizeTransmission, tokens, waitMinutes, codeMeanings, authenticationWait, botDelay, repeatReply } from './domain.js';
import { radiogramRecovery, recoveryTarget, mergeRadiogramCorrection, cancelLastRadiogramGroup } from './radiogramRecovery.js';
import { developmentPrefix } from './development.js';

// The clock, audio and scheduler are injected so real-time radio behavior can be
// exercised without speakers or wall-clock waits in tests.
export class Task5Session {
  constructor({
    cells,
    audio,
    pattern,
    decodePattern,
    now = () => performance.now(),
    random = Math.random,
    development = false,
    changed = () => {},
    persist = () => {}
  }) {
    Object.assign(this, {
      cells,
      audio,
      pattern,
      decodePattern,
      now,
      random,
      development,
      changed,
      persist: development ? () => {} : persist
    });
    this.state = {
      status: 'idle',
      variant: null,
      index: 0,
      input: '',
      draft: '',
      buffer: '',
      error: '',
      notice: '',
      events: [],
      attempts: [],
      decodedReceivedCodes: [],
      radiogramRecovery: null,
      elapsed: 0,
      remaining: 0,
      repeats: 0,
      hints: 0,
      pressed: false,
      tape: []
    };
    this.epoch = 0;
    this.lastMessage = null;
    this.pendingReceivedCodes = [];
  }
  get active() {
    return ['running', 'playing', 'paused'].includes(this.state.status);
  }
  get step() {
    const s = this.state.variant?.steps[this.state.index];
    return s ? resolveStep(s, this.state.variant, this.state.attempts) : null;
  }
  get receipt() {
    if (this.step?.kind !== 'receive') return null;
    const s = this.state.variant.steps[this.state.index + 1];
    return s?.id.endsWith('-receipt') && s.direction === 'transmit' ? s : null;
  }
  get target() {
    if (this.state.radiogramRecovery) {
      const gram = this.state.variant.radiograms.find(gram => gram.id === this.state.radiogramRecovery.radiogramID);
      return recoveryTarget(this.state.radiogramRecovery, this.step, gram);
    }
    return this.receipt || this.step;
  }
  get summary() {
    const grams = this.state.variant?.radiograms || [];
    const completed = direction => grams.filter(r => r.direction === direction && this.state.attempts.some(a => a.stepID === r.id && a.correct && !['bot', 'service', 'correction', 'development'].includes(a.inputMethod))).reduce((n, r) => n + r.groups.length, 0);
    const total = direction => grams.filter(r => r.direction === direction).reduce((n, r) => n + r.groups.length, 0);
    return {
      transmittedGroups: completed('transmit'),
      receivedGroups: completed('receive'),
      totalTransmitGroups: total('transmit'),
      totalReceiveGroups: total('receive'),
      failedChecks: this.state.attempts.filter(a => !a.correct).length,
      completedSteps: this.state.index,
      totalSteps: this.state.variant?.steps.length || 0,
      hints: this.state.hints,
      repeats: this.state.repeats
    };
  }
  get outgoingCodeMessage() {
    const target = this.target;
    if (!target || target.direction !== 'transmit' || !this.state.variant) return null;
    const text = target.expectedMessages[0] || '';
    const groups = codeMeanings(text, target, this.state.variant);
    if (!groups.length) return null;
    const withheld = new Set(this.pendingReceivedCodes.flatMap(entry => entry.groups.map(group => group.code)));
    return { text, groups: groups.filter(group => !withheld.has(group.code)) };
  }
  emit(save = true) {
    this.changed({
      ...this.state
    });
    if (save) this.persist(this.archive());
  }
  log(kind, detail) {
    this.state.events.push({
      date: new Date().toISOString(),
      stepID: this.step?.id,
      kind,
      detail
    });
  }
  archive() {
    const {
      pressed: _pressed,
      buffer: _buffer,
      tape: _tape,
      journal: _legacyJournal,
      ...s
    } = this.state;
    return {
      schemaVersion: 1,
      ...s,
      developerReview: this.development,
      pendingReply: this.active ? this.pausedReply || this.playingReply || null : null,
      lastBotMessage: this.lastMessage,
      pendingReceivedCodes: this.pendingReceivedCodes,
      waitPolicy: 'hidden-bot-as-v1',
      startsNewTransmission: this.newTransmission === true,
      remaining: this.state.remaining
    };
  }
  prepare(configuration, seed = String(Date.now())) {
    if (this.active) return;
    const variant = generate(configuration, seed, this.cells);
    this.newTransmission = false;
    this.state = {
      ...this.state,
      variant,
      status: 'idle',
      index: 0,
      input: '',
      draft: '',
      buffer: '',
      error: '',
      notice: '',
      radiogramRecovery: null
    };
    this.emit(false);
  }
  start(configuration, seed = String(Date.now())) {
    if (!this.audio.ready) throw new Error('Звуковой движок ещё не готов.');
    const variant = generate(configuration, seed, this.cells);
    this.cancel();
    this.pausedReply = null;
    this.newTransmission = false;
    this.state = {
      ...this.state,
      status: 'running',
      variant,
      index: 0,
      input: '',
      draft: '',
      buffer: '',
      events: [],
      attempts: [],
      decodedReceivedCodes: [],
      radiogramRecovery: null,
      elapsed: 0,
      remaining: 0,
      repeats: 0,
      hints: 0,
      error: '',
      notice: '',
      tape: []
    };
    this.started = this.now();
    this.lastMessage = null;
    this.pendingReceivedCodes = [];
    this.enter();
  }
  restore(data) {
    if (this.active) throw new Error('Сначала остановите тренировку.');
    if (!this.development && (data?.developerReview || Array.isArray(data?.attempts) && data.attempts.some(attempt => attempt.developerReview || attempt.inputMethod === 'development'))) {
      throw new Error('DEV-просмотр нельзя открыть как результат обычной тренировки.');
    }
    if (data?.format === 'paloma.task5.export') {
      if (data.profileID !== 'task5.photos.v8.final-k') throw new Error('Неподдерживаемый профиль тренировки.');
      data = { ...data, variant: data.reviewVariant || generate(data.configuration, data.seed, this.cells) };
    }
    if (!validArchive(data)) throw new Error('Неподдерживаемый или повреждённый архив Задачи 5.');
    this.cancel();
    this.newTransmission = data.startsNewTransmission === true;
    this.state = {
      ...this.state,
      ...structuredClone(data),
      journal: undefined,
      decodedReceivedCodes: structuredClone(data.decodedReceivedCodes || []),
      radiogramRecovery: structuredClone(data.radiogramRecovery || null),
      pressed: false,
      buffer: '',
      tape: []
    };
    this.state.status = ['running', 'playing', 'paused'].includes(data.status) ? 'paused' : data.status;
    this.started = this.now() - this.state.elapsed * 1000;
    this.waitUntil = null;
    if (this.step?.kind === 'pause') {
      const previous = this.state.variant.steps[this.state.index - 1];
      const wait = authenticationWait(this.step, previous, this.random);
      if (wait === 0) {
        this.state.index++;
        this.state.remaining = 0;
      } else {
        this.state.remaining = wait == null || data.waitPolicy === 'hidden-bot-as-v1'
          ? Math.min(wait == null ? 10 : 65, data.remaining || 0)
          : Math.ceil(wait / 1000);
        this.waitUntil = this.now() + this.state.remaining * 1000;
      }
    }
    this.lastMessage = data.lastBotMessage || null;
    const reconstructed = this.decodedFromAttempts();
    this.pendingReceivedCodes = reconstructed.pending;
    this.state.decodedReceivedCodes = reconstructed.revealed;
    this.pausedReply = data.pendingReply || (data.status === 'playing' ? {
      text: this.step?.botMessage,
      repeating: false
    } : null);
    this.log('restored', 'Архив открыт; активный обмен поставлен на паузу');
    this.emit();
  }
  decodedFromAttempts() {
    const pending = [], revealed = [], previous = [];
    for (const attempt of this.state.attempts) {
      const original = this.state.variant.steps.find(step => step.id === attempt.stepID);
      if (!original || !attempt.correct) continue;
      const step = resolveStep(original, this.state.variant, previous);
      if (step.direction === 'receive' && attempt.inputMethod === 'bot') {
        const groups = codeMeanings(attempt.input, step, this.state.variant);
        if (groups.length) pending.push({ stepID: step.id, groups });
      }
      if ((attempt.inputMethod === 'service' || step.direction === 'transmit' && ['auth-request-wait', 'auth-counter-wait'].includes(step.id)) && waitMinutes(attempt.input) != null) {
        revealed.push(...pending.splice(0));
      }
      previous.push(attempt);
    }
    return { pending, revealed };
  }
  exportData() {
    if (this.development) throw new Error('DEV-просмотр не экспортируется как результат тренировки.');
    if (this.active || !this.state.variant) throw new Error('Остановите тренировку перед экспортом.');
    const archive = this.archive();
    const { variant, pendingReceivedCodes: _pending, ...result } = archive;
    const played = this.state.events.some(event => event.kind === 'botDone' && event.stepID === this.step?.id);
    return {
      ...result,
      format: 'paloma.task5.export',
      seed: variant.seed,
      profileID: variant.profileID,
      configuration: variant.configuration,
      reviewVariant: this.state.status === 'completed' ? variant : null,
      lastBotMessage: played ? this.lastMessage : null
    };
  }
  developmentJump(index) {
    if (!this.development) throw new Error('Навигация DEV недоступна в обычной тренировке.');
    const variant = this.state.variant;
    if (!variant) throw new Error('Сначала подготовьте вариант.');
    const prefix = developmentPrefix(variant, index);
    this.cancel();
    this.state = {
      ...this.state, ...prefix, index, status: 'paused',
      input: '', draft: '', buffer: '', error: '', notice: '',
      radiogramRecovery: null, elapsed: 0, remaining: 0,
      pressed: false, tape: [], repeats: 0, hints: 0,
      developmentPreview: true
    };
    this.started = this.now();
    this.waitUntil = null;
    this.pausedReply = null;
    this.newTransmission = false;
    this.releasedAt = null;
    this.skipNextBotDelay = false;
    this.lastMessage = prefix.attempts.findLast(attempt => attempt.inputMethod === 'bot')?.input || null;
    const decoded = this.decodedFromAttempts();
    this.pendingReceivedCodes = decoded.pending;
    this.state.decodedReceivedCodes = decoded.revealed;
    this.log('developerJump', 'DEV: выбран этап; звук и продвижение остановлены');
    this.emit(false);
  }
  developmentEnter() {
    if (!this.development) throw new Error('Навигация DEV недоступна в обычной тренировке.');
    if (!this.audio.ready) throw new Error('Звуковой движок ещё не готов.');
    this.state.developmentPreview = false;
    if (this.state.radiogramRecovery && this.state.status === 'paused') this.resume();
    else { this.cancel(); this.enter(); }
  }
  developmentGroupError() {
    if (!this.development) throw new Error('Навигация DEV недоступна в обычной тренировке.');
    const variant = this.state.variant;
    const index = variant.steps.findIndex(step => step.direction === 'transmit' && step.bodyGroups > 0);
    this.developmentJump(index);
    this.developmentEnter();
    const gram = variant.radiograms.find(gram => gram.id === this.step.radiogramID);
    const groups = [...gram.groups];
    groups[0] = (groups[0][0] === 'А' ? 'Б' : 'А') + groups[0].slice(1);
    this.submit(`${gram.header} = ${gram.urgencyCode} ${gram.address} = ${groups.join(' ')} К`, 'development');
    this.pause();
    this.state.developmentPreview = true;
    this.emit(false);
  }
  cancel() {
    this.epoch++;
    this.release();
    this.audio.stopAll();
    this.playingReply = null;
    this.replyAction = null;
  }
  stop(reason = 'Тренировка остановлена', status = 'aborted') {
    this.tick();
    this.cancel();
    this.state.status = status;
    this.state.remaining = 0;
    this.log(status, reason);
    this.emit();
  }
  advance(count = 1) {
    this.release();
    this.state.input = '';
    this.state.buffer = '';
    this.state.error = '';
    this.state.notice = '';
    this.state.radiogramRecovery = null;
    this.newTransmission = false;
    this.state.index += count;
    this.enter();
  }
  enter() {
    this.state.status = 'running';
    this.waitUntil = null;
    this.state.remaining = 0;
    while (this.step?.kind === 'administrative') {
      this.log('operatorDuty', `${this.step.title} — самостоятельное действие`);
      this.state.index++;
    }
    let s = this.step;
    if (s?.kind === 'pause') {
      const previous = this.state.variant.steps[this.state.index - 1];
      if (s.id.endsWith('-wait-pause') && previous?.direction === 'transmit') {
        this.log('operatorWaitAcknowledged', 'Подтверждение принято; ключ доступен');
        this.state.index++;
        s = this.step;
      }
    }
    if (!s) {
      this.stop('Обмен завершён', 'completed');
      return;
    }
    this.log('step', s.title);
    this.state.draft = '';
    if (s.kind === 'pause') {
      const previous = this.state.variant.steps[this.state.index - 1];
      const duration = authenticationWait(s, previous, this.random) ?? s.requiredPauseSeconds * 1000;
      this.waitUntil = this.now() + duration;
      this.state.remaining = Math.ceil(duration / 1000);
      this.state.notice = 'Корреспондент готовит ответ';
      this.log('waitStarted', 'Корреспондент готовит ответ');
    } else if (s.botMessage) {
      this.lastMessage = s.botMessage;
      void this.play(s.botMessage);
    }
    this.emit();
  }
  async play(text, repeating = false) {
    const epoch = ++this.epoch;
    const stepID = this.step?.id;
    this.release();
    this.state.buffer = '';
    this.state.status = 'playing';
    this.state.notice = 'Корреспондент готовит ответ';
    this.playingReply = {
      text,
      repeating
    };
    const delay = this.skipNextBotDelay && !repeating ? 0 : botDelay(this.step, repeating, this.random);
    this.skipNextBotDelay = false;
    this.replyAt = this.now() + delay;
    this.replyAction = async () => {
      if (epoch !== this.epoch) return;
      this.replyAction = null;
      this.state.notice = 'Корреспондент передаёт';
      this.log('bot', 'Корреспондент начал передачу');
      this.emit();
      const result = await this.audio.playSequence([...text], this.pattern, null, pulse => {
        if (epoch === this.epoch) {
          this.state.pulse = pulse;
          this.changed({
            ...this.state
          });
        }
      }, {
        spacing: 'text',
        protectedFromKey: true,
        speed: this.state.variant.configuration.botSpeed
      });
      if (epoch !== this.epoch || this.step?.id !== stepID) return;
      this.playingReply = null;
      this.state.pulse = null;
      if (result.cancelled || result.error) {
        this.state.error = result.error || 'Передача прервана';
        this.stop(this.state.error, 'interrupted');
        return;
      }
      this.state.status = 'running';
      this.state.notice = '';
      this.log('botDone', 'Передача корреспондента окончена');
      if (!repeating) {
        const groups = codeMeanings(text, this.step, this.state.variant);
        if (groups.length) this.pendingReceivedCodes.push({ stepID: this.step.id, groups });
        this.record(text, { correct: true, errors: 0 }, 'bot');
      }
      if (!repeating && (this.step.kind === 'listen' || this.step.kind === 'receive' && !this.receipt)) {
        this.advance();
      } else this.emit();
    };
    this.emit();
    if (!delay) await this.replyAction();
  }
  tick() {
    if (!this.active) return;
    this.state.elapsed = Math.max(this.state.elapsed, (this.now() - this.started) / 1000);
    if (this.state.status === 'playing' && this.replyAction && this.now() >= this.replyAt) void this.replyAction();
    if (this.state.status === 'running' && this.waitUntil != null) {
      this.state.remaining = Math.max(0, Math.ceil((this.waitUntil - this.now()) / 1000));
      if (!this.state.remaining) {
        this.log('waitFinished', 'Время ожидания выдержано');
        this.skipNextBotDelay = this.step?.id.endsWith('-wait-pause');
        this.advance();
        return;
      }
    }
    if (this.state.status === 'running' && !this.state.pressed && this.releasedAt != null) {
      const gap = this.now() - this.releasedAt,
        unit = 6000 / this.state.variant.configuration.keySpeed;
      if (this.state.buffer && gap >= 2.5 * unit) this.commit();
      if (!this.state.buffer && gap >= 8 * unit) {
        this.releasedAt = null;
        if (this.state.input && !this.state.input.endsWith(' ')) this.state.input += ' ';
        const text = normalizeTransmission(this.state.input, this.target, this.state.variant),
          words = tokens(text);
        const internal = this.target.expectedMessages.some(e => {
          const expected = tokens(e);
          return words.length < expected.length && expected[words.length - 1] === 'К';
        });
        const service = ['ЩРС', 'ЩРЩ', 'РПТ'].includes(words[0]);
        if (words.at(-1) === 'К' && (service || !internal)) this.submit(text, 'key');
        else if (words.length) this.state.notice = 'Продолжайте передачу. Сообщение завершается К; перебой — восемь точек.';
      }
    }
    const save = this.now() - (this.lastBackgroundSave || 0) >= 1000;
    if (save) this.lastBackgroundSave = this.now();
    this.emit(save);
  }
  record(input, result, inputMethod, step = this.step) {
    this.state.attempts.push({
      date: new Date().toISOString(),
      stepID: step.id,
      input,
      ...result,
      aided: this.guideVisible || false,
      inputMethod
    });
  }
  submit(raw = this.state.input, method = 'text') {
    if (this.state.status !== 'running' || !this.target || this.step.kind === 'pause') return;
    const text = normalizeTransmission(raw, this.target, this.state.variant),
      words = tokens(text);
    if (['ЩРС', 'ЩРЩ', 'РПТ'].includes(words[0])) {
      this.service(text);
      return;
    }
    const scriptedAS = ['auth-request-wait', 'auth-counter-wait'].includes(this.step.id);
    if (!scriptedAS && words[0] === 'ОК' && words[1] === 'АС' && this.pendingReceivedCodes.length) {
      if (waitMinutes(text) == null) {
        this.state.error = 'Передайте ОК АС <1–99> К.';
        this.newTransmission = true;
      } else {
        this.record(text, { correct: true, errors: 0 }, 'service');
        this.revealReceivedCodes();
        this.state.input = '';
        this.state.buffer = '';
        this.state.error = '';
      }
      this.emit();
      return;
    }
    if (this.state.radiogramRecovery) {
      this.submitRadiogramCorrection(text, method);
      return;
    }
    const check = validate(text, this.target, this.state.variant);
    this.record(text, check, method, this.target);
    if (!check.correct) {
      this.state.error = check.message;
      this.newTransmission = true;
      this.log('rejected', check.message);
      const gram = this.state.variant.radiograms.find(gram => gram.id === this.step.radiogramID && gram.direction === 'transmit');
      if (gram && this.step.bodyGroups) {
        this.state.radiogramRecovery = radiogramRecovery(text, gram, this.state.variant.tdr);
        this.state.input = '';
        this.state.buffer = '';
      }
      void this.play(this.state.radiogramRecovery?.request || 'РПТ К', true);
      this.emit();
      return;
    }
    if (['auth-request-wait', 'auth-counter-wait'].includes(this.step.id) && this.step.direction === 'transmit') {
      this.revealReceivedCodes();
    }
    if (this.receipt) {
      if (this.state.variant.configuration.receptionMode === 'typed') this.record(this.state.draft, validate(this.state.draft, this.step, this.state.variant), 'reception');else this.log('paperUnverified', 'Приём на бумаге; точность не проверена');
      this.log('accepted', text);
      this.advance(2);
    } else {
      this.log('accepted', text);
      this.advance();
    }
  }
  submitRadiogramCorrection(text, method) {
    const recovery = this.state.radiogramRecovery;
    const gram = this.state.variant.radiograms.find(gram => gram.id === recovery.radiogramID);
    const merged = mergeRadiogramCorrection(recovery, text, gram, this.state.variant.tdr);
    if (merged == null) {
      this.record(text, { correct: false, errors: 1 }, 'correction');
      this.state.error = 'Исправьте запрошенную часть радиограммы и завершите К.';
      this.log('correctionRejected', recovery.request);
    } else {
      const check = validate(merged, this.step, this.state.variant);
      this.record(text, recovery.request === 'РПТ АЛ К' ? check : { correct: true, errors: 0 }, 'correction');
      if (check.correct) {
        this.record(merged, check, method);
        this.log('radiogramCorrected', 'Исправленные части объединены; радиограмма проверена полностью');
        this.advance();
        return;
      }
      this.state.radiogramRecovery = radiogramRecovery(merged, gram, this.state.variant.tdr);
      this.state.error = check.message;
      this.log('correctionAccepted', 'Часть исправлена; запрошена следующая часть');
    }
    this.newTransmission = true;
    this.state.input = '';
    this.state.buffer = '';
    void this.play(this.state.radiogramRecovery.request, true);
    this.emit();
  }
  revealReceivedCodes() {
    this.state.decodedReceivedCodes.push(...this.pendingReceivedCodes);
    this.pendingReceivedCodes = [];
    this.log('codesDecoded', 'Расшифровка принятых кодов открыта после подтверждения ОК АС');
  }
  service(text) {
    const words = tokens(text);
    let error;
    if (words.at(-1) !== 'К') error = 'Завершите служебную команду знаком К.';else if (['ЩРС', 'ЩРЩ'].includes(words[0])) {
      const speed = words.length === 2 ? this.state.variant.configuration.botSpeed + (words[0] === 'ЩРС' ? -5 : 5) : words.length === 3 && /^\d+$/.test(words[1]) && +words[1] >= 6 && +words[1] <= 30 ? +words[1] * 5 : null;
      if (speed == null) error = 'Скорость указывается в группах/мин: 6–30.';else {
        this.state.variant.configuration.botSpeed = Math.max(30, Math.min(150, speed));
        this.log('speed', `${this.state.variant.configuration.botSpeed} знаков/мин`);
      }
    } else {
      const rg = this.state.variant.radiograms.find(r => r.id === this.step.radiogramID && r.direction === 'receive');
      const reply = repeatReply(text, rg, this.lastMessage);
      if (!reply) error = 'Нет передачи для повтора или указан неверный диапазон групп.';else {
        this.state.repeats++;
        this.log('repeat', text);
        void this.play(reply, true);
      }
    }
    this.state.input = '';
    this.state.error = error || '';
    this.newTransmission = !!error;
    this.emit();
  }
  pause() {
    if (!['running', 'playing'].includes(this.state.status)) return;
    this.tick();
    this.pausedReply = this.playingReply;
    this.pauseAt = this.now();
    this.cancel();
    this.state.status = 'paused';
    this.log('paused', 'Пауза');
    this.emit();
  }
  resume() {
    if (this.state.status !== 'paused') return;
    if (!this.audio.ready) {
      this.state.error = 'Звуковой движок недоступен';
      this.emit();
      return;
    }
    if (this.waitUntil != null) this.waitUntil = this.now() + this.state.remaining * 1000;
    this.state.status = 'running';
    this.log('resumed', 'Тренировка продолжена');
    const reply = this.pausedReply;
    this.pausedReply = null;
    if (reply?.text) void this.play(reply.text, reply.repeating);
    this.emit();
  }
  down(source = 'keyboard') {
    if (this.state.status !== 'running' || !this.target || this.step.kind === 'pause' || this.state.pressed || !this.audio.ready) return;
    if (this.newTransmission) {
      this.state.input = '';
      this.state.buffer = '';
      this.state.error = '';
      this.newTransmission = false;
    }
    this.source = source;
    this.state.pressed = true;
    this.pressedAt = this.now();
    this.pressedDate = Date.now();
    this.releasedAt = null;
    if (source !== 'hardware') this.audio.keyDown('local');
    this.emit();
  }
  up(source = 'keyboard') {
    if (!this.state.pressed || this.source !== source) return;
    this.state.pressed = false;
    if (source !== 'hardware') this.audio.keyUp('local');
    this.releasedAt = this.now();
    const duration = this.now() - this.pressedAt;
    const pulse = duration >= 12000 / this.state.variant.configuration.keySpeed ? '-' : '.';
    this.state.buffer += pulse;
    this.state.tape.push({
      start: this.pressedDate,
      end: Date.now(),
      type: pulse === '.' ? 'dot' : 'dash'
    });
    if (this.state.tape.length > 300) this.state.tape.shift();
    this.emit();
  }
  release() {
    if (this.state.pressed) this.up(this.source);
    this.audio.keyUp('local');
  }
  commit() {
    const pattern = this.state.buffer;
    if (!pattern) return;
    if (/^\.{8,}$/.test(pattern)) {
      const radiogram = this.step?.direction === 'transmit' && this.step.bodyGroups > 0;
      const before = this.state.input;
      this.state.input = radiogram ? cancelLastRadiogramGroup(before) : '';
      this.log('operatorCorrection', `Перебой: отменена ${radiogram ? 'группа' : 'передача'} «${before.slice(this.state.input.length)}»`);
      this.state.error = '';
      this.newTransmission = false;
      this.state.notice = radiogram ? 'Перебой принят. Передайте последнюю группу заново.' : 'Перебой принят. Передайте сообщение заново.';
    } else this.state.input += pattern === '-----' ? '0' : this.decodePattern(pattern) || '�';
    this.state.buffer = '';
  }
  setInput(input) {
    this.state.input = input;
    this.emit();
  }
  setDraft(draft) {
    this.state.draft = draft;
    this.emit();
  }
  hint(visible) {
    this.guideVisible = visible;
    if (visible) {
      this.state.hints++;
      this.log('hint', 'Открыта подсказка');
    }
    this.emit();
  }
}
function validArchive(data) {
  if (!data || data.schemaVersion !== 1) return false;
  const v = data.variant;
  if (!v || v.profileID !== 'task5.photos.v8.final-k') return false;
  if (!/^\d+$/.test(v.seed) || BigInt(v.seed) > (1n << 64n) - 1n) return false;
  const config = v.configuration;
  if (!config || !['main', 'subordinate'].includes(config.role) || !['typed', 'paper'].includes(config.receptionMode)) return false;
  if (!['letters', 'digits'].includes(config.charset) || ![30, 60].includes(config.groups)) return false;
  if (!['botSpeed', 'keySpeed'].every(key => Number.isInteger(config[key]) && config[key] >= 30 && config[key] <= 150 && config[key] % 5 === 0)) return false;
  if (!textFields(v, ['ownCallsign', 'botCallsign'])) return false;
  if (!textFields(v.radioData, ['networkNumber', 'mainFrequency', 'reserveFrequency'])) return false;
  const t = v.tdr;
  if (!t || !Array.isArray(t.cells) || t.cells.length !== 100) return false;
  const validAxis = axis => Array.isArray(axis) && axis.length === 10 && axis.every(key => typeof key === 'string' && [...key].length === 2) && new Set(axis.join('')).size === 20;
  if (!validAxis(t.rowKeys) || !validAxis(t.columnKeys)) return false;
  const validCell = cell => {
    if (!cell || !Number.isInteger(cell.row) || !Number.isInteger(cell.column)) return false;
    if (cell.row < 0 || cell.row > 9 || cell.column < 0 || cell.column > 9 || cell.number !== `${cell.row}${cell.column}`) return false;
    return ['expressionId', 'expression', 'printedLetterMarker'].every(key => cell[key] == null || typeof cell[key] === 'string');
  };
  if (new Set(t.cells.map(cell => cell?.number)).size !== 100 || !t.cells.every(validCell)) return false;
  const validStep = step => {
    if (!textFields(step, ['id', 'title']) || !['administrative', 'listen', 'transmit', 'receive', 'pause', 'signal', 'receipt'].includes(step.kind)) return false;
    if (!textList(step.expectedMessages)) return false;
    if (step.botMessage != null && typeof step.botMessage !== 'string') return false;
    if (step.authenticationTokens != null && !textList(step.authenticationTokens)) return false;
    if (step.direction != null && !['transmit', 'receive'].includes(step.direction)) return false;
    if (step.bodyGroups != null && (!Number.isInteger(step.bodyGroups) || step.bodyGroups < 0 || step.bodyGroups > 60)) return false;
    return step.kind !== 'pause' || Number.isFinite(step.requiredPauseSeconds) && step.requiredPauseSeconds >= 0 && step.requiredPauseSeconds <= 5940;
  };
  if (!Array.isArray(v.steps) || !v.steps.length || v.steps.length > 200 || !v.steps.every(validStep)) return false;
  const validRadiogram = gram => textFields(gram, ['id', 'number', 'header', 'wireText', 'receipt', 'urgencyCode', 'urgency', 'address', 'originCallsign', 'recipientCallsign']) && ['transmit', 'receive'].includes(gram.direction) && textList(gram.groups) && gram.groups.every(group => group.length === 5);
  if (!Array.isArray(v.radiograms) || !v.radiograms.every(validRadiogram)) return false;
  if (!Array.isArray(v.signals) || !v.signals.every(signal => textFields(signal, ['id', 'group', 'firstPart', 'secondPart', 'receipt']) && ['transmit', 'receive'].includes(signal.direction))) return false;
  if (!Array.isArray(data.attempts) || !data.attempts.every(attempt => textFields(attempt, ['stepID', 'input']) && typeof attempt.correct === 'boolean' && (attempt.errors == null || Number.isFinite(attempt.errors) && attempt.errors >= 0))) return false;
  const accepted = [];
  for (const attempt of data.attempts) {
    const original = v.steps.find(step => step.id === attempt.stepID);
    if (!original) return false;
    if (attempt.correct && attempt.inputMethod === 'service' && waitMinutes(attempt.input) == null) return false;
    if (attempt.correct && attempt.inputMethod !== 'service' && original.authenticationTokens && !validate(attempt.input, resolveStep(original, v, accepted), v).correct) return false;
    if (attempt.correct && ['auth-request-wait', 'auth-counter-wait'].includes(original.id) && waitMinutes(attempt.input) == null) return false;
    accepted.push(attempt);
  }
  if (!Array.isArray(data.events) || !data.events.every(event => textFields(event, ['date', 'kind', 'detail']))) return false;
  const validDecoded = entries => Array.isArray(entries) && entries.every(entry => textFields(entry, ['stepID']) && Array.isArray(entry.groups) && entry.groups.every(group => textFields(group, ['code', 'meaning'])));
  if (data.decodedReceivedCodes != null && !validDecoded(data.decodedReceivedCodes)) return false;
  if (data.pendingReceivedCodes != null && !validDecoded(data.pendingReceivedCodes)) return false;
  if (data.pendingReply != null && (typeof data.pendingReply.text !== 'string' || typeof data.pendingReply.repeating !== 'boolean')) return false;
  if (data.lastBotMessage != null && typeof data.lastBotMessage !== 'string') return false;
  if (data.startsNewTransmission != null && typeof data.startsNewTransmission !== 'boolean') return false;
  if (!Number.isInteger(data.index) || data.index < 0 || data.index > v.steps.length) return false;
  if (data.radiogramRecovery != null) {
    const recovery = data.radiogramRecovery;
    if (!textFields(recovery, ['radiogramID', 'transmission', 'request'])) return false;
    const current = v.steps[data.index];
    const gram = v.radiograms.find(gram => gram.id === recovery.radiogramID);
    if (!current || current.radiogramID !== gram?.id || current.direction !== 'transmit' || !current.bodyGroups) return false;
    const expected = radiogramRecovery(recovery.transmission, gram, v.tdr);
    if (!expected || expected.request !== recovery.request) return false;
  }
  if (!['idle', 'running', 'playing', 'paused', 'completed', 'aborted', 'interrupted'].includes(data.status)) return false;
  return ['elapsed', 'remaining', 'repeats', 'hints'].every(key => Number.isFinite(data[key]) && data[key] >= 0) && textFields(data, ['input', 'draft', 'error', 'notice']);
}

function textFields(value, fields) {
  return value != null && fields.every(key => typeof value[key] === 'string');
}
function textList(value) {
  return Array.isArray(value) && value.every(item => typeof item === 'string');
}
