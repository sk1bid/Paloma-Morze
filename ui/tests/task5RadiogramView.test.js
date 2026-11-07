import { execFileSync } from 'node:child_process';
import { radiogramRows, radiogramHeaderFields, requestedRadiogramGroup, currentRadiogramGroup, visibleDecodedCodes } from '../src/task5/radiogramView.js';

describe('Task5 radiogram presentation', () => {
  test.each([30, 60])('%i groups retain their values in rows of exactly five', count => {
    const groups = Array.from({ length: count }, (_, index) => String(index).padStart(5, '0'));
    const original = [...groups];
    const rows = radiogramRows(groups);
    expect(rows).toHaveLength(count / 5);
    expect(rows.every(row => row.length === 5)).toBe(true);
    expect(rows.flat()).toEqual(original);
    expect(groups).toEqual(original);
    expect(rows[0][0]).toBe('00000');
  });
  test('repeat highlighting follows one-based GR numbering without treating other repeat forms as a group', () => {
    expect(requestedRadiogramGroup({ request: 'РПТ ГР 1 К' })).toBe(1);
    expect(requestedRadiogramGroup({ request: 'РПТ ГР 60 К' })).toBe(60);
    expect(requestedRadiogramGroup({ request: 'РПТ ПБЛ К' })).toBeNull();
    expect(requestedRadiogramGroup({ request: 'РПТ АЛ К' })).toBeNull();
  });
  test('paper header fields retain the exact transmitted order without invented reception metadata', () => {
    const gram = { originCallsign: 'АБ1В', number: '007', groups: Array(60).fill('АБВГД'), dateTime: '02 09 03' };
    const fields = radiogramHeaderFields(gram);
    expect(fields.map(field => field.label)).toEqual(['Из', '№', 'Групп', 'День', 'Время', 'Повтор №']);
    expect(fields.map(field => field.value).join(' ')).toBe('АБ1В 007 62 02 09 03 007 =');
    expect(fields.some(field => /Принял|Связь|Прин\./.test(field.label))).toBe(false);
  });
  test('overflow following counts only parsed body groups and recognizes the final K', () => {
    expect(currentRadiogramGroup('АБ1В 123 62 02 12 30 123', 60)).toBeNull();
    expect(currentRadiogramGroup('АБ1В 123 62 = ЗАБ 123456 123', 60)).toBeNull();
    expect(currentRadiogramGroup('ЗАГОЛОВОК = АДРЕС = ', 60)).toBe(1);
    expect(currentRadiogramGroup('ЗАГОЛОВОК = АДРЕС = АБВГД ', 60)).toBe(2);
    expect(currentRadiogramGroup('ЗАГОЛОВОК = АДРЕС = АБВГД АБ', 60)).toBe(2);
    expect(currentRadiogramGroup('ЗАГОЛОВОК = АДРЕС = АБВГД ЕЖЗИЙ К', 2)).toBe(3);
    expect(currentRadiogramGroup('ЗАГОЛОВОК=АДРЕС=АБВГД', 60)).toBe(1);
  });
  test('only the latest acknowledged frame from the matching exchange is visible', () => {
    const entries = [
      { stepID: 'auth-peer', groups: [{ code: 'ЗАБ', meaning: 'Старый пароль' }] },
      { stepID: 'auth-counter', groups: [{ code: 'ЗВГ', meaning: '49' }] },
      { stepID: 'rg-0-offer', groups: [{ code: 'ЗДЕ', meaning: 'Монолит' }] },
      { stepID: 'rg-1-offer', groups: [{ code: 'ЗЖИ', meaning: 'Ракета' }] }
    ];
    expect(visibleDecodedCodes({ id: 'auth-self' }, entries)).toEqual([entries[1]]);
    expect(visibleDecodedCodes({ id: 'rg-0-ready' }, entries)).toEqual([entries[2]]);
    expect(visibleDecodedCodes({ id: 'rg-1-offer' }, entries)).toEqual([entries[3]]);
    for (const id of ['rg-0', 'rg-0-receipt', 'signal-0-first', 'close']) expect(visibleDecodedCodes({ id }, entries)).toEqual([]);
    expect(visibleDecodedCodes({ id: 'auth-self' }, [])).toEqual([]);
    expect(entries).toHaveLength(4);
  });
  test('real React rendering separates the blank, keeps five columns and highlights only the requested fragment', () => {
    const script = String.raw`
      import {createServer} from 'vite';
      import React from 'react';
      import {renderToStaticMarkup} from 'react-dom/server';
      import {readFileSync} from 'node:fs';
      import assert from 'node:assert/strict';
      const server=await createServer({configFile:false,root:process.cwd(),server:{middlewareMode:true},appType:'custom',logLevel:'silent'});
      try {
        const {RadiogramBlank}=await server.ssrLoadModule('/src/task5/RadiogramBlank.jsx');
        const {Task5Exchange}=await server.ssrLoadModule('/src/task5/Task5Exchange.jsx');
        const {generate}=await server.ssrLoadModule('/src/task5/domain.js');
        const cells=JSON.parse(readFileSync('src/task5/tdr.json','utf8')).cells;
        for (const groups of [30,60]) {
          const variant=generate({groups},'42',cells), gram=variant.radiograms[0];
          const original=JSON.stringify(gram);
          const recovery={request:'РПТ ГР '+groups+' К'};
          const html=renderToStaticMarkup(React.createElement(RadiogramBlank,{gram,recovery,response:gram.groups[groups-1]+' К'}));
          const rows=[...html.matchAll(/<tr>(.*?)<\/tr>/g)];
          assert.equal(rows.length,groups/5);
          assert(rows.every(row=>(row[1].match(/<td /g)||[]).length===5));
          const rendered=[...html.matchAll(/<td([^>]*)>([^<]*)<\/td>/g)];
          assert.deepEqual(rendered.map(cell=>cell[2]),gram.groups);
          assert.equal(rendered.filter(cell=>cell[1].includes('class="requested"')).length,1);
          assert(rendered[groups-1][1].includes('class="requested"'));
          assert(rendered[groups-1][1].includes('data-group="'+groups+'"'));
          const headerValues=[...html.matchAll(/class="task5-radiogram-value">([^<]*)<\/span>/g)].map(value=>value[1]);
          assert.equal(headerValues.join(' '),gram.header+' =');
          assert.equal((html.match(/class="task5-radiogram-field"/g)||[]).length,6);
          assert(html.includes(gram.urgencyCode+' '+gram.address+' ='));
          assert(html.includes('aria-label="Конец радиограммы">К</div>'));
          assert(html.includes('aria-label="Запрошенный ответ"'));
          assert.equal(JSON.stringify(gram),original);
          const header=renderToStaticMarkup(React.createElement(RadiogramBlank,{gram,recovery:{request:'РПТ ПБЛ К'},response:gram.header+' = '+gram.urgencyCode+' '+gram.address+' = К'}));
          assert(header.includes('task5-radiogram-heading requested'));
          assert(header.includes('task5-radiogram-address requested'));
          assert(!header.includes('class="requested"'));
          const decoded=[{stepID:'auth-peer',groups:[{code:'ЗАБ',meaning:'СТАРЫЙ ПАРОЛЬ'}]},{stepID:'auth-counter',groups:[{code:'ЗВГ',meaning:'НОВЫЙ ПАРОЛЬ'}]},{stepID:'rg-1-offer',groups:[{code:'ЗДЕ',meaning:'КАТЕГОРИЯ ПРИЁМА'}]}];
          const base={variant,decodedReceivedCodes:decoded,status:'running',codeMessage:{text:gram.wireText,groups:[{code:gram.urgencyCode,meaning:'ЛИШНЯЯ КАТЕГОРИЯ'}]}};
          const outgoing=renderToStaticMarkup(React.createElement(Task5Exchange,{...base,step:variant.steps.find(step=>step.id===gram.id),recovery,response:gram.groups[groups-1]+' К'}));
          assert(outgoing.includes('data-group="'+groups+'"'));
          assert(!outgoing.includes('СТАРЫЙ ПАРОЛЬ'));
          assert(!outgoing.includes('НОВЫЙ ПАРОЛЬ'));
          assert(!outgoing.includes('ЛИШНЯЯ КАТЕГОРИЯ'));
          const incoming=variant.radiograms[1];
          const received=renderToStaticMarkup(React.createElement(Task5Exchange,{...base,codeMessage:null,step:variant.steps.find(step=>step.id===incoming.id)}));
          assert(!received.includes(incoming.groups[0]));
          assert(!received.includes('ПАРОЛЬ'));
          assert(!received.includes('КАТЕГОРИЯ ПРИЁМА'));
          const ready=renderToStaticMarkup(React.createElement(Task5Exchange,{...base,codeMessage:null,step:variant.steps.find(step=>step.id===incoming.id+'-ready')}));
          assert(ready.includes('КАТЕГОРИЯ ПРИЁМА')); assert(!ready.includes('ПАРОЛЬ'));
          const auth=renderToStaticMarkup(React.createElement(Task5Exchange,{...base,codeMessage:null,step:variant.steps.find(step=>step.id==='auth-self')}));
          assert(auth.includes('НОВЫЙ ПАРОЛЬ')); assert(!auth.includes('СТАРЫЙ ПАРОЛЬ'));
        }
        console.log('Radiogram React render passed');
      } finally {await server.close();}
    `;
    const output = execFileSync(process.execPath, ['--input-type=module', '-e', script], { cwd: new URL('..', import.meta.url), encoding: 'utf8' });
    expect(output).toContain('render passed');
  });
});
