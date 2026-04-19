import React, { useEffect, useRef } from 'react';

/**
 * Highly optimized Canvas-based scrolling tape display for Morse signals.
 * De-coupled from React render cycle and DPI-aware for maximum clarity and smoothness.
 * Universal support for Retina and Standard displays with dynamic screen-switching.
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
  const propsRef = useRef({
    events,
    isPressed,
    lastPressTime,
    wpm,
    dashThreshold,
    lastDotDuration,
    height,
    label,
    colorMode
  });

  // Keep propsRef in sync with latest props on every render
  useEffect(() => {
    propsRef.current = {
      events,
      isPressed,
      lastPressTime,
      wpm,
      dashThreshold,
      lastDotDuration,
      height,
      label,
      colorMode
    };
  });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    let animationFrame;
    
    // Internal state for DPI and Dimension management
    let lastDpr = window.devicePixelRatio || 1;
    let cssWidth = canvas.clientWidth || 900;
    let cssHeight = height || 100;

    const syncResolution = () => {
      const dpr = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      cssWidth = rect.width || 900;
      cssHeight = rect.height || 100;
      
      // Update hardware resolution
      canvas.width = cssWidth * dpr;
      canvas.height = cssHeight * dpr;
      
      // Reset scale and apply current DPR
      ctx.setTransform(1, 0, 0, 1, 0, 0); 
      ctx.scale(dpr, dpr);
      lastDpr = dpr;
    };

    // Initial sync
    syncResolution();

    // Listen for resize and monitor DPR changes
    const resizeObserver = new ResizeObserver(() => {
      syncResolution();
    });
    resizeObserver.observe(canvas);

    // High-precision clock sync
    const startPerf = performance.now();
    const startDate = Date.now();
    
    const render = () => {
      // Pull latest values from Ref to avoid stale closure or loop restarts
      const { 
        events: eventsRef, 
        isPressed: pressed, 
        lastPressTime: pressTimeRef, 
        wpm: currentWpm, 
        height: canvasHeight,
        label: currentLabel,
        colorMode: mode
      } = propsRef.current;

      // Handle height changes propogated from props
      if (canvasHeight !== cssHeight) {
        syncResolution();
      }

      // Periodically check for DPR changes (moving between screens)
      if (window.devicePixelRatio !== lastDpr) {
        syncResolution();
      }

      // Calculate high-precision "now" synchronized with the system clock
      const now = startDate + (performance.now() - startPerf);
      const pixelsPerMs = currentWpm / 150;
      const centerY = cssHeight / 2;
      const rightMargin = 200;

      // Ensure clear canvas at mapped resolution
      ctx.clearRect(0, 0, cssWidth, cssHeight);
      
      // Draw Axis
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
      ctx.setLineDash([5, 5]);
      ctx.beginPath(); 
      ctx.moveTo(0, centerY); 
      ctx.lineTo(cssWidth, centerY); 
      ctx.stroke();
      ctx.setLineDash([]);

      // Draw Pointer (Vertical line where segments emerge)
      ctx.strokeStyle = mode === 'local' ? 'rgba(0, 210, 255, 0.3)' : 'rgba(0, 210, 255, 0.2)';
      ctx.lineWidth = 1;
      ctx.beginPath(); 
      ctx.moveTo(cssWidth - rightMargin, 5); 
      ctx.lineTo(cssWidth - rightMargin, cssHeight - 5); 
      ctx.stroke();

      // Draw Label
      if (currentLabel) {
        ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
        ctx.font = 'bold 10px Inter';
        ctx.fillText(currentLabel.toUpperCase(), 10, 20);
      }

      // Draw Finished Events
      const evList = eventsRef.current || eventsRef;
      evList.forEach(ev => {
        // Reverted to raw floats for sub-pixel anti-aliasing to prevent flickering
        const xStart = cssWidth - rightMargin + (ev.start - now) * pixelsPerMs;
        const xEnd = ev.end ? cssWidth - rightMargin + (ev.end - now) * pixelsPerMs : cssWidth - rightMargin;
        const width = Math.max(xEnd - xStart, 3);
        
        if (xEnd > 0 && xStart < cssWidth) {
          let baseColor;
          if (ev.type === 'too-long' || ev.type === 'too_long') baseColor = '#ff5555';
          else if (ev.type === 'dash') baseColor = '#ff79c6';
          else baseColor = '#50fa7b';

          // Optimization: Use multi-pass fill instead of expensive shadowBlur for finished events
          ctx.fillStyle = baseColor;
          ctx.globalAlpha = 0.25;
          ctx.beginPath();
          ctx.roundRect(xStart - 2, centerY - 14, width + 4, 28, 6);
          ctx.fill();

          ctx.globalAlpha = 1.0;
          ctx.beginPath(); 
          ctx.roundRect(xStart, centerY - 12, width, 24, 4); 
          ctx.fill();
          
          if (ev.charLabel) {
            ctx.fillStyle = 'white';
            ctx.font = '10px Inter';
            ctx.fillText(ev.charLabel, xStart, centerY - 18);
          }
        }
      });

      // Draw Active Press
      if (pressed) {
        const start = pressTimeRef.current || pressTimeRef;
        const xStart = cssWidth - rightMargin + (start - now) * pixelsPerMs;
        const width = (cssWidth - rightMargin) - xStart;
        const duration = now - start;
        const refUnit = 1200 / 15;
        
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
    
    animationFrame = requestAnimationFrame(render);
    return () => {
      cancelAnimationFrame(animationFrame);
      resizeObserver.disconnect();
    };
  }, []); 

  return (
    <div className="tape-display-wrapper" style={{ height }}>
      <canvas 
        ref={canvasRef} 
        className="tape-canvas" 
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
};
