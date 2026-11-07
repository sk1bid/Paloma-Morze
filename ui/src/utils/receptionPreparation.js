// The preparation timer owns no audio: callers may start playback only when
// its promise resolves true. Cancellation settles the old run before restart.
export function createReceptionPreparation(onTick) {
  let timer = null;
  let resolvePending = null;

  const cancel = () => {
    clearTimeout(timer);
    timer = null;
    if (resolvePending) {
      resolvePending(false);
      resolvePending = null;
    }
  };

  return {
    cancel,
    start() {
      cancel();
      let remaining = 5;
      onTick(remaining);
      return new Promise(resolve => {
        resolvePending = resolve;
        const tick = () => {
          remaining -= 1;
          onTick(remaining);
          if (remaining === 0) {
            timer = null;
            resolvePending = null;
            resolve(true);
          } else {
            timer = setTimeout(tick, 1000);
          }
        };
        timer = setTimeout(tick, 1000);
      });
    }
  };
}
