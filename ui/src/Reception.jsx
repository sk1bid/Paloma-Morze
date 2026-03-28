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
  { id: 7, chars: ['З', 'В', 'Ч', 'Ш'] },
  { id: 8, chars: ['Э', 'Ю', 'Я'] },
  { id: 9, chars: ['1', '2', '3', '4'] },
  { id: 10, chars: ['5', '6', '7', '8'] },
  { id: 11, chars: ['9', '0', '/', '.'] },
  { id: 12, chars: ['?'] }
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

const UI_STRINGS = {
  RU: { lesson: 'УРОК', charSpeed: 'СКОРОСТЬ ЗНАКА', pauseSpeed: 'СКОРОСТЬ ПАУЗЫ', start: 'СТАРТ', stop: 'СТОП', title: 'НОВЫЕ ЗНАКИ', desc: 'Наведите для подсказки, нажмите для прослушивания' },
  EN: { lesson: 'LESSON', charSpeed: 'CHAR SPEED', pauseSpeed: 'GAP SPEED', start: 'START', stop: 'STOP', title: 'LEARN CHARACTERS', desc: 'Hover for hint, click to listen' }
};

export const Reception = React.memo(({ frequency, volume, lang = 'RU' }) => {
  const [lessonIndex, setLessonIndex] = useState(0);
  const [charSpeed, setCharSpeed] = useState(50); // Signs Per Minute (APAK standard)
  const [pauseSpeed, setPauseSpeed] = useState(15); // Gap SPM
  
  const [hoverChar, setHoverChar] = useState(null);
  const [playingChar, setPlayingChar] = useState(null);
  const [pulseType, setPulseType] = useState(null); // 'dot', 'dash' or null
  const [isRunning, setIsRunning] = useState(false);

  const currentLesson = LESSONS[lessonIndex];

  // Keep Audio Engine sync'd with global settings in real-time
  useEffect(() => {
    audioEngine.setFrequency(frequency);
    audioEngine.setVolume(volume);
    audioEngine.setCharWpm(Math.max(5, charSpeed / 5));
    audioEngine.setGapWpm(Math.max(3, pauseSpeed / 5));
  }, [frequency, volume, charSpeed, pauseSpeed]);

  const playSingleChar = async (char) => {
    if (isRunning || (playingChar && playingChar !== char)) return; 
    const morsePattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === char);
    if (morsePattern) {
      setPlayingChar(char);
      await audioEngine.playString(morsePattern, setPulseType);
      setPlayingChar(null);
      setPulseType(null);
    }
  };

  const startExercise = async () => {
    if (isRunning) {
      audioEngine.stopAll();
      setIsRunning(false);
      setPlayingChar(null);
      setPulseType(null);
      return;
    }

    if (playingChar) return; 

    setIsRunning(true);
    
    // Create sequence: 5 repetitions of each new char in grouped order.
    let sequence = [];
    currentLesson.chars.forEach(c => {
      for(let i=0; i<5; i++) sequence.push(c);
      sequence.push(' '); // space between letter groups
    });

    await audioEngine.playSequence(sequence, MORSE_RU, (char) => {
      setPlayingChar(char);
    }, setPulseType);

    setIsRunning(false);
    setPlayingChar(null);
    setPulseType(null);
  };

  // Ensure audio stops if component unmounts
  useEffect(() => {
    return () => audioEngine.stopAll();
  }, []);

  const ui = UI_STRINGS[lang] || UI_STRINGS.RU;
  const mnemonics = lang === 'RU' ? MNEMONICS_RU : MNEMONICS_EN;

  // Determine what to show in the header
  const activeChar = playingChar || hoverChar;
  let headerTitle = ui.title;
  let headerDesc = ui.desc;

  if (activeChar) {
    const pattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === activeChar);
    headerTitle = activeChar;
    headerDesc = mnemonics[pattern] || '';
  }

  return (
    <div className="reception-container">
      <div className="reception-sidebar">
        <div className="control-group">
          <label>{ui.lesson}</label>
          <div className="number-stepper">
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setLessonIndex(Math.max(0, lessonIndex - 1))}
            >-</button>
            <span>{currentLesson.id} / 12</span>
            <button 
              disabled={isRunning || playingChar}
              onClick={() => setLessonIndex(Math.min(11, lessonIndex + 1))}
            >+</button>
          </div>
        </div>

        <div className="control-group">
          <label>{ui.charSpeed}</label>
          <div className="number-stepper">
            <button onClick={() => setCharSpeed(Math.max(20, charSpeed - 5))}>-</button>
            <span>{charSpeed}</span>
            <button onClick={() => setCharSpeed(Math.min(150, charSpeed + 5))}>+</button>
          </div>
        </div>

        <div className="control-group">
          <label>{ui.pauseSpeed}</label>
          <div className="number-stepper">
            <button onClick={() => setPauseSpeed(Math.max(5, pauseSpeed - 5))}>-</button>
            <span>{pauseSpeed}</span>
            <button onClick={() => setPauseSpeed(Math.min(100, pauseSpeed + 5))}>+</button>
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

        <div 
          className={`letters-grid ${(isRunning || playingChar) ? 'disabled' : ''}`}
          onMouseLeave={() => setHoverChar(null)}
        >
          {currentLesson.chars.map((char, i) => {
            return (
              <div 
                key={i} 
                className={`letter-card ${playingChar === char ? 'playing' : ''} ${pulseType && playingChar === char ? 'pulse-' + pulseType : ''} ${((isRunning || playingChar) && playingChar !== char) ? 'locked' : ''}`}
                onMouseEnter={() => setHoverChar(char)}
                onClick={() => playSingleChar(char)}
              >
                <div className="char-display">{char}</div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
});
