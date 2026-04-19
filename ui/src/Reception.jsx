import React, { useState, useEffect, useRef } from 'react';
import { Play, Square, FastForward, Volume2 } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { audioEngine } from './audio';
import { MORSE_RU, MNEMONICS_RU, MNEMONICS_EN } from './constants';
import { getMorsePattern, getMnemonic } from './utils/morseProvider';
import { Q_LESSON_GROUPS } from './utils/q_codes';

const LESSONS = [
  { id: 1, chars: ['Е', 'Л', 'Ж', 'А'] },
  { id: 2, chars: ['С', 'Щ', 'Т', 'Ц'] },
  { id: 3, chars: ['Д', 'О', 'Р', 'И'] },
  { id: 4, chars: ['Г', 'Ь', 'Ф', 'Н'] },
  { id: 5, chars: ['Й', 'У', 'Х', 'К'] },
  { id: 6, chars: ['Б', 'П', 'М', 'Ы'] },
  { id: 7, chars: ['З', 'В', 'Ю', 'Я'] },
  { id: 8, chars: ['Э', 'Ч', 'Ш'] },
  { id: 9, chars: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'] },
  { id: 10, chars: ['/', '=', '?'] },
  ...Q_LESSON_GROUPS
];

// Use shared constants

const KEYBOARD_LAYOUT = [
  ['Й', 'Ц', 'У', 'К', 'Е', 'Н', 'Г', 'Ш', 'Щ', 'З', 'Х'],
  ['Ф', 'Ы', 'В', 'А', 'П', 'Р', 'О', 'Л', 'Д', 'Ж', 'Э'],
  ['Я', 'Ч', 'С', 'М', 'И', 'Т', 'Ь', 'Б', 'Ю'],
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '/', '=', '?']
];

const UI_STRINGS = {
  RU: {
    lesson: 'УРОК',
    exercise: 'УПРАЖНЕНИЕ',
    groups: 'ГРУПП',
    charSpeed: 'СКОРОСТЬ ЗНАКА',
    ratio: '- / .',
    pause: 'ПАУЗА',
    start: 'СТАРТ',
    stop: 'СТОП',
    title: 'НОВЫЕ ЗНАКИ',
    desc: 'Наведите для подсказки, нажмите для прослушивания',
    ex2Title: 'Нажимайте знаки, которые вы слышали!',
    reportTitle: 'РЕЗУЛЬТАТЫ СЕССИИ',
    noErrors: 'ОШИБОК НЕТ',
    errorsFound: 'ОШИБКИ В СЛЕДУЮЩИХ ЗНАКАХ:',
    closeReport: 'ЗАКРЫТЬ',
    examTitle: 'ТЕКСТ КОНТРОЛЬНОЙ',
    digits: 'ЦИФРЫ',
    symbols: 'ЗНАКИ',
    selectLetters: 'ВЫБРАТЬ БУКВЫ'
  },
  EN: {
    lesson: 'LESSON',
    exercise: 'EXERCISE',
    groups: 'GROUPS',
    charSpeed: 'CHAR SPEED',
    ratio: '- / .',
    pause: 'PAUSE',
    start: 'START',
    stop: 'STOP',
    title: 'LEARN CHARACTERS',
    desc: 'Hover for hint, click to listen',
    ex2Title: 'Press the characters you hear!',
    reportTitle: 'SESSION RESULTS',
    noErrors: 'PERFECT! NO ERRORS',
    errorsFound: 'ERRORS IN FOLLOWING SIGNS:',
    closeReport: 'CLOSE',
    examTitle: 'EXAM TEXT',
    digits: 'DIGITS',
    symbols: 'SIGNS',
    selectLetters: 'SELECT LETTERS'
  }
};

const generateSequence = (activePool, totalCount, exerciseIndex, symbolsPerGroup = 5) => {
  if (!activePool || activePool.length === 0) return [];

  // For Exercises 1 & 2, totalCount might be small. 
  // For Exercise 3 (Groups), totalCount is already groups * 5.

  // 1. Create a balanced pool
  let pool = [];
  while (pool.length < totalCount) {
    const segment = [...activePool].sort(() => Math.random() - 0.5);
    pool.push(...segment);
  }
  pool = pool.slice(0, totalCount);

  // 2. Initial Shuffle (Fisher-Yates)
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }

  // 3. Strict De-duplication (Prevent consecutive repeats)
  if (activePool.length > 1) {
    for (let i = 0; i < pool.length - 1; i++) {
      if (pool[i] === pool[i + 1]) {
        // Find a replacement from elsewhere in the pool
        let found = false;
        for (let k = 0; k < pool.length; k++) {
          if (k === i || k === i + 1) continue;

          const charToMove = pool[i + 1];
          const targetCandidate = pool[k];

          const isCandidateSafeAtIPlus1 = targetCandidate !== pool[i] && (i + 2 >= pool.length || targetCandidate !== pool[i + 2]);
          const isCharSafeAtK = (k === 0 || charToMove !== pool[k - 1]) && (k + 1 >= pool.length || charToMove !== pool[k + 1]);

          if (isCandidateSafeAtIPlus1 && isCharSafeAtK) {
            [pool[i + 1], pool[k]] = [pool[k], pool[i + 1]];
            found = true;
            break;
          }
        }
      }
    }
  }

  // 4. Assemble
  let sequence = [];
  const isExam = exerciseIndex === 3;

  if (isExam) {
    // Standard groups with spaces for Exam mode
    const groupCountTotal = Math.ceil(totalCount / symbolsPerGroup);
    for (let g = 0; g < groupCountTotal; g++) {
      for (let i = 0; i < symbolsPerGroup; i++) {
        const idx = g * symbolsPerGroup + i;
        if (idx < pool.length) sequence.push(pool[idx]);
      }
      if (g < groupCountTotal - 1) sequence.push(' ');
    }
  } else {
    // Continuous stream for Practice and Group training
    sequence = [...pool];
  }
  return sequence;
};

export const Reception = React.memo(({ frequency, volume, lang = 'RU', wpm, setWpm, dashRatio, setDashRatio, pauseFactor, setPauseFactor, customOverrides = {} }) => {
  const [lessonIndex, setLessonIndex] = useState(0);
  const [exerciseIndex, setExerciseIndex] = useState(0); // 0 = Learning (Ex 1), 1 = Practice (Ex 2)
  const [groupCount, setGroupCount] = useState(5);

  useEffect(() => {
    if (exerciseIndex < 2 && manualMode) {
      setManualMode(false);
    }
  }, [exerciseIndex]);

  const currentLesson = LESSONS[lessonIndex];
  const isQCodeLesson = currentLesson && currentLesson.id >= 11;

  // Restriction: Disable Ex 3/4 for Q-codes
  useEffect(() => {
    if (isQCodeLesson && exerciseIndex > 1) {
      setExerciseIndex(1);
    }
  }, [lessonIndex, isQCodeLesson]);

  const [hoverChar, setHoverChar] = useState(null);
  const [playingChar, setPlayingChar] = useState(null);
  const [pulseType, setPulseType] = useState(null); // 'dot', 'dash' or null
  const [isRunning, setIsRunning] = useState(false);

  const [includeDigits, setIncludeDigits] = useState(false);
  const [includeSymbols, setIncludeSymbols] = useState(false);
  const [manualMode, setManualMode] = useState(false);
  const [manualPool, setManualPool] = useState([]);

  // Exercise 2 Interactive State
  const [sessionSequence, setSessionSequence] = useState([]);
  const [currentStep, setCurrentStep] = useState(0);
  const [waitingForInput, setWaitingForInput] = useState(false);
  const [sessionErrors, setSessionErrors] = useState(new Set());
  const [examResult, setExamResult] = useState([]); // Array of characters played during exam
  const [showReport, setShowReport] = useState(false);
  const [selectedChar, setSelectedChar] = useState(null); // The one user clicked
  const [feedbackStatus, setFeedbackStatus] = useState(null); // 'correct' | 'wrong'

  // Refs for stable access in async loops
  const isRunningRef = useRef(false);
  const currentStepRef = useRef(0);
  const sequenceRef = useRef([]);
  const waitingRef = useRef(false);
  const isPlayingRef = useRef(false); // Immediate lock for single char playback

  const lessonChars = currentLesson.chars;

  // Logic for Exercise 3/4 pool: 
  // Base pool is letters up to current lesson.
  // Then we optionally add digits/symbols based on toggles OR if current lesson is 9/10.
  const getBasePool = () => {
    // Lesson 9 (id 9) is index 8: ONLY digits
    if (lessonIndex === 8) return [...LESSONS[8].chars];
    // Lesson 10 (id 10) is index 9: ONLY signs
    if (lessonIndex === 9) return [...LESSONS[9].chars];

    let pool = [];
    const startIdx = isQCodeLesson ? 10 : 0;
    const endIdx = lessonIndex;
    
    for (let i = startIdx; i <= endIdx; i++) {
      if (LESSONS[i]) {
        pool = [...pool, ...LESSONS[i].chars];
      }
    }

    if (includeSymbols && !isQCodeLesson && lessonIndex < 8) {
      pool = [...pool, ...LESSONS[9].chars];
    }
    return Array.from(new Set(pool));
  };

  const studiedPool = manualMode
    ? [...manualPool, ...(includeSymbols ? LESSONS[9].chars : [])]
    : [...getBasePool(), ...(includeSymbols ? LESSONS[9].chars : [])];

  // Keep Audio Engine sync'd with global settings in real-time
  useEffect(() => {
    audioEngine.setFrequency(frequency);
    audioEngine.setVolume(volume);
    audioEngine.setCharWpm(wpm);
    audioEngine.setPauseFactor(pauseFactor);
    audioEngine.setDashRatio(dashRatio);
  }, [frequency, volume, wpm, pauseFactor, dashRatio]);

  // Unified pattern/mnemonic lookup via provider
  const getCharPattern = (char) => getMorsePattern(char, customOverrides);
  const getCharMnemonic = (char) => getMnemonic(char, lang, customOverrides);

  const playSingleCharFiltered = async (char) => {
    // 1. FOR CUSTOM SELECTION: Strict lock (cannot select another until current finished)
    if (manualMode && !isRunning && isPlayingRef.current) return;

    // 2. FOR BROWSING: Allow interrupting previous sound for responsiveness
    if (!manualMode && !isRunning) {
      audioEngine.stopAll();
      setPlayingChar(null);
      setPulseType(null);
    }

    // 3. EXERCISE 4: Block ALL during automated playback
    if (isRunning && exerciseIndex === 3) return;

    // 4. EXERCISE 1-3: Handle Answering
    if (isRunning && exerciseIndex >= 0 && waitingForInput) {
      const activePool = exerciseIndex === 0 ? lessonChars : studiedPool;
      if (activePool.includes(char)) {
        handleUserAnswer(char);
      }
      return;
    }

    // Toggle Manual Pool membership (Custom Selection)
    if (manualMode && !isRunning) {
      setManualPool(prev => {
        const next = new Set(prev);
        if (next.has(char)) next.delete(char);
        else next.add(char);
        return Array.from(next);
      });
    }

    // Audio Feedback / Preview
    const morsePattern = getCharPattern(char);
    if (morsePattern) {
      isPlayingRef.current = true;
      setPlayingChar(char);
      try {
        await audioEngine.playString(morsePattern, null, setPulseType);
      } finally {
        setPlayingChar(null);
        setPulseType(null);
        isPlayingRef.current = false;
      }
    }
  };

  const handleUserAnswer = async (char) => {
    if (!waitingRef.current || !isRunningRef.current) return;

    const target = sequenceRef.current[currentStepRef.current];
    setSelectedChar(char);

    if (char === target) {
      // Correct!
      setFeedbackStatus('correct');
      setWaitingForInput(false);
      waitingRef.current = false;
      setTimeout(() => {
        setFeedbackStatus(null);
        setSelectedChar(null);
        advanceSession();
      }, 600);
    } else {
      // Wrong! 
      setFeedbackStatus('wrong');
      setSessionErrors(prev => new Set(prev).add(target));
      setWaitingForInput(false);
      waitingRef.current = false;

      // Awareness pause so user can see the red feedback
      await new Promise(r => setTimeout(r, 1000));

      // Play 5 times as penalty
      const morsePattern = getCharPattern(target);
      if (morsePattern) {
        setPlayingChar(target);

        // Calculate rhythmic gap for penalty (matches APAK mapping: 2x + 1 dots)
        const dotLen = 6.0 / (wpm || 50);
        const pFactorDots = (pauseFactor * 2.0) + 1.0;
        const penaltyGapMs = dotLen * pFactorDots * 1000;

        for (let i = 0; i < 5; i++) {
          if (!isRunningRef.current) break;
          const playPromise = audioEngine.playString(morsePattern, null, setPulseType);
          await playPromise;
          if (!isRunningRef.current) break;
          await new Promise(r => setTimeout(r, penaltyGapMs));
        }
        setPlayingChar(null);
        setPulseType(null);
        if (!isRunningRef.current) return;

        // Added reset pause after penalty
        await new Promise(r => setTimeout(r, 1000));
        if (!isRunningRef.current) return;
      }
      setFeedbackStatus(null);
      setSelectedChar(null);
      advanceSession();
    }
  };

  const advanceSession = () => {
    const nextStep = currentStepRef.current + 1;
    if (nextStep >= sequenceRef.current.length) {
      finishSession();
    } else {
      setCurrentStep(nextStep);
      currentStepRef.current = nextStep;
      playCurrentTarget();
    }
  };

  const playCurrentTarget = async () => {
    if (!isRunningRef.current) return;

    const target = sequenceRef.current[currentStepRef.current];
    if (target === ' ') {
      // Gap between groups
      await new Promise(r => setTimeout(r, 1000));
      if (!isRunningRef.current) return;
      advanceSession();
      return;
    }

    const morsePattern = getCharPattern(target);
    if (morsePattern) {
      if (exerciseIndex === 0) setPlayingChar(target); // Only highlight in Ex 1
      await audioEngine.playString(morsePattern, null, setPulseType);
      if (!isRunningRef.current) {
        setPlayingChar(null);
        setPulseType(null);
        return;
      }
      setPlayingChar(null);
      setPulseType(null);

      setWaitingForInput(true);
      waitingRef.current = true;
    }
  };

  const finishSession = () => {
    setIsRunning(false);
    isRunningRef.current = false;
    setShowReport(true);
  };

  const startExercise = async () => {
    if (isRunning) {
      audioEngine.stopAll();
      setIsRunning(false);
      isRunningRef.current = false;
      setPlayingChar(null);
      setPulseType(null);
      setWaitingForInput(false);
      waitingRef.current = false;
      setFeedbackStatus(null);
      setSelectedChar(null);
      return;
    }

    if (playingChar) return;

    // Reset session state
    setSessionErrors(new Set());
    setExamResult([]);
    setShowReport(false);

    if (exerciseIndex === 0) {
      // EX 1: Learning Mode
      setIsRunning(true);
      isRunningRef.current = true;
      let sequence = [];
      lessonChars.forEach(c => {
        for (let i = 0; i < 5; i++) sequence.push(c);
        sequence.push(' ');
      });

      await audioEngine.playSequence(sequence, getCharPattern, (char) => {
        setPlayingChar(char);
      }, setPulseType);

      setIsRunning(false);
      isRunningRef.current = false;
      setPlayingChar(null);
      setPulseType(null);
    } else if (exerciseIndex === 3) {
      // EX 4: Exam Mode (Paper-based)
      const totalCount = groupCount * 5;
      const freshSequence = generateSequence(studiedPool, totalCount, exerciseIndex, 5);

      console.log('[Reception] Starting Exam Sequence:', freshSequence);
      setExamResult(freshSequence);
      setIsRunning(true);
      isRunningRef.current = true;

      try {
        await audioEngine.playSequence(freshSequence, getCharPattern, null, null);
      } catch (err) {
        console.error('[Reception] Playback Error:', err);
      }

      setIsRunning(false);
      isRunningRef.current = false;
      setPlayingChar(null);
      setPulseType(null);
      setShowReport(true);
    } else {
      // EX 2 & 3: Interactive Practice
      const activePool = exerciseIndex === 1 ? lessonChars : studiedPool;
      const totalCount = exerciseIndex === 2 ? groupCount * 5 : 15;
      const sequence = generateSequence(activePool, totalCount, exerciseIndex, 5);

      setSessionSequence(sequence);
      sequenceRef.current = sequence;
      setCurrentStep(0);
      currentStepRef.current = 0;
      setIsRunning(true);
      isRunningRef.current = true;

      playCurrentTarget();
    }
  };

  // Ensure audio stops if component unmounts
  useEffect(() => {
    return () => audioEngine.stopAll();
  }, []);

  const ui = UI_STRINGS[lang] || UI_STRINGS.RU;
  const mnemonics = lang === 'RU' ? MNEMONICS_RU : MNEMONICS_EN;

  // Determine what to show in the header
  const activeChar = playingChar || hoverChar;

  // Base labels (Defaults for the current exercise)
  let headerTitle = exerciseIndex === 0 ? ui.title : (exerciseIndex === 3 ? ui.examTitle : ui.ex2Title);
  let headerDesc = ui.desc;

  // Use the same logic for both exercises: if a char is active, show its info.
  if (activeChar && (!isRunning || (exerciseIndex < 3 && exerciseIndex >= 0))) {
    headerTitle = activeChar;
    headerDesc = getCharMnemonic(activeChar);
  }

  return (
    <div className="reception-container">
      <div className="reception-sidebar">
        <button
          className={`toggle-btn main-select ${manualMode ? 'active' : ''}`}
          onClick={() => setManualMode(!manualMode)}
          style={{
            marginBottom: '12px',
            padding: '12px 0',
            opacity: exerciseIndex < 2 ? 0.3 : 1,
            pointerEvents: 'auto',
            cursor: exerciseIndex < 2 ? 'not-allowed' : 'pointer'
          }}
          title={exerciseIndex < 2 ? (lang === 'RU' ? 'Доступно в 3 и 4 упражнении' : 'Available in Exercises 3 & 4') : ''}
          disabled={exerciseIndex < 2}
        >
          {ui.selectLetters}
        </button>

        <div className="control-group"
          style={{
            opacity: manualMode ? 0.3 : 1,
            pointerEvents: 'auto',
            cursor: manualMode ? 'not-allowed' : 'default'
          }}
        >
          <label title={manualMode ? (lang === 'RU' ? 'Доступно в обычном режиме' : 'Available in standard mode') : ''}>{ui.lesson}</label>
          <div className="number-stepper">
            <button
              disabled={isRunning || playingChar || manualMode}
              title={manualMode ? (lang === 'RU' ? 'Доступно в обычном режиме' : 'Available in standard mode') : ''}
              onClick={() => setLessonIndex(Math.max(0, lessonIndex - 1))}
            >-</button>
            <span title={manualMode ? (lang === 'RU' ? 'Доступно в обычном режиме' : 'Available in standard mode') : ''}>{currentLesson.id}</span>
            <button
              disabled={isRunning || playingChar || manualMode}
              title={manualMode ? (lang === 'RU' ? 'Доступно в обычном режиме' : 'Available in standard mode') : ''}
              onClick={() => setLessonIndex(Math.min(LESSONS.length - 1, lessonIndex + 1))}
            >+</button>
          </div>
        </div>

        <div className="control-group">
          <label>{ui.exercise}</label>
          <div className="number-stepper">
            <button
              disabled={isRunning || playingChar}
              onClick={() => setExerciseIndex(Math.max(0, exerciseIndex - 1))}
            >-</button>
            <span style={{ color: isQCodeLesson && exerciseIndex > 1 ? 'rgba(255,255,255,0.2)' : 'inherit' }}>
              {exerciseIndex + 1}
            </span>
            <button
              disabled={isRunning || playingChar || (isQCodeLesson && exerciseIndex >= 1)}
              onClick={() => setExerciseIndex(Math.min(3, exerciseIndex + 1))}
            >+</button>
          </div>
          {isQCodeLesson && <div style={{ fontSize: '10px', opacity: 0.5, textAlign: 'center', marginTop: '4px' }}>{lang === 'RU' ? 'НЕДОСТУПНО ДЛЯ Щ-КОДОВ' : 'N/A FOR Q-CODES'}</div>}
        </div>



        <div className="control-group" style={{
          opacity: exerciseIndex < 2 ? 0.3 : 1,
          pointerEvents: 'auto',
          cursor: exerciseIndex < 2 ? 'not-allowed' : 'default'
        }}>
          <label>{ui.groups}</label>
          <div className="number-stepper">
            <button
              disabled={isRunning || playingChar || exerciseIndex < 2}
              title={exerciseIndex < 2 ? (lang === 'RU' ? 'Доступно в 3 и 4 упражнении' : 'Available in Exercises 3 & 4') : ''}
              onClick={() => setGroupCount(Math.max(5, groupCount - 5))}
            >-</button>
            <span title={exerciseIndex < 2 ? (lang === 'RU' ? 'Доступно в 3 и 4 упражнении' : 'Available in Exercises 3 & 4') : ''}>{groupCount}</span>
            <button
              disabled={isRunning || playingChar || exerciseIndex < 2}
              title={exerciseIndex < 2 ? (lang === 'RU' ? 'Доступно в 3 и 4 упражнении' : 'Available in Exercises 3 & 4') : ''}
              onClick={() => setGroupCount(Math.min(100, groupCount + 5))}
            >+</button>
          </div>
        </div>



        <div className="sidebar-separator"></div>

        <div className="control-group">
          <label>{ui.charSpeed}</label>
          <div className="number-stepper">
            <button onClick={() => setWpm(Math.max(20, wpm - 5))}>-</button>
            <span>{wpm}</span>
            <button onClick={() => setWpm(Math.min(250, wpm + 5))}>+</button>
          </div>
        </div>

        <div className="control-group">
          <label>{ui.ratio}</label>
          <div className="number-stepper">
            <button onClick={() => setDashRatio(Math.max(2.0, parseFloat((dashRatio - 0.5).toFixed(1))))}>-</button>
            <span>{dashRatio.toFixed(1)}</span>
            <button onClick={() => setDashRatio(Math.min(5.0, parseFloat((dashRatio + 0.5).toFixed(1))))}>+</button>
          </div>
        </div>

        <div className="control-group">
          <label>{ui.pause}</label>
          <div className="number-stepper">
            <button onClick={() => setPauseFactor(Math.max(1.0, parseFloat((pauseFactor - 0.5).toFixed(1))))}>-</button>
            <span>x{pauseFactor.toFixed(1)}</span>
            <button onClick={() => setPauseFactor(Math.min(10.0, parseFloat((pauseFactor + 0.5).toFixed(1))))}>+</button>
          </div>
        </div>

        <div className="control-group" style={{
          opacity: exerciseIndex < 2 ? 0.3 : 1,
          pointerEvents: 'auto',
          cursor: exerciseIndex < 2 ? 'not-allowed' : 'default',
          marginTop: '6px',
          marginBottom: '16px'
        }}>
          <button
            className={`toggle-btn ${includeSymbols ? 'active' : ''}`}
            onClick={() => { if (exerciseIndex < 2) return; setIncludeSymbols(!includeSymbols); }}
            disabled={exerciseIndex < 2}
            style={{
              opacity: exerciseIndex < 2 ? 0.3 : 1,
              pointerEvents: 'auto',
              cursor: exerciseIndex < 2 ? 'not-allowed' : 'pointer'
            }}
            title={exerciseIndex < 2 ? (lang === 'RU' ? 'Доступно в 3 и 4 упражнении' : 'Available in Exercises 3 & 4') : ''}
          >
            {ui.symbols}
          </button>
        </div>

        <button
          className={`start-btn ${isRunning ? 'stop' : ''}`}
          onClick={startExercise}
          disabled={!isRunning && playingChar}
        >
          {isRunning ? <><Square size={16} /> {ui.stop}</> : <><Play size={16} /> {ui.start}</>}
        </button>
      </div>

      <div className="reception-main">
        <div className="lesson-header">
          <motion.h2
            key={headerTitle}
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.1 }}
          >
            {headerTitle}
          </motion.h2>
          <motion.p
            key={headerDesc}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.2 }}
          >
            {headerDesc}
          </motion.p>
        </div>

        {exerciseIndex < 2 ? (
          <div
            className={`letters-grid ${isQCodeLesson ? 'q-codes-layout' : ''} ${(playingChar || feedbackStatus || (isRunning && (exerciseIndex === 3 || !waitingForInput))) ? 'disabled' : ''}`}
            onMouseLeave={() => setHoverChar(null)}
          >
            {(exerciseIndex < 2 ? lessonChars : studiedPool).map((char, i) => {
              const isTarget = playingChar === char;
              return (
                <div
                  key={char}
                  className={`letter-card ${isTarget ? 'playing' : ''} ${pulseType && isTarget ? 'pulse-' + pulseType : ''} ${((isRunning && exerciseIndex === 0 || playingChar) && playingChar !== char) ? 'locked' : ''} ${waitingForInput ? 'waiting' : ''} ${selectedChar === char ? feedbackStatus : ''} ${manualMode && manualPool.includes(char) ? 'manual-selected' : ''}`}
                  onMouseEnter={() => setHoverChar(char)}
                  onClick={() => playSingleCharFiltered(char)}
                >
                  <div className="char-display">{char}</div>
                </div>
              );
            })}
          </div>
        ) : (
          <div className={`keyboard-container ${(playingChar || feedbackStatus || (isRunning && (exerciseIndex === 3 || !waitingForInput))) ? 'disabled' : ''}`}>
            {KEYBOARD_LAYOUT.map((row, rowIndex) => (
              <div key={rowIndex} className="keyboard-row">
                {row.map((char, i) => {
                  const isEligible = studiedPool.includes(char);
                  const isTarget = playingChar === char;
                  const isLocked = isRunning && (exerciseIndex === 3 || !isEligible);
                  const isDimmed = isRunning && !isEligible && exerciseIndex !== 3;

                  return (
                    <div
                      key={char}
                      className={`keyboard-key ${isEligible ? 'eligible' : 'ineligible'} ${isTarget ? 'playing' : ''} ${pulseType && isTarget ? 'pulse-' + pulseType : ''} ${isLocked ? 'locked' : ''} ${isDimmed ? 'dimmed' : ''} ${waitingForInput && isEligible ? 'waiting' : ''} ${selectedChar === char ? feedbackStatus : ''}`}
                      onMouseEnter={() => setHoverChar(char)}
                      onMouseLeave={() => setHoverChar(null)}
                      onClick={() => playSingleCharFiltered(char)}
                    >
                      <div className="char-display">{char}</div>
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        )}
      </div>

      <AnimatePresence>
        {showReport && (
          <motion.div
            className="report-overlay"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <motion.div
              className={`report-card glass-panel ${exerciseIndex === 3 ? 'exam-report' : ''}`}
              initial={{ scale: 0.9, y: 20 }}
              animate={{ scale: 1, y: 0 }}
            >
              <h3>{exerciseIndex === 3 ? ui.examTitle : ui.reportTitle}</h3>              <div className="report-content">
                {exerciseIndex === 3 ? (
                  <div className="exam-result-container">
                    {(() => {
                      const groups = examResult.join('').split(' ');
                      const rows = [];
                      for (let i = 0; i < groups.length; i += 5) {
                        rows.push(groups.slice(i, i + 5));
                      }
                      return rows.map((row, rowIdx) => (
                        <div key={rowIdx} className="exam-result-row">
                          {row.map((group, gIdx) => (
                            <div key={gIdx} className="exam-group-wrapper">
                              <span className="group-number">{rowIdx * 5 + gIdx + 1}</span>
                              <span className="exam-group">{group}</span>
                            </div>
                          ))}
                        </div>
                      ));
                    })()}
                  </div>
                ) : (
                  sessionErrors.size === 0 ? (
                    <p className="success-msg">{ui.noErrors}</p>
                  ) : (
                    <>
                      <p>{ui.errorsFound}</p>
                      <div className="error-list">
                        {Array.from(sessionErrors).map(err => (
                          <div key={err} className="error-item">{err}</div>
                        ))}
                      </div>
                    </>
                  )
                )}
              </div>
              <button className="start-btn" onClick={() => setShowReport(false)}>{ui.closeReport}</button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
});
