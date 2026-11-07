import { jest } from '@jest/globals';
import { createReceptionPreparation } from '../src/utils/receptionPreparation.js';

describe('reception preparation', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  test('holds playback for five seconds and reports each second', async () => {
    const onTick = jest.fn();
    const play = jest.fn();
    const preparation = createReceptionPreparation(onTick);
    const ready = preparation.start().then(result => { if (result) play(); });
    expect(onTick.mock.calls).toEqual([[5]]);
    await jest.advanceTimersByTimeAsync(4999);
    expect(play).not.toHaveBeenCalled();
    expect(onTick.mock.calls).toEqual([[5], [4], [3], [2], [1]]);
    await jest.advanceTimersByTimeAsync(1);
    await ready;
    expect(play).toHaveBeenCalledTimes(1);
    expect(onTick).toHaveBeenLastCalledWith(0);
    await jest.advanceTimersByTimeAsync(5000);
    expect(play).toHaveBeenCalledTimes(1);
  });

  test('stop or unmount cancels without starting audio', async () => {
    const onTick = jest.fn();
    const preparation = createReceptionPreparation(onTick);
    const ready = preparation.start();
    await jest.advanceTimersByTimeAsync(2000);
    preparation.cancel();
    expect(await ready).toBe(false);
    await jest.advanceTimersByTimeAsync(10000);
    expect(onTick).toHaveBeenCalledTimes(3);
    expect(jest.getTimerCount()).toBe(0);
  });

  test('restart receives a full countdown and stale run stays cancelled', async () => {
    const preparation = createReceptionPreparation(jest.fn());
    const old = preparation.start();
    await jest.advanceTimersByTimeAsync(4000);
    const fresh = preparation.start();
    expect(await old).toBe(false);
    const ready = jest.fn();
    fresh.then(ready);
    await jest.advanceTimersByTimeAsync(4999);
    expect(ready).not.toHaveBeenCalled();
    await jest.advanceTimersByTimeAsync(1);
    expect(ready).toHaveBeenCalledWith(true);
  });
});
