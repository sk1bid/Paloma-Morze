const { spawn } = require('child_process');
const { WebSocketServer } = require('ws');
const path = require('path');
const fs = require('fs');

let activeEngine = null, wss = null, ready = false, isKeyConnected = false;
let engineRate = 48000, nextId = 1, stdoutBuffer = '', audioOwner = null;
const requests = new Map();
const send = (ws, value) => { if (ws.readyState === 1) ws.send(typeof value === 'string' ? value : JSON.stringify(value)); };
function broadcast(value) { if (wss) wss.clients.forEach(ws => send(ws, value)); }
function write(line) { if (activeEngine) activeEngine.stdin.write(line + '\n'); }
function error(ws, id, message) { send(ws, { type: 'audio', event: 'error', id, message }); }
function nativeLine(line) {
    if (line.startsWith('AUDIO ')) {
        const [, event, nativeId, value] = line.split(' ');
        if (event === 'READY') {
            ready = nativeId === '1'; engineRate = Number(value);
            broadcast({ type: 'audio', event: ready ? 'ready' : 'error', sampleRate: engineRate, message: ready ? undefined : 'Unsupported audio protocol' });
            return;
        }
        const request = requests.get(Number(nativeId));
        if (request) {
            send(request.ws, { type: 'audio', event: event.toLowerCase(), id: request.id,
                value: event === 'ERROR' ? value : Number(value), sampleRate: engineRate });
            if (event === 'DONE' || event === 'ERROR') requests.delete(Number(nativeId));
        } else if (event === 'ERROR') broadcast({ type: 'audio', event: 'error', message: value });
        return;
    }
    if (line === '1' || line === '0') broadcast(line);
    else if (line.includes('[Engine] Connected')) { isKeyConnected = true; broadcast('STATUS:CONNECTED'); }
    else if (/Disconnected|Reconnecting|Port lost/.test(line)) { isKeyConnected = false; broadcast('STATUS:DISCONNECTED'); }
    else if (/Permission denied|ERROR:EACCES/.test(line)) broadcast('ERROR:PERMISSION_DENIED');
    if (line) console.log(`[Engine]: ${line}`);
}
function validSettings(s) {
    return s && ['speed','frequency','ratio','pause','front','volume'].every(k => Number.isFinite(s[k])) &&
        s.speed >= 30 && s.speed <= 150 && s.speed % 5 === 0 && s.frequency >= 200 && s.frequency <= 2000 &&
        s.ratio >= 2 && s.ratio <= 4.5 && s.pause >= 1 && s.pause <= 6 && Number.isInteger(s.front) &&
        s.front >= 0 && s.front <= 12 && s.volume >= 0 && s.volume <= 100 &&
        ['sine','square'].includes(s.waveform) && ['clean','original'].includes(s.quality);
}
function message(ws, data) {
    const text = data.toString();
    // Compatibility for existing hardware mute/status clients, never arbitrary stdin.
    if (/^[FVMAW][0-9]+(?:\.[0-9]+)?$/.test(text)) { if (ready) write(text); return; }
    let m;
    try { m = JSON.parse(text); } catch { return; }
    if (m.type !== 'audio') return;
    if (!ready) { error(ws, m.id, 'Звуковой движок недоступен'); return; }
    if (m.op === 'settings') {
        if (!validSettings(m.settings)) { error(ws,m.id,'Invalid audio settings'); return; }
        const s=m.settings;
        write(`S ${s.frequency} ${s.volume} ${s.front} ${s.waveform==='square'?1:0} ${s.quality==='original'?1:0}`);
    } else if (m.op === 'play') {
        if (!validSettings(m.settings) || !Array.isArray(m.patterns) || m.patterns.length>2000 ||
            !m.patterns.length || m.patterns.some(p => typeof p!=='string'|| !/^(?:[.-]+(?:,[.-]+)*|\/)$/.test(p)) ||
            m.patterns.join('|').length>20000 || !['text','learning','repeat'].includes(m.spacing) ||
            (typeof m.id !== 'string' && typeof m.id !== 'number')) { error(ws,m.id,'Invalid audio sequence'); return; }
        if (requests.size>=64) { error(ws,m.id,'Audio queue full'); return; }
        const s=m.settings, id=nextId++;
        requests.set(id,{ ws,id:m.id }); audioOwner=ws;
        write(`P ${id} ${s.speed} ${Math.round(11025/s.frequency)} ${Math.round(s.ratio*10)} ${Math.round(s.pause*10)} ${s.front} ${s.waveform==='square'?1:0} ${s.quality==='original'?1:0} ${['text','learning','repeat'].indexOf(m.spacing)} ${m.patterns.join('|')}`);
    } else if (m.op === 'key' && ['local','remote'].includes(m.source) && typeof m.down === 'boolean') {
        audioOwner=ws; write(`K ${m.source} ${m.down?1:0}`);
    } else if (m.op === 'stop') {
        for (const [id,r] of requests) if (r.ws===ws && (m.id===undefined || r.id===m.id)) write(`STOP ${id}`);
    } else if (m.op === 'reset' && audioOwner===ws) {
        write('RESET'); audioOwner=null;
    } else if (m.op === 'notice' && ['connect','disconnect'].includes(m.name)) write(`N ${m.name==='connect'?1:0}`);
}
function startEngine(isProduction=false, extraArgs=[]) {
    if (wss) return;
    wss=new WebSocketServer({ port:Number(process.env.PALOMA_AUDIO_PORT)||8080, host:'127.0.0.1', maxPayload:65536 });
    const server=wss;
    wss.on('error',e => { console.error('[Bridge]',e.message); broadcast({type:'audio',event:'error',message:'Audio bridge unavailable'}); });
    wss.on('connection',ws => {
        send(ws,isKeyConnected?'STATUS:CONNECTED':'STATUS:DISCONNECTED');
        if(ready)send(ws,{type:'audio',event:'ready',sampleRate:engineRate});
        ws.on('message',data=>message(ws,data));
        ws.on('close',()=>{
            for(const [id,r] of requests)if(r.ws===ws){write(`STOP ${id}`);requests.delete(id);}
            if(audioOwner===ws){write('RESET');audioOwner=null;}
        });
    });
    // Do not spawn another audio device if another app already owns the bridge.
    wss.on('listening',()=>{
        const name=process.platform==='win32'?'morze_app.exe':'morze_app';
        const nativeDir=isProduction?path.join(process.resourcesPath||path.join(__dirname,'..'),'app.asar.unpacked','native'):path.join(__dirname,'native');
        const executable=path.join(nativeDir,name);
        const launch=()=>{
            if(wss!==server)return;
            ready=false;stdoutBuffer='';
            const child=spawn(executable,extraArgs,{cwd:nativeDir});activeEngine=child;
            child.stdin.on?.('error',()=>{});
            child.stdout.on('data',data=>{
                stdoutBuffer+=data.toString();
                let i;
                while((i=stdoutBuffer.indexOf('\n'))>=0){const line=stdoutBuffer.slice(0,i).trim();stdoutBuffer=stdoutBuffer.slice(i+1);nativeLine(line);}
            });
            const failed=message=>{
                if(activeEngine!==child)return;
                ready=false;activeEngine=null;isKeyConnected=false;
                requests.forEach(r=>error(r.ws,r.id,message));requests.clear();
                broadcast({type:'audio',event:'unavailable',message});broadcast('STATUS:DISCONNECTED');
            };
            child.on('error',e=>failed(e.message));
            child.on('close',()=>failed('Звуковой движок остановлен. Перезапустите приложение.'));
            child.stderr.on('data',data=>console.error('[Native]',data.toString()));
        };
        const inputs=['morze_engine_v2.cpp','morse_audio.hpp'].map(file=>path.join(nativeDir,file));
        const stale=!fs.existsSync(executable) || (!isProduction && inputs.some(file=>fs.statSync(file).mtimeMs>fs.statSync(executable).mtimeMs));
        if(!isProduction&&stale){
            const flags=process.platform==='darwin'?['-framework','CoreAudio','-framework','AudioUnit','-framework','CoreFoundation']:process.platform==='win32'?['-lwinmm']:['-lasound','-ldl'];
            const build=spawn('g++',['-std=c++17','-O2',inputs[0],'-I',nativeDir,'-o',executable,'-lpthread','-lm',...flags]);
            build.stderr.on('data',data=>console.error(data.toString()));
            build.on('error',e=>broadcast({type:'audio',event:'unavailable',message:e.message}));
            build.on('close',code=>{if(code===0)launch();else broadcast({type:'audio',event:'unavailable',message:'Native audio build failed'});});
        } else launch();
    });
}
function stopEngine(){
    const child=activeEngine;activeEngine=null;ready=false;
    if(child)child.kill();
    requests.clear();audioOwner=null;stdoutBuffer='';isKeyConnected=false;
    if(wss){wss.close();wss=null;}
}
module.exports={start:startEngine,stop:stopEngine};
