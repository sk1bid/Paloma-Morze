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

export const Transmission = ({ frequency, volume, lang, ws, wpm, dashRatio, pauseFactor }) => {
  const [decodedText, setDecodedText] = useState('');
  const [lastMnemonic, setLastMnemonic] = useState('');
  const [morseBuffer, setMorseBuffer] = useState('');
  
  const [isPressedUI, setIsPressedUI] = useState(false);
  
  const canvasRef = useRef(null);
  const lastPressTime = useRef(Date.now());
  const lastDotDuration = useRef(1200 / wpm);
  const textScrollRef = useRef(null);
  const events = useRef([]); // {start, end, type}

  const [previewChar, setPreviewChar] = useState('');
  const [previewMnemonic, setPreviewMnemonic] = useState('');

  // Auto-scroll text to bottom/right
  const wpmRef = useRef(20);
  const dashRatioRef = useRef(3.0);
  const pauseFactorRef = useRef(3.0);

  useEffect(() => { 
    wpmRef.current = wpm;
    dashRatioRef.current = dashRatio;
    pauseFactorRef.current = pauseFactor;
  }, [wpm, dashRatio, pauseFactor]);

  const isPressedRef = useRef(false);

  useEffect(() => {
    if (textScrollRef.current) {
      textScrollRef.current.scrollLeft = textScrollRef.current.scrollWidth;
    }
  }, [decodedText, morseBuffer]);

  // Tape Animation Logic - STABLE & BEAUTIFUL 60fps flow
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d', { alpha: true });
    
    // Offscreen canvas for axis
    const offscreen = document.createElement('canvas');
    const octx = offscreen.getContext('2d', { alpha: true });
    
    let animationFrame;
    let logicalWidth = 0;
    let logicalHeight = 0;
    let dpr = 1;

    const setupCanvas = () => {
      dpr = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      logicalWidth = Math.ceil(rect.width);
      logicalHeight = Math.ceil(rect.height);
      if (logicalWidth === 0) return;

      canvas.width = logicalWidth * dpr;
      canvas.height = logicalHeight * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      canvas.style.width = `${logicalWidth}px`;
      canvas.style.height = `${logicalHeight}px`;

      offscreen.width = canvas.width;
      offscreen.height = canvas.height;
      octx.setTransform(dpr, 0, 0, dpr, 0, 0);
      
      // Clear offscreen (it will be transparent)
      octx.clearRect(0, 0, logicalWidth, logicalHeight);
      
      const centerY = logicalHeight / 2;
      // Vibrant Axis - Beta 2 Style (0.15 opacity)
      octx.strokeStyle = 'rgba(255, 255, 255, 0.15)'; 
      octx.setLineDash([5, 5]);
      octx.beginPath(); octx.moveTo(0, centerY); octx.lineTo(logicalWidth, centerY); octx.stroke();
      octx.setLineDash([]);

      const rightMargin = 100;
      // Vibrant Pointer - Beta 2 Style (0.5 opacity, width 2)
      octx.strokeStyle = 'rgba(0, 210, 255, 0.5)';
      octx.lineWidth = 2;
      octx.beginPath(); octx.moveTo(logicalWidth - rightMargin, 10); octx.lineTo(logicalWidth - rightMargin, logicalHeight - 10); octx.stroke();
    };

    setupCanvas();
    window.addEventListener('resize', setupCanvas);

    const rightMargin = 100;

    const render = () => {
      const now = Date.now();
      const currentWpm = wpmRef.current;
      const pixelsPerMs = currentWpm / 150; 
      const centerY = logicalHeight / 2;

      // 1. Clear Main Canvas
      ctx.clearRect(0, 0, logicalWidth, logicalHeight);
      
      // 2. Static Draw (Draw axes from offscreen)
      ctx.drawImage(offscreen, 0, 0, canvas.width, canvas.height, 0, 0, logicalWidth, logicalHeight);

      // Draw Finished Events - BATCHED Path2D
      const paths = { dot: new Path2D(), dash: new Path2D(), 'too-long': new Path2D() };
      let has = { dot: false, dash: false, 'too-long': false };

      events.current.forEach(ev => {
        const xStart = logicalWidth - rightMargin + (ev.start - now) * pixelsPerMs;
        const xEnd = ev.end ? logicalWidth - rightMargin + (ev.end - now) * pixelsPerMs : logicalWidth - rightMargin;
        const width = Math.max(xEnd - xStart, 4);
        if (xEnd > 0 && xStart < logicalWidth) {
          paths[ev.type].roundRect(xStart, centerY - 15, width, 30, 6);
          has[ev.type] = true;
        }
      });

      // Draw batches with Beta 2 aesthetics (shadowBlur: 4)
      ctx.shadowBlur = 4;
      if (has.dot) { ctx.fillStyle = '#50fa7b'; ctx.shadowColor = '#50fa7b80'; ctx.fill(paths.dot); }
      if (has.dash) { ctx.fillStyle = '#ff79c6'; ctx.shadowColor = '#ff79c680'; ctx.fill(paths.dash); }
      if (has['too-long']) { ctx.fillStyle = '#ff5555'; ctx.shadowColor = '#ff555580'; ctx.fill(paths['too-long']); }
      ctx.shadowBlur = 0;

      // Draw Active Press - Beta 2 Style (shadowBlur: 6)
      if (isPressedRef.current) {
        const xStart = logicalWidth - rightMargin + (lastPressTime.current - now) * pixelsPerMs;
        const width = (logicalWidth - rightMargin) - xStart;
        const duration = now - lastPressTime.current;
        
        // Dynamic thresholds based on global ratio
        const dotThreshold = 1200 / currentWpm;
        const currentDashRatio = dashRatioRef.current;
        const dashThreshold = dotThreshold * (currentDashRatio + 1) / 2;
        const tooLongThreshold = dotThreshold * (currentDashRatio + 1.5);
        
        if (duration > tooLongThreshold) ctx.fillStyle = '#ff5555';
        else if (duration >= dashThreshold) ctx.fillStyle = '#ff79c6';
        else ctx.fillStyle = '#50fa7b';

        ctx.shadowBlur = 6; ctx.shadowColor = ctx.fillStyle;
        ctx.beginPath(); ctx.roundRect(xStart, centerY - 15, width, 30, 6); ctx.fill();
        ctx.shadowBlur = 0;
      }

      if (events.current.length > 50) {
        events.current = events.current.filter(ev => (ev.end || now) > now - 10000 / pixelsPerMs);
      }
      animationFrame = requestAnimationFrame(render);
    };

    animationFrame = requestAnimationFrame(render);
    return () => {
      cancelAnimationFrame(animationFrame);
      window.removeEventListener('resize', setupCanvas);
    };
  }, []);

  useEffect(() => {
    // If ws is passed as a ref, pull the current object. If it's the socket itself, use it.
    const socket = ws?.current || ws;
    if (!socket) return;
    
    const handleMessage = (event) => {
      const val = event.data;
      const now = Date.now();
      const duration = now - lastPressTime.current;
      const currentWpm = wpmRef.current;
      const currentDashRatio = dashRatioRef.current;
      const dotThreshold = 1200 / currentWpm;
      const dashThreshold = dotThreshold * (currentDashRatio + 1) / 2;
      const tooLongThreshold = dotThreshold * (currentDashRatio + 1.5);

      if (val === '1') {
        isPressedRef.current = true;
        setIsPressedUI(true);
      } else if (val === '0') {
        isPressedRef.current = false;
        setIsPressedUI(false);
        let type = 'dot';
        if (duration >= dashThreshold) {
          type = (duration > tooLongThreshold) ? 'too-long' : 'dash';
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
  }, [lang, ws, ws?.current]);

  // Handle Gaps (Characters and Words)
  useEffect(() => {
    const timer = setInterval(() => {
      if (isPressedRef.current) return;
      const gap = Date.now() - lastPressTime.current;
      const unit = 1200 / wpmRef.current;
      const charGapThreshold = unit * pauseFactorRef.current; 
      const wordGapThreshold = charGapThreshold * 2.33; 

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
  }, [morseBuffer, decodedText]);

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
