import React, { useState, useEffect, useRef } from 'react';
import { Play, Square, FastForward, Volume2 } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { audioEngine } from './audio';

const LESSONS = [
  { id: 1, chars: ['Е', 'Л', 'Ж'] },
  { id: 2, chars: ['А', 'С', 'Щ'] },
  { id: 3, chars: ['Т', 'Ц', 'Д'] },
  { id: 4, chars: ['О', 'Р', 'И'] },
  { id: 5, chars: ['Г', 'Ь', 'Ф'] },
  { id: 6, chars: ['Н', 'Й', 'У'] },
  { id: 7, chars: ['Х', 'К', 'Б'] },
  { id: 8, chars: ['П', 'М', 'Ы'] },
  { id: 9, chars: ['З', 'В', 'Ш'] },
  { id: 10, chars: ['Я', 'Ч'] },
  { id: 11, chars: ['Э', 'Ю'] },
  { id: 12, chars: ['1', '2', '3', '4'] },
  { id: 13, chars: ['5', '6', '7', '8'] },
  { id: 14, chars: ['9', '0', '?', '/', '.'] }
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

const MNEMONICS = {
  '.-': 'ай-ДА', '-...': 'БА-ки-те-кут', '.--': 'ви-ДА-ЛА', '--.': 'ГА-РА-жи', '-..': 'ДО-ми-ки', '.': 'есть',
  '...-': 'же-ле-зи-СТО', '--..': 'ЗА-КА-ти-ки', '..': 'И-ди', '.---': 'йес-НА-ПА-РА', '-.-': 'КАК-же-ТАК', '.-..': 'лу-НА-ти-ки',
  '--': 'МА-МА', '-.': 'НО-мер', '---': 'О-КО-ЛО', '.--.': 'пи-ЛА-ПО-ет', '.-.': 'ре-ША-ет', '...': 'си-не-е',
  '-': 'ТАК', '..-': 'у-нес-ЛО', '..-.': 'фи-ли-МОН-чик', '....': 'хи-ми-чи-те', '-.-.': 'ЦА-пли-НА-ши', '---.': 'ЧА-ША-ТО-нет',
  '----': 'ША-РО-ВА-РЫ', '--.-': 'ЩА-ВАМ-не-ША', '-.--': 'Ы-не-НА-ДО', '-..-': 'ТО-мяг-кий-ЗНАК', '..-..': 'э-ле-РО-ни-ки', '..--': 'ю-ли-А-НА', '.-.-': 'я-МАЛ-я-МАЛ',
  '-----': 'НОЛЬ-ТО-О-КО-ЛО', '.----': 'и-ТО-ЛЬКО-О-ДНА', '..---': 'две-не-ХО-РО-ШО', '...--': 'три-те-бе-МА-ЛО',
  '....-': 'че-тве-ри-те-КА', '.....': 'пя-ти-ле-ти-е', '-....': 'ПО-ше-сти-бе-ри', '--...': 'ДА-ДА-се-ме-ри',
  '---..': 'ВО-СЬМО-ГО-и-ди', '----.': 'НО-НА-НО-НА-ми', '-..-.': 'РА-зде-ли-те-КА', '.-.-.-': 'ТОЧ-КА-ТОЧ-КА-ТОЧ-КА', '..--..': 'ВО-ПРО-СИК-ВО-ПРО-СИК'
};

export const Reception = ({ frequency, volume }) => {
  const [lessonIndex, setLessonIndex] = useState(0);
  const [charSpeed, setCharSpeed] = useState(50); // WPM equivalent (approx characters per min)
  const [pauseSpeed, setPauseSpeed] = useState(15); // Gap WPM (Farnsworth)
  
  const [hoverChar, setHoverChar] = useState(null);
  const [playingChar, setPlayingChar] = useState(null);
  const [isRunning, setIsRunning] = useState(false);

  const currentLesson = LESSONS[lessonIndex];

  // Keep Audio Engine sync'd with global settings
  useEffect(() => {
    audioEngine.setFrequency(frequency);
    audioEngine.setVolume(volume);
  }, [frequency, volume]);

  const playSingleChar = async (char) => {
    if (isRunning) return; // Prevent manual play during exercise
    const morsePattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === char);
    if (morsePattern) {
      setPlayingChar(char);
      // Rough WPM conversion from "Signs per minute" (APAK uses 50 as standard)
      const wpm = Math.max(10, charSpeed / 2.5); 
      await audioEngine.playString(morsePattern, wpm);
      setPlayingChar(null);
    }
  };

  const startExercise = async () => {
    if (isRunning) {
      audioEngine.stopAll();
      setIsRunning(false);
      setPlayingChar(null);
      return;
    }

    setIsRunning(true);
    
    // Create sequence: 5 repetitions of each new char in random order, or sequential.
    // The user requested: "5 повторении каждой буквы". Let's do them grouped for initial learning.
    let sequence = [];
    currentLesson.chars.forEach(c => {
      for(let i=0; i<5; i++) sequence.push(c);
      sequence.push(' '); // space between letter groups
    });

    const wpm = Math.max(10, charSpeed / 2.5);
    const gapWpm = Math.max(5, pauseSpeed / 2.5);

    await audioEngine.playSequence(sequence, MORSE_RU, wpm, gapWpm, (char) => {
      setPlayingChar(char);
    });

    setIsRunning(false);
    setPlayingChar(null);
  };

  // Ensure audio stops if component unmounts
  useEffect(() => {
    return () => audioEngine.stopAll();
  }, []);

  return (
    <div className="reception-container">
      <div className="reception-sidebar">
        <div className="control-group">
          <label>УРОК</label>
          <div className="number-stepper">
            <button onClick={() => setLessonIndex(Math.max(0, lessonIndex - 1))}>-</button>
            <span>{currentLesson.id} / 14</span>
            <button onClick={() => setLessonIndex(Math.min(13, lessonIndex + 1))}>+</button>
          </div>
        </div>

        <div className="control-group">
          <label>СКОРОСТЬ ЗНАКА</label>
          <div className="number-stepper">
            <button onClick={() => setCharSpeed(Math.max(20, charSpeed - 5))}>-</button>
            <span>{charSpeed}</span>
            <button onClick={() => setCharSpeed(Math.min(150, charSpeed + 5))}>+</button>
          </div>
        </div>

        <div className="control-group">
          <label>СКОРОСТЬ ПАУЗЫ</label>
          <div className="number-stepper">
            <button onClick={() => setPauseSpeed(Math.max(5, pauseSpeed - 5))}>-</button>
            <span>{pauseSpeed}</span>
            <button onClick={() => setPauseSpeed(Math.min(100, pauseSpeed + 5))}>+</button>
          </div>
        </div>

        <button className={`start-btn ${isRunning ? 'stop' : ''}`} onClick={startExercise}>
          {isRunning ? <><Square size={16} /> СТОП</> : <><Play size={16} /> СТАРТ</>}
        </button>
      </div>

      <div className="reception-main">
        <div className="lesson-header">
          <h2>НОВЫЕ ЗНАКИ</h2>
          <p>Наведите для подсказки, нажмите для прослушивания</p>
        </div>

        <div className="letters-grid">
          {currentLesson.chars.map((char, i) => {
            const pattern = Object.keys(MORSE_RU).find(k => MORSE_RU[k] === char);
            const mnemonic = MNEMONICS[pattern] || pattern;
            
            return (
              <div 
                key={i} 
                className={`letter-card ${playingChar === char ? 'playing' : ''}`}
                onMouseEnter={() => setHoverChar(char)}
                onMouseLeave={() => setHoverChar(null)}
                onClick={() => playSingleChar(char)}
              >
                <div className="char-display">{char}</div>
                <AnimatePresence>
                  {hoverChar === char && !isRunning && (
                    <motion.div 
                      key="mnemonic"
                      initial={{ opacity: 0, y: 10 }} 
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -10 }}
                      className="mnemonic-display"
                    >
                      {mnemonic}
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
