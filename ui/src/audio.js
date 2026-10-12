import { APAK_RATE, normalizeAudioSettings } from './audioSettings.js';

// A control client only: there is no browser audio output or synthesis here.
export class MorseAudioEngine {
  constructor() {
    this.socket=null;this.ready=false;this.nextId=1;
    this.frequency=APAK_RATE/23;this.volume=50;this.charWpm=50;
    this.dashRatio=3;this.pauseFactor=3;this.front=6;
    this.waveform='sine';
    this.pending=new Map();this.activeSources=new Set();this.onError=null;
  }
  init() { return this.ready; }
  settings() {
    return {speed:this.charWpm,frequency:this.frequency,volume:this.volume,ratio:this.dashRatio,
      pause:this.pauseFactor,front:this.front,waveform:this.waveform,quality:'clean'};
  }
  bindSocket(socket) {
    if(this.socket===socket)return;
    this.detach?.();this.failAll('Соединение со звуковым движком изменилось',false);
    this.socket=socket;this.ready=false;
    const message=event=>this.handleMessage(event.data);
    const close=()=>{this.ready=false;this.failAll('Нет соединения со звуковым движком');};
    socket.addEventListener('message',message);socket.addEventListener('close',close);
    const blur=()=>{if(this.activeSources.has('local'))this.keyUp('local');};
    globalThis.window?.addEventListener?.('blur',blur);
    this.detach=()=>{socket.removeEventListener('message',message);socket.removeEventListener('close',close);globalThis.window?.removeEventListener?.('blur',blur);};
  }
  send(message) {
    if(!this.ready||this.socket?.readyState!==1)return false;
    this.socket.send(JSON.stringify({type:'audio',...message}));return true;
  }
  sync() {this.send({op:'settings',settings:this.settings()});}
  setFrequency(value){this.frequency=normalizeAudioSettings({frequency:value}).frequency;this.sync();}
  setVolume(value){this.volume=Math.min(100,Math.max(0,Number(value)||0));this.sync();}
  setCharWpm(value){this.charWpm=normalizeAudioSettings({speed:value}).speed;this.sync();}
  setPauseFactor(value){this.pauseFactor=normalizeAudioSettings({pause:value}).pause;this.sync();}
  setDashRatio(value){this.dashRatio=normalizeAudioSettings({ratio:value}).ratio;this.sync();}
  setFront(value){this.front=normalizeAudioSettings({front:value}).front;this.sync();}
  setWaveform(value){this.waveform=value==='square'?'square':'sine';this.sync();}
  finish(id,cancelled,error) {
    const entry=this.pending.get(id);if(!entry)return;
    this.pending.delete(id);entry.onChar?.(null);entry.onPulse?.(null);
    entry.resolve({cancelled,...(error?{error}:{})});
  }
  failAll(message,report=true) {
    const hadPending=this.pending.size>0;
    for(const id of [...this.pending.keys()])this.finish(id,true,message);
    this.activeSources.clear();
    if(report&&hadPending)this.onError?.(message);
  }
  handleMessage(data) {
    let m;try{m=JSON.parse(data);}catch{return;}
    if(m.type!=='audio')return;
    if(m.event==='ready'){this.ready=true;this.sync();this.onError?.(null);return;}
    if(m.event==='unavailable'){this.ready=false;this.failAll(m.message);return;}
    const entry=this.pending.get(String(m.id));
    if(m.event==='error'){
      const message=m.message||m.value||'Ошибка звукового движка';
      this.finish(String(m.id),true,message);this.onError?.(message);return;
    }
    if(!entry)return; // Ignore late events from cancelled or replaced sessions.
    if(m.event==='char')entry.onChar?.(entry.characters[m.value]);
    else if(m.event==='pulse')entry.onPulse?.(m.value===1?'dot':m.value===2?'dash':null);
    else if(m.event==='done')this.finish(String(m.id),m.value!==0);
  }
  playSequence(sequence,morseDict,onCharPlay=null,onPulse=null,options={}) {
    const lookup=typeof morseDict==='function'?morseDict:char=>Object.keys(morseDict).find(key=>morseDict[key]===char);
    const patterns=[],characters=[];
    for(const char of sequence){
      if(/^\s+$/.test(char)){patterns.push('/');characters.push(null);continue;}
      const pattern=lookup(char);
      if(pattern&&/^[.\-\s]+$/.test(pattern)){patterns.push(pattern.trim().split(/\s+/).join(','));characters.push(char);}
    }
    if(!patterns.some(p=>p!=='/'))return Promise.resolve({cancelled:false});
    if(!this.ready||this.socket?.readyState!==1){
      const error='Звуковой движок ещё не готов. Подождите или перезапустите приложение.';
      this.onError?.(error);return Promise.resolve({cancelled:true,error});
    }
    const id=String(this.nextId++);
    const promise=new Promise(resolve=>this.pending.set(id,{resolve,characters,onChar:onCharPlay,onPulse}));
    this.send({op:'play',id,patterns,settings:this.settings(),spacing:options.spacing||'text'});
    return promise;
  }
  playString(pattern,_startTime,onPulse=null){return this.playSequence(['_'],()=>pattern,null,onPulse);}
  keyDown(source='local') {
    if(!['local','remote'].includes(source)||this.activeSources.has(source))return;
    if(this.send({op:'key',source,down:true}))this.activeSources.add(source);
    else this.onError?.('Звуковой движок недоступен. Перезапустите приложение.');
  }
  keyUp(source) {
    const sources=source?[source]:[...this.activeSources];
    for(const key of sources){this.activeSources.delete(key);this.send({op:'key',source:key,down:false});}
  }
  notice(name){this.send({op:'notice',name});}
  stopAll(){this.send({op:'reset'});this.failAll('Отменено',false);}
}
export const audioEngine=new MorseAudioEngine();
