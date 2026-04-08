import React, { useState, useEffect, useRef } from 'react';
import { Terminal, Zap, History, Speaker, Settings, Info } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import './App.css';

const MORSE_EN = {
  '.-': 'A', '-...': 'B', '-.-.': 'C', '-..': 'D', '.': 'E', '..-.': 'F',
  '--.': 'G', '....': 'H', '..': 'I', '.---': 'J', '-.-': 'K', '.-..': 'L',
  '--': 'M', '-.': 'N', '---': 'O', '.--.': 'P', '--.-': 'Q', '.-.': 'R',
  '...': 'S', '-': 'T', '..-': 'U', '...-': 'V', '.--': 'W', '-..-': 'X',
  '-.--': 'Y', '--..': 'Z', '-----': '0', '.----': '1', '..---': '2',
  '...--': '3', '....-': '4', '.....': '5', '-....': '6', '--...': '7',
  '---..': '8', '----.': '9', '----': '0', '.-.-': 'AR'
};

const MORSE_RU = {
  '.-': 'А', '-...': 'Б', '.--': 'В', '--.': 'Г', '-..': 'Д', '.': 'Е',
  '...-': 'Ж', '--..': 'З', '..': 'И', '.---': 'Й', '-.-': 'К', '.-..': 'Л',
  '--': 'М', '-.': 'Н', '---': 'О', '.--.': 'П', '.-.': 'Р', '...': 'С',
  '-': 'Т', '..-': 'У', '..-.': 'Ф', '....': 'Х', '-.-.': 'Ц', '---.': 'Ч',
  '----': 'Ш', '--.-': 'Щ', '-.--': 'Ы', '-..-': 'Ь', '..-..': 'Э', '..--': 'Ю', '.-.-': 'Я',
  '-----': '0', '.----': '1', '..---': '2', '...--': '3', '....-': '4', '.....': '5',
  '-....': '6', '--...': '7', '---..': '8', '----.': '9', '-..-.': '/'
};

const MNEMONICS = {
  '.-': 'ай-ДА', '-...': 'БА-ки-те-кут', '.--': 'ви-ДА-ЛА', '--.': 'ГА-РА-жи', '-..': 'ДО-ми-ки', '.': 'есть',
  '...-': 'же-ле-зи-СТО', '--..': 'ЗА-КА-ти-ки', '..': 'И-ди', '.---': 'йес-НА-ПА-РА', '-.-': 'КАК-же-ТАК', '.-..': 'лу-НА-ти-ки',
  '--': 'МА-МА', '-.': 'НО-мер', '---': 'О-КО-ЛО', '.--.': 'пи-ЛА-ПО-ет', '.-.': 'ре-ША-ет', '...': 'си-не-е',
  '-': 'ТАК', '..-': 'у-нес-ЛО', '..-.': 'фи-ли-МОН-чик', '....': 'хи-ми-чи-те', '-.-.': 'ЦА-пли-НА-ши', '---.': 'ЧА-ША-ТО-нет',
  '----': 'ША-РО-ВА-РЫ', '--.-': 'ЩА-ВАМ-не-ША', '-.--': 'Ы-не-НА-ДО', '-..-': 'ТО-мяг-кий-ЗНАК', '..-..': 'э-ле-РО-ни-ки', '..--': 'ю-ли-А-НА', '.-.-': 'я-МАЛ-я-МАЛ',
  '-----': 'НОЛЬ-ТО-О-КО-ЛО', '.----': 'и-ТО-ЛЬКО-О-ДНА', '..---': 'две-не-ХО-РО-ШО', '...--': 'три-те-бе-МА-ЛО',
  '....-': 'че-тве-ри-те-КА', '.....': 'пя-ти-ле-ти-е', '-....': 'ПО-ше-сти-бе-ри', '--...': 'ДА-ДА-се-ме-ри',
  '---..': 'ВО-СЬМО-ГО-и-ди', '----.': 'НО-НА-НО-НА-ми', '-..-.': 'РА-зде-ли-те-КА'
};

export const Transmission = ({ frequency, volume, lang, ws }) => {
  const [isPressed, setIsPressed] = useState(false);
  const [decodedText, setDecodedText] = useState('');
  const [lastMnemonic, setLastMnemonic] = useState('');
  const [morseBuffer, setMorseBuffer] = useState('');
  
  const [wpm, setWpm] = useState(15);
  
  const canvasRef = useRef(null);
  const lastPressTime = useRef(Date.now());
  const lastDotDuration = useRef(1200 / wpm);
  const textScrollRef = useRef(null);
  const events = useRef([]); // {start, end, type}

  // WPM determines thresholds: 1 unit = 1200 / wpm (ms)
  const unit = 1200 / wpm;
  const dashThreshold = unit * 2; // Halfway between 1x and 3x
  const charGapThreshold = unit * 2.5; // Halfway between 1x and 3x (for gap)
  const wordGapThreshold = unit * 8; // User requested 8x standard
  const [previewChar, setPreviewChar] = useState('');
  const [previewMnemonic, setPreviewMnemonic] = useState('');

  // Auto-scroll text to bottom/right
  useEffect(() => {
    if (textScrollRef.current) {
      textScrollRef.current.scrollLeft = textScrollRef.current.scrollWidth;
    }
  }, [decodedText, morseBuffer]);

  // Tape Animation Logic
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    let animationFrame;
    const pixelsPerMs = wpm / 150;

    const render = () => {
      const now = Date.now();
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const rightMargin = 100;
      const centerY = canvas.height / 2;

      // Draw Axis
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
      ctx.setLineDash([5, 5]);
      ctx.beginPath(); ctx.moveTo(0, centerY); ctx.lineTo(canvas.width, centerY); ctx.stroke();
      ctx.setLineDash([]);

      // Draw Pointer
      ctx.strokeStyle = 'rgba(0, 210, 255, 0.5)';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(canvas.width - rightMargin, 10); ctx.lineTo(canvas.width - rightMargin, canvas.height - 10); ctx.stroke();

      // Draw Finished Events
      events.current.forEach(ev => {
        const xStart = canvas.width - rightMargin + (ev.start - now) * pixelsPerMs;
        const xEnd = ev.end ? canvas.width - rightMargin + (ev.end - now) * pixelsPerMs : canvas.width - rightMargin;
        const width = xEnd - xStart;
        if (xEnd > 0 && xStart < canvas.width) {
          if (ev.type === 'too-long') ctx.fillStyle = '#ff5555'; // Red
          else if (ev.type === 'dash') ctx.fillStyle = '#ff79c6'; // Pink
          else ctx.fillStyle = '#50fa7b'; // Green (dot)
          
          ctx.shadowBlur = 12; ctx.shadowColor = ctx.fillStyle + '80';
          ctx.beginPath(); ctx.roundRect(xStart, centerY - 15, Math.max(width, 4), 30, 6); ctx.fill();
          ctx.shadowBlur = 0;
        }
      });

      // Draw Active Press
      if (isPressed) {
        const xStart = canvas.width - rightMargin + (lastPressTime.current - now) * pixelsPerMs;
        const width = (canvas.width - rightMargin) - xStart;
        const duration = now - lastPressTime.current;
        
        // Color active press based on duration
        if (duration > lastDotDuration.current * 4.5) ctx.fillStyle = '#ff5555';
        else if (duration >= dashThreshold) ctx.fillStyle = '#ff79c6';
        else ctx.fillStyle = '#50fa7b';

        ctx.shadowBlur = 20; ctx.shadowColor = ctx.fillStyle;
        ctx.beginPath(); ctx.roundRect(xStart, centerY - 15, width, 30, 6); ctx.fill();
        ctx.shadowBlur = 0;
      }

      if (events.current.length > 50) {
        events.current = events.current.filter(ev => (ev.end || now) > now - 10000 / pixelsPerMs);
      }
      animationFrame = requestAnimationFrame(render);
    };
    render();
    return () => cancelAnimationFrame(animationFrame);
  }, [wpm, isPressed, dashThreshold]);

  useEffect(() => {
    // If ws is passed as a ref, pull the current object. If it's the socket itself, use it.
    const socket = ws?.current || ws;
    if (!socket) return;
    
    const handleMessage = (event) => {
      const val = event.data;
      const now = Date.now();
      const duration = now - lastPressTime.current;

      if (val === '1') {
        setIsPressed(true);
      } else if (val === '0') {
        setIsPressed(false);
        let type = 'dot';
        if (duration >= dashThreshold) {
          type = (duration > lastDotDuration.current * 4.5) ? 'too-long' : 'dash';
        } else {
          lastDotDuration.current = duration; // Update rhythm based on last dot
        }
        setMorseBuffer(prev => {
          const next = prev + (type === 'dot' ? '.' : '-');
          const codes = lang === 'RU' ? MORSE_RU : MORSE_EN;
          setPreviewChar(codes[next] || '?');
          setPreviewMnemonic(MNEMONICS[next] || ''); // Live mnemonic preview
          return next;
        });
        events.current.push({ start: lastPressTime.current, end: now, type });
      }
      lastPressTime.current = now;
    };
    
    socket.addEventListener('message', handleMessage);
    return () => {
      socket.removeEventListener('message', handleMessage);
    };
  }, [lang, dashThreshold, charGapThreshold, ws, ws?.current]);

  // Handle Gaps (Characters and Words)
  useEffect(() => {
    const timer = setInterval(() => {
      if (isPressed) return;
      const gap = Date.now() - lastPressTime.current;

      // Character gap - finalize current character
      if (morseBuffer && gap > charGapThreshold) {
        decodeMorse(morseBuffer);
        setMorseBuffer('');
      }

      // Word gap - add a space (8x)
      if (!morseBuffer && decodedText && !decodedText.endsWith(' ') && gap > wordGapThreshold) {
        setDecodedText(prev => prev + ' ');
        setLastMnemonic(''); 
      }
    }, 50);
    return () => clearInterval(timer);
  }, [isPressed, morseBuffer, decodedText, charGapThreshold, wordGapThreshold]);

  const decodeMorse = (buffer) => {
    const codes = lang === 'RU' ? MORSE_RU : MORSE_EN;
    const char = codes[buffer] || '?';
    setDecodedText(prev => prev + char);
    setLastMnemonic(MNEMONICS[buffer] || '');
    setPreviewChar('');
    setPreviewMnemonic(''); // Clear preview when confirmed
  };

  return (
    <>


      <main>

          <section className="scrolling-tape-container">
            <canvas ref={canvasRef} width={800} height={100} className="tape-canvas" />
          </section>

          <section className="output-panel">
            <div className="mnemonic-hint">
              {previewMnemonic && <span className="preview-mnemonic">{previewMnemonic}</span>}
              {!previewMnemonic && lastMnemonic && <motion.span initial={{y:10, opacity:0}} animate={{y:0, opacity:1}}>{lastMnemonic}</motion.span>}
              {!lastMnemonic && !previewMnemonic && morseBuffer && <span className="buffer-preview">{morseBuffer}</span>}
            </div>
            <div className="text-scroll-container" ref={textScrollRef}>
              <div className="text-display">
                {decodedText || (!previewChar && <span className="placeholder">START TYPING...</span>)}
                {previewChar && <span className="preview-char">{previewChar}</span>}
                <motion.span animate={{ opacity: [0, 1, 0] }} transition={{ duration: 0.8, repeat: Infinity }} className="cursor">_</motion.span>
              </div>
            </div>
          </section>
        </main>

      <footer>
        <button className="clear-btn" onClick={() => { setDecodedText(''); setMorseBuffer(''); setLastMnemonic(''); events.current = []; }}>CLEAR</button>
      </footer>
    </>
  );
};
