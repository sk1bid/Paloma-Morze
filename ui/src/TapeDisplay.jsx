import React, { useEffect, useRef } from 'react';

/**
 * Highly optimized Canvas-based scrolling tape display for Morse signals.
 * Reused from Transmission logic to ensure visual consistency.
 */
export const TapeDisplay = ({ 
  events, 
  isPressed, 
  lastPressTime, 
  wpm = 15, 
  dashThreshold = 200, 
  lastDotDuration = 100,
  height = 100,
  label = '',
  colorMode = 'local' // 'local' (green/pink) or 'remote' (cyan)
}) => {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    let animationFrame;
    
    const pixelsPerMs = wpm / 150;
    const centerY = height / 2;
    const rightMargin = 100;

    const render = () => {
      const now = Date.now();
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      
      // Draw Axis
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
      ctx.setLineDash([5, 5]);
      ctx.beginPath(); 
      ctx.moveTo(0, centerY); 
      ctx.lineTo(canvas.width, centerY); 
      ctx.stroke();
      ctx.setLineDash([]);

      // Draw Pointer
      ctx.strokeStyle = colorMode === 'local' ? 'rgba(0, 210, 255, 0.3)' : 'rgba(0, 210, 255, 0.2)';
      ctx.lineWidth = 1;
      ctx.beginPath(); 
      ctx.moveTo(canvas.width - rightMargin, 5); 
      ctx.lineTo(canvas.width - rightMargin, canvas.height - 5); 
      ctx.stroke();

      // Draw Label
      if (label) {
        ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
        ctx.font = 'bold 10px Inter';
        ctx.fillText(label.toUpperCase(), 10, 20);
      }

      // Draw Finished Events
      const evList = events.current || events;
      evList.forEach(ev => {
        const xStart = canvas.width - rightMargin + (ev.start - now) * pixelsPerMs;
        const xEnd = ev.end ? canvas.width - rightMargin + (ev.end - now) * pixelsPerMs : canvas.width - rightMargin;
        const width = xEnd - xStart;
        
        if (xEnd > 0 && xStart < canvas.width) {
          if (ev.type === 'too-long' || ev.type === 'too_long') ctx.fillStyle = '#ff5555';
          else if (ev.type === 'dash') ctx.fillStyle = '#ff79c6';
          else ctx.fillStyle = '#50fa7b';
          
          ctx.shadowBlur = 4; ctx.shadowColor = ctx.fillStyle + '60';
          ctx.beginPath(); 
          ctx.roundRect(xStart, centerY - 12, Math.max(width, 3), 24, 4); 
          ctx.fill();
          
          if (ev.charLabel) {
            ctx.fillStyle = 'white';
            ctx.font = '10px Inter';
            ctx.fillText(ev.charLabel, xStart, centerY - 18);
          }
          ctx.shadowBlur = 0;
        }
      });

      // Draw Active Press
      if (isPressed) {
        const start = lastPressTime.current || lastPressTime;
        const xStart = canvas.width - rightMargin + (start - now) * pixelsPerMs;
        const width = (canvas.width - rightMargin) - xStart;
        const duration = now - start;
        const refUnit = 1200 / 15; // Evaluations are based on standard 15 WPM vision
        
        if (duration > refUnit * 4.5) ctx.fillStyle = '#ff5555';
        else if (duration >= refUnit * 2) ctx.fillStyle = '#ff79c6';
        else ctx.fillStyle = '#50fa7b';

        ctx.shadowBlur = 20; ctx.shadowColor = ctx.fillStyle;
        ctx.beginPath(); 
        ctx.roundRect(xStart, centerY - 12, Math.max(width, 2), 24, 4); 
        ctx.fill();
        ctx.shadowBlur = 0;
      }

      animationFrame = requestAnimationFrame(render);
    };
    
    render();
    return () => cancelAnimationFrame(animationFrame);
  }, [wpm, dashThreshold, isPressed, label, colorMode, height, lastDotDuration]);

  return (
    <div className="tape-display-wrapper" style={{ height }}>
      <canvas 
        ref={canvasRef} 
        width={900} 
        height={height} 
        className="tape-canvas" 
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
};
