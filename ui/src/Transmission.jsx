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

const MNEMONICS_RU = {
  '.-': 'ай-ДА', '-...': 'БА-ки-те-кут', '.--': 'ви-ДА-ЛА', '--.': 'ГА-РА-жи', '-..': 'ДО-ми-ки', '.': 'есть',
  '...-': 'же-ле-зи-СТО', '--..': 'ЗА-КА-ти-ки', '..': 'И-ди', '.---': 'йес-НА-ПА-РА', '-.-': 'КАК-же-ТАК', '.-..': 'лу-НА-ти-ки',
  '--': 'МА-МА', '-.': 'НО-мер', '---': 'О-КО-ЛО', '.--.': 'пи-ЛА-ПО-ет', '.-.': 'ре-ША-ет', '...': 'си-не-е',
  '-': 'ТАК', '..-': 'у-нес-ЛО', '..-.': 'фи-ли-МОН-чик', '....': 'хи-ми-чи-те', '-.-.': 'ЦА-пли-НА-ши', '---.': 'ЧА-ША-ТО-нет',
  '----': 'ША-РО-ВА-РЫ', '--.-': 'ЩА-ВАМ-не-ША', '-.--': 'Ы-не-НА-ДО', '-..-': 'ТО-мяг-кий-ЗНАК', '..-..': 'э-ле-РО-ни-ки', '..--': 'ю-ли-А-НА', '.-.-': 'я-МАЛ-я-МАЛ',
  '-----': 'НОЛЬ-ТО-О-КО-ЛО', '.----': 'и-ТО-ЛЬКО-О-ДНА', '..---': 'две-не-ХО-РО-ШО', '...--': 'три-те-бе-МА-ЛО',
  '....-': 'че-тве-ри-те-КА', '.....': 'пя-ти-ле-ти-е', '-....': 'ПО-ше-сти-бе-ри', '--...': 'ДА-ДА-се-ме-ри',
  '---..': 'ВО-СЬМО-ГО-и-ди', '----.': 'НО-НА-НО-НА-ми', '-..-.': 'РА-зде-ли-те-КА'
};

const MNEMONICS_EN = {
  '.-': 'a-PART', '-...': 'BOB-is-the-man', '-.-.': 'CO-ca-CO-la', '-..': 'DOG-did-it', '.': 'egg', '..-.': 'fetch-a-FI-re',
  '--.': 'GO-GO-dance', '....': 'hi-ppo-po-tmus', '..': 'i-nit', '.---': 'in-JA-PON-GOL', '-.-': 'KANG-ga-ROO', '.-..': 'l-A-po-p-o',
  '--': 'MA-MA', '-.': 'NO-el', '---': 'ONE-OF-US', '.--.': 'a-PU-PPY-poo', '--.-': 'GOD-SAVE-the-QUEEN', '.-.': 'ro-TAY-tor',
  '...': 'si-si-si', '-': 'TALL', '..-': 'un-der-WHERE', '...-': 'vic-to-ry-VEE', '.--': 'a-WET-DOG', '-..-': 'X-marks-the-SPOT',
  '-.--': 'YELL-ow-YOYO', '--..': 'ZEN-dra-is-HERE', '-----': 'NO-ONE-GO-ES-HOME', '.----': 'a-LONG-WHI-TE-BEA-RD', '..---': 'and-not-GO-OD-for-US', '...--': 'it-is-not-for-ME',
  '....-': 'and-the-dogs-are-HERE', '.....': 'i-ti-bi-ti-hi', '-....': 'SIX-dogs-are-run-ning', '--...': 'SE-VEN-is-high-up-HERE',
  '---..': 'EIGHT-TEN-is-not-E-NOUGH', '----.': 'NINE-NINE-is-not-for-US'
};

export const Transmission = React.memo(({ frequency, volume, lang, ws }) => {
  const [isPressed, setIsPressed] = useState(false);
  const isPressedRef = useRef(false);
  
  const [decodedText, setDecodedText] = useState('');
  const [lastMnemonic, setLastMnemonic] = useState('');
  const [morseBuffer, setMorseBuffer] = useState('');
  
  const [wpm, setWpm] = useState(15);
  const wpmRef = useRef(15);
  
  const canvasRef = useRef(null);
  const lastPressTime = useRef(Date.now());
  const lastDotDuration = useRef(1200 / 15);
  const textScrollRef = useRef(null);
  const events = useRef([]); // {start, end, type}

  useEffect(() => { wpmRef.current = wpm; }, [wpm]);

  // WPM determines thresholds: 1 unit = 1200 / wpm (ms)
  const unit = 1200 / wpm;
  const dashThreshold = unit * 2; 
  const charGapThreshold = unit * 2.5; 
  const wordGapThreshold = unit * 8; 
  const [previewChar, setPreviewChar] = useState('');
  const [previewMnemonic, setPreviewMnemonic] = useState('');

  const mnemonics = lang === 'RU' ? MNEMONICS_RU : MNEMONICS_EN;

  // Auto-scroll text to bottom/right
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
      octx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
      octx.setLineDash([5, 5]);
      octx.beginPath(); octx.moveTo(0, centerY); octx.lineTo(logicalWidth, centerY); octx.stroke();
      octx.setLineDash([]);

      const rightMargin = 100;
      octx.strokeStyle = 'rgba(0, 210, 255, 0.2)';
      octx.beginPath(); octx.moveTo(logicalWidth - rightMargin, 15); octx.lineTo(logicalWidth - rightMargin, logicalHeight - 15); octx.stroke();
    };

    setupCanvas();
    window.addEventListener('resize', setupCanvas);

    let lastFrameTime = performance.now();
    let frameCount = 0;
    const rightMargin = 100;

    const render = (time) => {
      const frameDelta = time - lastFrameTime;
      lastFrameTime = time;
      
      const now = Date.now();
      const currentWpm = wpmRef.current;
      const pms = currentWpm / 150; 
      const centerY = logicalHeight / 2;
      const basePos = logicalWidth - rightMargin;

      // 1. Clear Main Canvas (Make it transparent to show CSS bg)
      ctx.clearRect(0, 0, logicalWidth, logicalHeight);
      
      // 2. Static Draw (Draw axes from offscreen)
      ctx.drawImage(offscreen, 0, 0, canvas.width, canvas.height, 0, 0, logicalWidth, logicalHeight);

      // 2. Batch Drawing (BEAUTIFUL VERSION)
      const evs = events.current;
      const cutoff = now - (logicalWidth / pms + 1000); 
      
      const paths = {
        dot: new Path2D(),
        dash: new Path2D(),
        'too-long': new Path2D()
      };
      const activeTypes = { dot: false, dash: false, 'too-long': false };

      for (let i = 0; i < evs.length; i++) {
        const ev = evs[i];
        if (ev.end < cutoff) continue;

        const xStart = basePos + (ev.start - now) * pms;
        const xEnd = basePos + (ev.end - now) * pms;
        const width = Math.max(xEnd - xStart, 4);

        if (xEnd > -50 && xStart < logicalWidth + 50) {
          paths[ev.type].roundRect(xStart, centerY - 15, width, 30, 6);
          activeTypes[ev.type] = true;
        }
      }

      // Draw batches with aesthetic colors
      if (activeTypes.dot) { ctx.fillStyle = '#50fa7b'; ctx.fill(paths.dot); }
      if (activeTypes.dash) { ctx.fillStyle = '#ff79c6'; ctx.fill(paths.dash); }
      if (activeTypes['too-long']) { ctx.fillStyle = '#ff5555'; ctx.fill(paths['too-long']); }

      // 3. Active Press (With Glow & Animation)
      if (isPressedRef.current) {
        const xStart = basePos + (lastPressTime.current - now) * pms;
        const width = basePos - xStart;
        const duration = now - lastPressTime.current;
        const dashThr = (1200 / currentWpm) * 2;
        const dotDur = lastDotDuration.current;

        let color = '#50fa7b';
        if (duration > dotDur * 4.5) color = '#ff5555';
        else if (duration >= dashThr) color = '#ff79c6';

        // Draw Glow first (cheap method: gradient path)
        const glow = ctx.createLinearGradient(xStart, 0, basePos, 0);
        glow.addColorStop(0, color);
        glow.addColorStop(1, 'rgba(255, 255, 255, 0.4)');
        
        ctx.save();
        ctx.beginPath();
        ctx.roundRect(xStart, centerY - 15, width, 30, 6);
        ctx.fillStyle = glow;
        ctx.fill();
        
        // White-glass stroke
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.5)';
        ctx.lineWidth = 1.5;
        ctx.stroke();
        ctx.restore();
      }

      // 4. Optimized Memory
      if (evs.length > 80 && Math.random() < 0.01) {
        events.current = evs.filter(ev => ev.end > cutoff);
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
    const socket = ws?.current || ws;
    if (!socket) return;
    
    const handleMessage = (event) => {
      const val = event.data;
      const now = Date.now();
      const currentDashThreshold = (1200 / wpmRef.current) * 2;
      const currentLastDotDuration = lastDotDuration.current;

      if (val === '1') {
        setIsPressed(true);
        isPressedRef.current = true;
      } else if (val === '0') {
        setIsPressed(false);
        isPressedRef.current = false;
        const duration = now - lastPressTime.current;
        let type = 'dot';
        if (duration >= currentDashThreshold) {
          type = (duration > currentLastDotDuration * 4.5) ? 'too-long' : 'dash';
        } else {
          lastDotDuration.current = duration;
        }
        setMorseBuffer(prev => {
          const next = prev + (type === 'dot' ? '.' : '-');
          const codes = lang === 'RU' ? MORSE_RU : MORSE_EN;
          setPreviewChar(codes[next] || '?');
          setPreviewMnemonic(mnemonics[next] || ''); 
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
    setLastMnemonic(mnemonics[buffer] || '');
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
});
