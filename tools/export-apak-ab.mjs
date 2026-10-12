// Reproducible A/B: actual APAK waveOutWrite buffers vs Paloma's production PCM renderer.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildApakPCM } from '../ui/tests/reference/apakAudio.js';
import { APAK_RATE, apakWav, roundEven } from '../ui/tests/reference/apakAudio.js';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const capturePath = process.argv[2];
const out = process.argv[3];
if (!capturePath || !out) throw Error('Usage: node tools/export-apak-ab.mjs capture.bin output-directory');
const manifest = JSON.parse(fs.readFileSync(path.join(repo,'ui/tests/fixtures/apak-2.12/capture.json')));
const records = [], bytes = fs.readFileSync(capturePath);
for(let offset=0;offset+8<=bytes.length;){
  const timeMs=bytes.readUInt32LE(offset),length=bytes.readUInt32LE(offset+4);
  if(offset+8+length>bytes.length)throw Error('Truncated capture');
  records.push({timeMs,pcm:bytes.subarray(offset+8,offset+8+length)});
  offset+=8+length;
}
const selected=manifest.records.map(x=>({...records[x.index],char:x.char,pattern:x.pat}));
const zero=selected[0].timeMs;
const last=selected.at(-1);
const pcm=new Uint8Array(roundEven((last.timeMs-zero)*APAK_RATE/1000)+last.pcm.length).fill(128);
for(const record of selected)pcm.set(record.pcm,roundEven((record.timeMs-zero)*APAK_RATE/1000));
const sequence=[];
for(const record of selected){
  if(sequence.length && sequence.at(-1)!==record.char)sequence.push(' ');
  sequence.push(record.char);
}
const lookup=char=>selected.find(x=>x.char===char).pattern;
const generated=buildApakPCM(sequence,lookup,{...manifest.settings,spacing:'learning'});
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'01-APAK-live-50-x3.wav'),apakWav(pcm));
fs.writeFileSync(path.join(out,'02-Paloma-fixed-50-x3.wav'),apakWav(generated.pcm));
// Align timestamps only to isolate timbre; report it separately, never as native playback timing.
const aligned=new Uint8Array(pcm.length).fill(128);
let differences=0;
for(const record of selected){
  const r=buildApakPCM([record.char],lookup,manifest.settings);
  for(let i=0;i<r.pcm.length;i++)if(r.pcm[i]!==record.pcm[i])differences++;
  aligned.set(r.pcm,roundEven((record.timeMs-zero)*APAK_RATE/1000));
}
fs.writeFileSync(path.join(out,'03-Paloma-aligned-for-timbre.wav'),apakWav(aligned));
const stats={settings:manifest.settings,sequence,characters:selected.length,
  apakDurationSeconds:pcm.length/APAK_RATE,palomaDurationSeconds:generated.duration,
  differingToneSamples:differences,
  captureMethod:'APAK waveOutWrite PCM with GetTickCount submit timestamps, not a microphone or loopback recording',
  palomaMethod:'Frozen JS reference model for the original APAK PCM; production audio now runs in C++',
  alignedMethod:'Paloma sign buffers placed at captured APAK submit timestamps, isolates timbre only'};
fs.writeFileSync(path.join(out,'comparison.json'),JSON.stringify(stats,null,2)+'\n');
console.log(JSON.stringify(stats,null,2));
