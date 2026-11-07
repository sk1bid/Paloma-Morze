import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { jest } from '@jest/globals';
import { Task5Session } from '../src/task5/session.js';
import { task5DevelopmentEnabled } from '../src/task5/development.js';
import { resolveStep, validate } from '../src/task5/domain.js';

const cells = JSON.parse(readFileSync(new URL('../src/task5/tdr.json', import.meta.url))).cells;
function model({ role = 'main', development = true } = {}) {
  let clock = 0;
  const audio = { ready: true, playSequence: jest.fn(async () => ({ cancelled: false })), stopAll: jest.fn(), keyDown: jest.fn(), keyUp: jest.fn() };
  const persist = jest.fn();
  const session = new Task5Session({ cells, audio, pattern: () => '.', decodePattern: () => 'Е', development, persist, now: () => clock, random: () => 0 });
  session.prepare({ groups: 30, role }, '42');
  const tick = async milliseconds => { clock += milliseconds; session.tick(); await Promise.resolve(); await Promise.resolve(); };
  return { session, audio, persist, tick };
}

describe('Task5 isolated developer navigation', () => {
  test('requires explicit launch query and a developer-capable build', () => {
    expect(task5DevelopmentEnabled({ search: '?task5dev=1' })).toBe(false);
    expect(task5DevelopmentEnabled({ development: true })).toBe(false);
    expect(task5DevelopmentEnabled({ previewBuild: true })).toBe(false);
    expect(task5DevelopmentEnabled({ development: true, search: '?task5dev=1' })).toBe(true);
    expect(task5DevelopmentEnabled({ previewBuild: true, search: '?task5dev=1' })).toBe(true);
    expect(task5DevelopmentEnabled({ previewBuild: true, search: '?task5dev=0' })).toBe(false);
  });
  test.each(['main', 'subordinate'])('every stage freezes exactly where selected with valid adaptive authentication (%s)', role => {
    const { session, audio, persist } = model({ role });
    for (let index = 0; index < session.state.variant.steps.length; index++) {
      session.developmentJump(index);
      expect(session.state.index).toBe(index);
      expect(session.state.status).toBe('paused');
      expect(session.state.developmentPreview).toBe(true);
      const accepted = [];
      for (const attempt of session.state.attempts) {
        const original = session.state.variant.steps.find(step => step.id === attempt.stepID);
        expect(attempt.developerReview).toBe(true);
        if (original.authenticationTokens) expect(validate(attempt.input, resolveStep(original, session.state.variant, accepted), session.state.variant).correct).toBe(true);
        accepted.push(attempt);
      }
      expect(session.summary.transmittedGroups).toBe(0);
      expect(session.summary.receivedGroups).toBe(0);
    }
    expect(audio.playSequence).not.toHaveBeenCalled();
    expect(persist).not.toHaveBeenCalled();
  });
  test('manual stage entry uses the actual key and bot playback flow', async () => {
    const { session, audio, tick } = model();
    session.developmentJump(session.state.variant.steps.findIndex(step => step.id === 'call'));
    session.developmentEnter();
    session.down(); await tick(80); session.up(); await tick(250);
    expect(audio.keyDown).toHaveBeenCalledWith('local'); expect(session.state.input).toBe('Е');
    session.submit(session.target.expectedMessages[0]); await tick(5000);
    expect(audio.playSequence).toHaveBeenCalled(); expect(session.step.id).toBe('quality');
  });
  test('a jump cancels held input and stale audio completions cannot advance the selected stage', async () => {
    const { session, audio, tick } = model(); let finish;
    audio.playSequence.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
    const incoming = session.state.variant.steps.findIndex(step => step.id === 'call-reply');
    session.developmentJump(incoming); session.developmentEnter(); await tick(5000);
    const outgoing = session.state.variant.steps.findIndex(step => step.id === 'auth-self');
    session.developmentJump(outgoing); finish({ cancelled: false }); await Promise.resolve();
    expect(session.state.index).toBe(outgoing); expect(session.state.status).toBe('paused');
    session.developmentEnter(); session.down(); session.state.input = 'ЧЕРНОВИК'; session.developmentJump(incoming);
    expect(session.state.pressed).toBe(false); expect(session.state.input).toBe(''); expect(session.state.buffer).toBe('');
    expect(audio.keyUp).toHaveBeenCalledWith('local');
  });
  test('group-error preview opens a real pending correction and can be corrected manually', async () => {
    const { session, persist, tick } = model(); session.developmentGroupError();
    expect(session.state.radiogramRecovery.request).toBe('РПТ ГР 1 К'); expect(session.state.status).toBe('paused'); expect(session.state.error).toBeTruthy();
    const gram = session.state.variant.radiograms.find(gram => gram.id === session.step.radiogramID);
    expect(session.target.expectedMessages).toEqual([`${gram.groups[0]} К`]);
    session.developmentEnter(); await tick(5000); session.submit(`${gram.groups[0]} К`, 'key');
    expect(session.state.radiogramRecovery).toBeNull(); expect(session.summary.transmittedGroups).toBe(30);
    expect(persist).not.toHaveBeenCalled();
  });
  test('developer history cannot persist, export, or become a normal restored training result', () => {
    const dev = model(); dev.session.developmentJump(dev.session.state.variant.steps.length - 1); dev.session.stop();
    expect(dev.persist).not.toHaveBeenCalled(); expect(() => dev.session.exportData()).toThrow('DEV');
    const archive = dev.session.archive(); expect(archive.developerReview).toBe(true);
    const normal = model({ development: false });
    expect(() => normal.session.restore(archive)).toThrow('DEV');
    expect(() => normal.session.developmentJump(3)).toThrow('недоступна');
    expect(() => normal.session.developmentEnter()).toThrow('недоступна');
    expect(() => normal.session.developmentGroupError()).toThrow('недоступна');
    expect(normal.session.state.index).toBe(0);
    const ordinaryArchive = normal.session.archive();
    dev.session.restore(ordinaryArchive);
    expect(dev.session.archive().developerReview).toBe(true);
  });
  test('incoming code meanings remain gated by the valid simulated AS prefix', () => {
    const { session } = model({ role: 'subordinate' });
    const wait = session.state.variant.steps.findIndex(step => step.id === 'auth-request-wait');
    session.developmentJump(wait); expect(session.state.decodedReceivedCodes).toEqual([]); expect(session.pendingReceivedCodes.length).toBeGreaterThan(0);
    session.developmentJump(wait + 2); expect(session.state.decodedReceivedCodes.length).toBeGreaterThan(0);
  });
  test('main React markup is identical in DEV and production; the separate controller owns its toolbar', () => {
    const script = `
      import {createServer} from 'vite';
      import React from 'react';
      import {renderToStaticMarkup} from 'react-dom/server';
      import assert from 'node:assert/strict';
      const server=await createServer({configFile:false,root:process.cwd(),server:{middlewareMode:true},appType:'custom',logLevel:'silent'});
      try {
        const {Task5}=await server.ssrLoadModule('/src/task5/Task5.jsx');
        const props={active:true,customOverrides:{},transmissionKey:'Space'};
        const normal=renderToStaticMarkup(React.createElement(Task5,props));
        const dev=renderToStaticMarkup(React.createElement(Task5,{...props,development:true}));
        assert(!normal.includes('DEV · ЗАДАЧА №5'));
        assert.equal(dev,normal);
        assert(!dev.includes('Автопросмотр'));
        assert(!dev.includes('task5-development-main'));
        const {DevelopmentController}=await server.ssrLoadModule('/src/task5/DevelopmentController.jsx');
        const controller=renderToStaticMarkup(React.createElement(DevelopmentController));
        assert(controller.includes('DEV · ЗАДАЧА №5'));
        assert(controller.includes('Автопросмотр'));
        assert(!controller.includes('Лента передачи'));
        const {DevelopmentTools}=await server.ssrLoadModule('/src/task5/DevelopmentTools.jsx');
        const state={index:1,developmentPreview:true,variant:{steps:[{id:'a',title:'Вызов',direction:'transmit'},{id:'b',title:'Ответ бота',direction:'receive'}]}};
        const html=renderToStaticMarkup(React.createElement(DevelopmentTools,{state,session:{state},active:true,setAutomatic:()=>{},onError:()=>{}}));
        assert(html.includes('value="1" selected=""'));
        assert(html.includes('Ответ бота · Приём'));
        console.log('Task5 React render smoke passed');
      } finally {await server.close();}
    `;
    const output = execFileSync(process.execPath, ['--input-type=module', '-e', script], { cwd: new URL('..', import.meta.url), encoding: 'utf8' });
    expect(output).toContain('render smoke passed');
  });
});
