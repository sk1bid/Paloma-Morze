// UI bounds only. PCM, envelope, spacing and playback clocks live in C++.
export const APAK_RATE=11025;
const number=(n,fallback,min,max)=>Math.min(max,Math.max(min,Number.isFinite(Number(n))?Number(n):fallback));
export function normalizeAudioSettings(s={}) {
  const period=Math.round(number(APAK_RATE/Number(s.frequency||APAK_RATE/23),23,8,38));
  return {speed:Math.round(number(s.speed??50,50,30,150)/5)*5,period,frequency:APAK_RATE/period,
    front:Math.round(number(s.front??6,6,0,12)),ratio:number(s.ratio??3,3,2,4.5),pause:number(s.pause??3,3,1,6)};
}
