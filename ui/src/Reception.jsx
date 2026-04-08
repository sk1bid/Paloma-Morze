import React, { useState, useEffect, useRef } from 'react';
import { Play, Square, FastForward, Volume2 } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { audioEngine } from './audio';

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
  { id: 10, chars: ['/', '.', '?'] }
];

const MORSE_RU = {
  '.-': 'А', '-...': 'Б', '.--': 'В', '--.': 'Г', '-..': 'Д', '.': 'Е',
  '...-': 'Ж', '--..': 'З', '..': 'И', '.---': 'Й', '-.-': 'К', '.-..': 'Л',
  '--': 'М', '-.': 'Н', '---': 'О', '.--.': 'П', '.-.': 'Р', '...': 'С',
  '-': 'Т', '..-': 'У', '..-.': 'Ф', '....': 'Х', '-.-.': 'Ц', '---.': 'Ч',
  '----': 'Ш', '--.-': 'Щ', '-.--': 'Ы', '-..-': 'Ь', '..-..': 'Э', '..--': 'Ю', '.-.-': 'Я',
  '-----': '0', '.----': '1', '..---': '2', '...--': '3', '....-': '4', '.....': '5',
  '-....': '6', '--...': '7', '---..': '8', '----.': '9', '-..-.': '/', '.-.-.-': '.', '..--..': '?'
};

const MNEMONICS_RU = {
  '.-': 'ай-ДА', '-...': 'БА-ки-те-кут', '.--': 'ви-ДА-ЛА', '--.': 'ГА-РА-жи', '-..': 'ДО-ми-ки', '.': 'есть',
  '...-': 'же-ле-зи-СТО', '--..': 'ЗА-КА-ти-ки', '..': 'и-ди', '.---': 'йес-НА-ПА-РА', '-.-': 'КАК-же-ТАК', '.-..': 'лу-НА-ти-ки',
  '--': 'МА-МА', '-.': 'НО-мер', '---': 'О-КО-ЛО', '.--.': 'пи-ЛА-ПО-ет', '.-.': 'ре-ША-ет', '...': 'си-не-е',
  '-': 'ТАК', '..-': 'у-нес-ЛО', '..-.': 'фи-ли-МОН-чик', '....': 'хи-ми-чи-те', '-.-.': 'ЦА-пли-НА-ши', '---.': 'ЧА-ША-ТО-нет',
  '----': 'ША-РО-ВА-РЫ', '--.-': 'ЩА-ВАМ-не-ША', '-.--': 'Ы-не-НА-ДО', '-..-': 'ТО-мяг-кий-ЗНАК', '..-..': 'э-ле-РО-ни-ки', '..--': 'ю-ли-А-НА', '.-.-': 'я-МАЛ-я-МАЛ',
  '-----': 'НОЛЬ-ТО-О-КО-ЛО', '.----': 'и-ТО-ЛЬКО-О-ДНА', '..---': 'две-не-ХО-РО-ШО', '...--': 'три-те-бе-МА-ЛО',
  '....-': 'че-тве-ри-те-КА', '.....': 'пя-ти-ле-ти-е', '-....': 'ПО-ше-сти-бе-ри', '--...': 'ДА-ДА-се-ме-ри',
  '---..': 'ВО-СЬМО-ГО-и-ди', '----.': 'НО-НА-НО-НА-ми', '-..-.': 'РА-зде-ли-те-КА', '.-.-.-': 'ТОЧ-КА-ТОЧ-КА-ТОЧ-КА', '..--..': 'ВО-ПРО-СИК-ВО-ПРО-СИК'
};

const MNEMONICS_EN = {
  '.-': 'a-PART', '-...': 'BOB-is-the-man', '-.-.': 'CO-ca-CO-la', '-..': 'DOG-did-it', '.': 'egg', '..-.': 'fetch-a-FI-re',
  '--.': 'GO-GO-dance', '....': 'hi-ppo-po-tmus', '..': 'i-nit', '.---': 'in-JA-PON-GOL', '-.-': 'KANG-ga-ROO', '.-..': 'l-A-po-p-o',
  '--': 'MA-MA', '-.': 'NO-el', '---': 'ONE-OF-US', '.--.': 'a-PU-PPY-poo', '--.-': 'GOD-SAVE-the-QUEEN', '.-.': 'ro-TAY-tor',
  '...': 'si-si-si', '-': 'TALL', '..-': 'un-der-WHERE', '...-': 'vic-to-ry-VEE', '.--': 'a-WET-DOG', '-..-': 'X-marks-the-SPOT',
  '-.--': 'YELL-ow-YOYO', '--..': 'ZEN-dra-is-HERE', '-----': 'NO-ONE-GO-ES-HOME', '.----': 'a-LONG-WHI-TE-BEA-RD', '..---': 'and-not-GO-OD-for-US', '...--': 'it-is-not-for-ME',
  '....-': 'and-the-dogs-are-HERE', '.....': 'i-ti-bi-ti-hi', '-....': 'SIX-dogs-are-run-ning', '--...': 'SE-VEN-is-high-up-HERE',
  '---..': 'EIGHT-TEN-is-not-E-NOUGH', '----.': 'NINE-NINE-is-not-for-US', '.-.-.-': 'STOP', '..--..': 'QUERY'
};

const KEYBOARD_LAYOUT = [
  ['Й', 'Ц', 'У', 'К', 'Е', 'Н', 'Г', 'Ш', 'Щ', 'З', 'Х'],
  ['Ф', 'Ы', 'В', 'А', 'П', 'Р', 'О', 'Л', 'Д', 'Ж', 'Э'],
  ['Я', 'Ч', 'С', 'М', 'И', 'Т', 'Ь', 'Б', 'Ю'],
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '/', '.', '?']
];

const UI_STRINGS = {
  RU: { 
    lesson: 'УРОК', 
    exercise: 'УПРАЖНЕНИЕ',
    groups: 'ГРУПП',
    charSpeed: 'ЗНАКОВ/МИН', 
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
    symbols: 'СИМВОЛЫ',
    selectLetters: 'ВЫБРАТЬ БУКВЫ'
  },
  EN: { 
    lesson: 'LESSON', 
    exercise: 'EXERCISE',
    groups: 'GROUPS',
    charSpeed: 'CPM (SPEED)', 
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
    symbols: 'SYMBOLS',
    selectLetters: 'SELECT LETTERS'
  }
};

const generateSequence = (activePool, totalCount, symbolsPerGroup = 5) => {
  if (!activePool || activePool.length === 0) return [];
  
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

  // 4. Assemble with groups
  let sequence = [];
  const groupCountTotal = Math.ceil(totalCount / symbolsPerGroup);
  for (let g = 0; g < groupCountTotal; g++) {
    for (let i = 0; i < symbolsPerGroup; i++) {
      const idx = g * symbolsPerGroup + i;
      if (idx < pool.length) sequence.push(pool[idx]);
    }
    if (g < groupCountTotal - 1) sequence.push(' ');
  }
  return sequence;
};

export const Reception = React.memo(({ frequency, volume, lang = 'RU', wpm, setWpm, dashRatio, setDashRatio, pauseFactor, setPauseFactor }) => {
  const [lessonIndex, setLessonIndex] = useState(0);
  const [exerciseIndex, setExerciseIndex] = useState(0); // 0 = Learning (Ex 1), 1 = Practice (Ex 2)
  const [groupCount, setGroupCount] = useState(5);
  
  // Auto-disable manualMode (and clear selection if needed) 
  // when switching to exercises that don't support it (Ex 1 & 2)
  useEffect(() => {
    if (exerciseIndex < 2 && manualMode) {
      setManualMode(false);
    }
  }, [exerciseIndex]);

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
 
  const currentLesson = LESSONS[lessonIndex];
  const lessonChars = currentLesson.chars;
  
  // Logic for Exercise 3/4 pool: 
  // Base pool is letters up to current lesson.
  // Then we optionally add digits/symbols based on toggles OR if current lesson is 9/10.
  const getBasePool = () => {
    let pool = LESSONS.slice(0, Math.min(8, lessonIndex + 1)).flatMap(l => l.chars);
    if (lessonIndex === 8) pool = LESSONS[8].chars; // Digits lesson
    if (lessonIndex === 9) pool = LESSONS[9].chars; // Symbols lesson
    
    if (includeSymbols && lessonIndex < 9) {
      pool = [...pool, ...LESSONS[9].chars];
    }
    return Array.from(new Set(pool));
  };
  
  const studiedPool = manualMode ? [...manualPool, ...(includeSymbols ? LESSONS[9].chars : [])] : getBasePool();
 
  // Keep Audio Engine sync'd with global settings in real-time
  useEffect(() => {
    audioEngine.setFrequency(frequency);
    audioEngine.setVolume(volume);
    audioEngine.setCharWpm(wpm);
    audioEngine.setGapWpm(wpm / pauseFactor); 
    audioEngine.setDashRatio(dashRatio);
  }, [frequency, volume, wpm, pauseFactor, dashRatio]);

  const playSingleCharFiltered = async (char) => {
    // If exercise is running and it's Exercise 4, we block all keyboard interaction
    if (isRunning && exerciseIndex === 3) return;

    // If exercise is running and we're looking for input, clicking is "answering"
    if (isRunning && exerciseIndex >= 1 && waitingForInput) {
      // In Ex 2/3, we only respond to characters in the active pool
      const activePool = exerciseIndex === 1 ? lessonChars : studiedPool;
      if (activePool.includes(char)) {
        handleUserAnswer(char);
      }
      return;
    }

    // Handle Manual Selection Toggling
    if (manualMode && !isRunning) {
      setManualPool(prev => {
        const next = new Set(prev);
        if (next.has(char)) next.delete(char);
        else next.add(char);
        return Array.from(next);
      });
      // Also play sound for feedback
    }

    // Preview Mode (when not running or not waiting for input)
    if (playingChar) return; 
    const morsePattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === char);
    if (morsePattern) {
      setPlayingChar(char);
      await audioEngine.playString(morsePattern, null, setPulseType);
      setPlayingChar(null);
      setPulseType(null);
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
      const morsePattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === target);
      if (morsePattern) {
        setPlayingChar(target);
        
        // Calculate rhythmic gap for penalty (3 dots * pauseFactor)
        const dotLen = 6.0 / (wpm || 50);
        const penaltyGapMs = dotLen * 3 * (pauseFactor || 1.0) * 1000;

        for (let i = 0; i < 5; i++) {
          if (!isRunningRef.current) break;
          const playPromise = audioEngine.playString(morsePattern, null, setPulseType);
          await playPromise;
          await new Promise(r => setTimeout(r, penaltyGapMs));
        }
        setPlayingChar(null);
        setPulseType(null);
        // Added reset pause after penalty
        await new Promise(r => setTimeout(r, 1000));
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
      advanceSession();
      return;
    }

    const morsePattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === target);
    if (morsePattern) {
      if (exerciseIndex === 0) setPlayingChar(target); // Only highlight in Ex 1
      await audioEngine.playString(morsePattern, null, setPulseType);
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
        for(let i=0; i<5; i++) sequence.push(c);
        sequence.push(' '); 
      });

      await audioEngine.playSequence(sequence, MORSE_RU, (char) => {
        setPlayingChar(char);
      }, setPulseType);

      setIsRunning(false);
      isRunningRef.current = false;
      setPlayingChar(null);
      setPulseType(null);
    } else if (exerciseIndex === 3) {
      // EX 4: Exam Mode (Paper-based)
      const totalCount = groupCount * 5; 
      const freshSequence = generateSequence(studiedPool, totalCount, 5);

      console.log('[Reception] Starting Exam Sequence:', freshSequence);
      setExamResult(freshSequence);
      setIsRunning(true);
      isRunningRef.current = true;

      try {
        await audioEngine.playSequence(freshSequence, MORSE_RU, null, null);
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
      const sequence = generateSequence(activePool, totalCount, 5);

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
    const pattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === activeChar);
    headerTitle = activeChar;
    headerDesc = mnemonics[pattern] || '';
  }

  return (
    <div className="reception-container">
      <div className="reception-sidebar">
        {exerciseIndex >= 2 && (
          <button 
            className={`toggle-btn main-select ${manualMode ? 'active' : ''}`}
            onClick={() => setManualMode(!manualMode)}
            style={{ marginBottom: '12px', padding: '12px 0' }}
          >
            {ui.selectLetters}
          </button>
        )}

        <div className="control-group" style={{ display: manualMode ? 'none' : 'flex' }}>
          <label>{ui.lesson}</label>
          <div className="number-stepper">
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setLessonIndex(Math.max(0, lessonIndex - 1))}
            >-</button>
            <span>{currentLesson.id}</span>
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setLessonIndex(Math.min(9, lessonIndex + 1))}
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
            <span>{exerciseIndex + 1}</span>
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setExerciseIndex(Math.min(3, exerciseIndex + 1))}
            >+</button>
          </div>
        </div>

        {(exerciseIndex === 2 || exerciseIndex === 3) && (
          <div className="toggle-row">
            <button className={`toggle-btn ${includeSymbols ? 'active' : ''}`} onClick={() => setIncludeSymbols(!includeSymbols)}>
              {ui.symbols}
            </button>
          </div>
        )}

        {(exerciseIndex === 2 || exerciseIndex === 3) && (
        <div className="control-group">
          <label>{ui.groups}</label>
          <div className="number-stepper">
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setGroupCount(Math.max(5, groupCount - 5))}
            >-</button>
            <span>{groupCount}</span>
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setGroupCount(Math.min(100, groupCount + 5))}
            >+</button>
          </div>
        </div>
        )}

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
            className={`letters-grid ${(playingChar || feedbackStatus || (isRunning && (exerciseIndex === 3 || !waitingForInput))) ? 'disabled' : ''}`}
            onMouseLeave={() => setHoverChar(null)}
          >
            {lessonChars.map((char, i) => {
              const isTarget = playingChar === char;
              return (
                <div 
                  key={i} 
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
                      key={i} 
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
              className="report-card glass-panel"
              initial={{ scale: 0.9, y: 20 }}
              animate={{ scale: 1, y: 0 }}
            >
              <h3>{exerciseIndex === 3 ? ui.examTitle : ui.reportTitle}</h3>
              <div className="report-content">
                {exerciseIndex === 3 ? (
                  <div className="exam-result-text">
                    {examResult.join('').split(' ').map((group, idx) => (
                      <span key={idx} className="exam-group">{group}</span>
                    ))}
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
