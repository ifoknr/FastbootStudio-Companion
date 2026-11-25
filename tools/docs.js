#!/usr/bin/env node
// Makes the pictures the READMEs show, from the WebUI with its demo bridge:
//   docs/webui-en.png, docs/webui-ar.png   four tabs side by side, night theme (1728 x 892)
//   docs/webui-tablet.png, -ar.png         the Device tab on a tablet, day theme (1280 x 800)
// Run it after a change to the look:  node tools/docs.js
// Needs Playwright with its Chromium (npm i playwright; npx playwright install chromium).
'use strict';
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const page = 'file://' + path.join(root, 'module/webroot/index.html');
const out = name => path.join(root, 'docs', name);
const TABS = ['device', 'mods', 'log', 'backup'];

// The demo's toast ("Demo data...") is not part of the look.
const settle = async p => {
  await p.waitForTimeout(3000);
  for (const f of p.frames()) await f.evaluate(() => { const t = document.querySelector('#toast'); if (t) t.hidden = true; }).catch(() => {});
};

(async () => {
  const browser = await chromium.launch();
  for (const lang of ['en', 'ar']) {
    // Four phones in a row; in Arabic the first tab is on the right, as the page itself reads.
    const strip = await browser.newContext({ viewport: { width: 1728, height: 892 }, colorScheme: 'dark' });
    const p = await strip.newPage();
    const tabs = lang === 'ar' ? [...TABS].reverse() : TABS;
    await p.goto(page);
    await p.setContent('<body style="margin:0;display:flex;background:#000">' + tabs.map(t =>
      `<iframe src="${page}?lang=${lang}&theme=dark#${t}" style="border:0;width:432px;height:892px;flex:none"></iframe>`).join('') + '</body>');
    await settle(p);
    await p.screenshot({ path: out(`webui-${lang}.png`) });
    await strip.close();

    const tablet = await browser.newContext({ viewport: { width: 1280, height: 800 }, colorScheme: 'light' });
    const t = await tablet.newPage();
    await t.goto(`${page}?lang=${lang}&theme=light#device`);
    await settle(t);
    await t.screenshot({ path: out(lang === 'ar' ? 'webui-tablet-ar.png' : 'webui-tablet.png') });
    await tablet.close();
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
