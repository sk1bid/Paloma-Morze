// Integration smoke: real native process + bridge + WebSocket, without a sound device.
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
const require=createRequire(new URL('../ui/package.json',import.meta.url));
const WebSocket=require('ws');const bridge=require('../ui/bridge.cjs');
process.env.PALOMA_AUDIO_PORT='18080';
const settings={speed:50,frequency:612.5,volume:50,ratio:3,pause:3,front:6,waveform:'sine',quality:'clean'};
bridge.start(false,['--test-mode','headless']);
const ws=new WebSocket('ws://127.0.0.1:18080');const messages=[];const waiting=[];
ws.on('message',data=>{try{const m=JSON.parse(data);messages.push(m);for(const waiter of [...waiting])if(waiter.test(m)){waiting.splice(waiting.indexOf(waiter),1);clearTimeout(waiter.timer);waiter.resolve(m);}}catch{}});
const until=test=>new Promise((resolve,reject)=>{const old=messages.find(test);if(old){resolve(old);return;}const waiter={test,resolve,timer:setTimeout(()=>reject(Error('Native audio timeout: '+JSON.stringify(messages.slice(-8)))),15000)};waiting.push(waiter);});
const send=m=>ws.send(JSON.stringify({type:'audio',...m}));
try {
  await until(m=>m.event==='ready');send({op:'settings',settings});
  send({op:'play',id:'smoke',settings,spacing:'text',patterns:['.','.-..']});
  const done=await until(m=>m.event==='done'&&m.id==='smoke');assert.equal(done.value,0);
  assert(messages.some(m=>m.event==='char'&&m.id==='smoke'&&m.value===1));
  send({op:'play',id:'long',settings,spacing:'text',patterns:Array(600).fill('.-..')});
  await until(m=>m.event==='start'&&m.id==='long');send({op:'key',source:'remote',down:true});
  assert.equal((await until(m=>m.event==='done'&&m.id==='long')).value,1);
  send({op:'key',source:'remote',down:false});send({op:'reset'});
  console.log('PASS: real C++ bridge READY, PCM-clock progress/completion, 3000-byte sequence, remote preemption.');
} finally {ws.close();bridge.stop();for(const w of waiting)clearTimeout(w.timer);}
