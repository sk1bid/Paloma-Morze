// Opt-in real Electron/DOM test. Build with VITE_TASK5_DEV_TOOLS=1 first.
const { app, BrowserWindow, ipcMain } = require('electron');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'paloma-task5-geometry-'));
app.setPath('userData', profile);
app.setPath('sessionData', profile);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, label) {
  for (let i = 0; i < 100; i++) { if (predicate()) return; await sleep(50); }
  throw new Error(`Timeout: ${label}. Build DEV assets before running this test.`);
}
app.whenReady().then(async () => {
  const window = new BrowserWindow({ show: false, width: 1100, height: 850, webPreferences: { nodeIntegration: true, contextIsolation: false } });
  let latest;
  const update = (event, snapshot) => { if (event.sender === window.webContents) latest = snapshot; };
  ipcMain.on('task5-dev:state', update);
  await window.loadFile(path.join(__dirname, '../dist/index.html'), { query: { task5dev: '1' } });
  await until(() => latest?.variant?.steps.length, 'main session prepared');
  const index = latest.variant.steps.findIndex(step => /^rg-\d+$/.test(step.id) && step.direction === 'transmit');
  assert(index >= 0);
  window.webContents.send('task5-dev:command', { type: 'jump', index });
  await until(() => latest.index === index && latest.status === 'paused', 'radiogram jump');
  const results = [];
  for (const theme of ['dark', 'light']) {
  await window.webContents.executeJavaScript(`document.documentElement.setAttribute('data-theme', '${theme}')`);
  for (const [width, height] of [[1100, 850], [1280, 900], [900, 700]]) {
    window.setSize(width, height);
    await sleep(400);
    const geometry = await window.webContents.executeJavaScript(`(async () => {
      await document.fonts.ready;
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      const workspace = document.querySelector('.task5-workspace');
      const table = document.querySelector('.task5-radiogram-body');
      const end = document.querySelector('[aria-label="Конец радиограммы"]');
      const header = document.querySelector('[aria-label="Заголовок"]');
      const cell = table?.querySelector('td');
      const main = document.querySelector('.task5-main');
      const paper = document.querySelector('.task5-radiogram-paper');
      const sidebar = document.querySelector('.task5-container .reception-sidebar');
      const probe = document.createElement('span'); probe.style.color = 'var(--text-secondary)'; main.appendChild(probe);
      const secondary = getComputedStyle(probe).color; probe.remove();
      if (!workspace || !table || !end || !cell) throw new Error('Radiogram DOM missing');
      const rect = element => ({ top: element.getBoundingClientRect().top, bottom: element.getBoundingClientRect().bottom, left: element.getBoundingClientRect().left, right: element.getBoundingClientRect().right });
      return { viewport: {width:innerWidth,height:innerHeight}, workspace:rect(workspace), table:rect(table), end:rect(end), header:rect(header), clientHeight:workspace.clientHeight, scrollHeight:workspace.scrollHeight, clientWidth:workspace.clientWidth, scrollWidth:workspace.scrollWidth, groups:table.querySelectorAll('td').length, columns:[...table.rows].map(row=>row.cells.length), font:getComputedStyle(cell).fontFamily, appFont:getComputedStyle(main).fontFamily, fontSize:parseFloat(getComputedStyle(cell).fontSize), tape:main.querySelector('.scrolling-tape-container').getBoundingClientRect().height, keyed:main.querySelector('.task5-key-display').getBoundingClientRect().height, paperBackground:getComputedStyle(paper).backgroundColor, appSurface:getComputedStyle(sidebar).backgroundColor, paperRadius:getComputedStyle(paper).borderRadius, appRadius:getComputedStyle(sidebar).borderRadius, paperImage:getComputedStyle(paper).backgroundImage, ink:getComputedStyle(cell).color, appInk:getComputedStyle(main).color, captionInk:getComputedStyle(header.querySelector('.task5-radiogram-caption')).color, secondary, gridBorder:getComputedStyle(cell).borderTopWidth, gridStyle:getComputedStyle(cell).borderTopStyle, gridColor:getComputedStyle(cell).borderTopColor, appBorder:getComputedStyle(sidebar).borderTopColor, outerBorder:getComputedStyle(paper).borderTopWidth, fields:header.querySelectorAll('.task5-radiogram-field').length };
    })()`);
    assert.equal(geometry.groups, 60, 'seeded form must have 60 groups');
    assert(geometry.columns.every(columns => columns === 5), 'exactly five columns');
    assert.equal(geometry.font, geometry.appFont, 'radiogram must use the app font');
    assert(geometry.fontSize >= 15, 'readable font floor');
    assert(geometry.tape >= 60 && geometry.tape <= 63, 'compact visible tape');
    assert(geometry.keyed >= 40 && geometry.keyed <= 48, 'compact keyed text panel');
    assert.equal(geometry.fields, 6, 'subdivided truthful header');
    assert.equal(geometry.paperBackground, geometry.appSurface, 'existing themed app surface');
    assert.equal(geometry.paperRadius, geometry.appRadius, 'existing panel radius');
    assert.equal(geometry.paperImage, 'none', 'no simulated texture');
    assert.equal(geometry.ink, geometry.appInk, 'existing primary text');
    assert.equal(geometry.captionInk, geometry.secondary, 'existing secondary text');
    assert.equal(geometry.gridColor, geometry.appBorder, 'existing themed border');
    assert.equal(geometry.gridStyle, 'solid', 'ruled body grid');
    assert.equal(Number.parseFloat(geometry.gridBorder), 1, 'thin body rules');
    assert.equal(Number.parseFloat(geometry.outerBorder), 1, 'paper perimeter');
    assert(geometry.header.top >= geometry.workspace.top - 1, 'header visible');
    assert(geometry.end.bottom <= geometry.workspace.top + geometry.clientHeight + 1, `final K must fit: ${JSON.stringify(geometry)}`);
    assert(geometry.table.bottom <= geometry.workspace.bottom + 1, 'all table rows visible');
    assert(geometry.scrollWidth <= geometry.clientWidth + 1, 'no horizontal overflow');
    assert(geometry.scrollHeight <= geometry.clientHeight + 1, 'no vertical scrolling required');
    results.push({ theme, size: [width, height], ...geometry });
  }
  }
  console.log(JSON.stringify({ passed: true, results }, null, 2));
  ipcMain.removeListener('task5-dev:state', update);
  window.destroy(); app.quit();
}).catch(error => { console.error(error); app.exit(1); });
