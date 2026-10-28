#!/usr/bin/env node
// 从官网首页的演示台（website/index.html 里的 #stageA）录 README 的两张动图，写到 docs/readme/<zh|en>/：
//   ask.webp       看报错：指着报错那一行、按住键问一句，右上角回答卡出回答（首屏用）
//   followup.webp  看图片：问照片里是哪儿，回答还在时再按一次键追问，追问编上号（「怎么用」一节用）
//
//   node scripts/readme-assets.mjs                 # 中英两份，本机起一个服务读 website/
//   node scripts/readme-assets.mjs --lang zh       # 只录一种
//   node scripts/readme-assets.mjs --site https://askfree.us-cloud.uk
//   node scripts/readme-assets.mjs --format gif    # GitHub 不显示 WebP 时换 GIF
//
// 要 Google Chrome、Playwright（全局装在 /opt/homebrew/lib/node_modules/playwright，或设 PLAYWRIGHT_DIR）、
// img2webp 和 ImageMagick（brew install webp imagemagick）。
// 帧取自 Chrome 的 screencast，页面底色透明，演示台的圆角外面是透明的，GitHub 深浅色都能用同一张。
// 每张 840 px 宽、不超过 400 KB。官网只有中文：英文那份把问题、回答和画面里的系统文字换成英文，
// 回答卡、录音胶囊这些 Ask Free 自己的界面保持中文，和 App 一样（App 只有中文界面）。
// 演示台改了就重录。

import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_DIR || '/opt/homebrew/lib/node_modules/playwright');

const arg = (name, def) => { const i = process.argv.indexOf('--' + name); return i > 0 ? process.argv[i + 1] : def; };
const langs = arg('lang', 'zh,en').split(',');
const format = arg('format', 'webp');
const width = 840;
const maxKB = 400;
const minGap = 90;
// 演示台的场景（SCENES 的下标）和录几轮：看报错只录第一问，看图片录提问加追问
const groups = [
  { name: 'ask', scene: 0, turns: 1 },
  { name: 'followup', scene: 1, turns: 2 },
];
// 场景开头上一个场景的胶囊还在淡出、结尾马上要切走，各剪掉一点（毫秒）
const trimIn = 450;
const trimOut = 120;

// 英文那份：问题和回答、画面里的系统文字（菜单栏、窗口标题、表格内容）换成英文。
// 回答卡状态条、底栏、胶囊是 Ask Free 的界面，App 里只有中文，这里也不换
const EN = {
  turns: [
    [
      { q: 'What does this error mean? How do I fix it?', a: ["The image library sharp isn't installed in this project. Run this in the photo-site folder:", '`npm install sharp`', 'Then run `npm run dev` again.'] },
      { q: 'Same error after installing it?', a: ['It probably went into another folder. Run `pwd` to check the terminal is in photo-site, delete the node_modules folder and run `npm install` again.'] },
    ],
    [
      { q: 'Which mountain is this?', a: ["It's the Matterhorn, on the border of Switzerland and Italy, 4,478 m high. The pyramid-shaped peak is easy to recognize; the village at its foot is Zermatt, on the Swiss side."] },
      { q: 'How do I get there from Zurich?', a: ['The train is easiest: Zurich to Visp, then the small train up to Zermatt, about 3 hours 15 minutes in all. Zermatt is car-free; drivers park in Täsch and take the shuttle train in.'] },
    ],
  ],
  apps: ['Terminal', 'Preview'],
  menus: ['File', 'Edit', 'View', 'Window'],
  clock: 'Thu 9:41',
  keyhint: 'Hold to talk, let go to ask',
  keyLabel: 'Right ⌥',
};

function serveWebsite() {
  const dir = path.join(root, 'website');
  const types = { '.html': 'text/html; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.js': 'text/javascript', '.css': 'text/css' };
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    const file = path.join(dir, p);
    if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` })));
}

// 只留演示台：页面别的都藏起来，演示台钉在左上角、宽 840，底色透明；去掉外阴影（裁出来会被切掉一截）
const ISOLATE = `html,body{background:transparent!important;overflow:hidden!important}
  body>*:not(main){display:none!important} main *{visibility:hidden!important}
  #stageA{visibility:visible!important;position:fixed!important;left:0;top:0;width:${width}px!important;margin:0!important;z-index:9999}
  #stageA *{visibility:visible!important} #stageA .stage{box-shadow:none!important}`;

async function recordGroup(browser, site, lang, group, tmp) {
  const ctx = await browser.newContext({ viewport: { width: 1000, height: 700 }, colorScheme: 'light', reducedMotion: 'no-preference', deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  await page.goto(`${site}/`, { waitUntil: 'networkidle' });
  await page.addStyleTag({ content: ISOLATE });
  if (lang === 'en') {
    await page.evaluate((en) => {
      en.turns.forEach((turns, i) => { SCENES[i].turns = turns; SCENES[i].app = en.apps[i]; });
      const st = document.querySelector('#stageA .stage');
      st.querySelectorAll('.mb > span').forEach((s, i) => { s.textContent = en.menus[i]; });
      st.querySelector('.mb .r > span:last-child').textContent = en.clock;
      st.querySelector('.keyhint > span:last-child').textContent = en.keyhint;
      st.querySelector('.keyhint .kbd').textContent = en.keyLabel;
    }, EN);
  }
  // 演示台按容器宽度缩放（960×600 → 840×525），等它缩好再量
  await page.waitForTimeout(500);
  const box = await page.evaluate(() => { const r = document.querySelector('#stageA .stage').getBoundingClientRect(); return { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) }; });
  // 记下场景切换和回答卡进入追问录音的时刻（Date.now()，和 screencast 帧的时间戳是同一个钟）
  await page.evaluate(() => {
    window.__ev = [];
    const tabs = [...document.querySelectorAll('#tabsA button')];
    new MutationObserver(() => {
      const on = tabs.findIndex((b) => b.classList.contains('on'));
      const last = window.__ev.filter((e) => e[0] === 'scene').at(-1);
      if (!last || last[1] !== on) window.__ev.push(['scene', on, Date.now()]);
    }).observe(document.querySelector('#tabsA'), { subtree: true, attributes: true, attributeFilter: ['class'] });
    const ap = document.querySelector('#stageA .ap');
    new MutationObserver(() => window.__ev.push(['ap', ap.className, Date.now()])).observe(ap, { attributes: true, attributeFilter: ['class'] });
  });
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
  const dir = path.join(tmp, `${lang}-${group.name}`);
  fs.mkdirSync(dir, { recursive: true });
  const frames = [];
  let recording = false;
  cdp.on('Page.screencastFrame', (f) => {
    cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
    if (!recording) return;
    const name = `f${String(frames.length).padStart(4, '0')}.png`;
    fs.writeFileSync(path.join(dir, name), Buffer.from(f.data, 'base64'));
    frames.push({ name, t: f.metadata.timestamp * 1000 });
  });
  await cdp.send('Page.startScreencast', { format: 'png', everyNthFrame: 1, maxWidth: 1000, maxHeight: 700 });
  await page.waitForTimeout(300);
  recording = true;
  // 点标签：这个场景从头放
  const clickedAt = await page.evaluate((i) => { const t = Date.now(); document.querySelectorAll('#tabsA button')[i].click(); return t; }, group.scene);
  // 等到该停的时候：只录第一问的，等回答卡进入追问录音；录完整个场景的，等下一个场景开始
  const endAt = await page.evaluate(async ({ since, scene, turns }) => {
    const deadline = Date.now() + 40000;
    while (Date.now() < deadline) {
      const ev = window.__ev.filter((e) => e[2] >= since);
      const hit = turns === 1
        ? ev.find((e) => e[0] === 'ap' && e[1].split(' ').includes('rec'))
        : ev.find((e) => e[0] === 'scene' && e[1] !== scene);
      if (hit) return hit[2];
      await new Promise((r) => setTimeout(r, 50));
    }
    return null;
  }, { since: clickedAt, scene: group.scene, turns: group.turns });
  await page.waitForTimeout(300);
  await cdp.send('Page.stopScreencast');
  await ctx.close();
  if (!endAt) throw new Error(`${lang} ${group.name}: the scene did not finish within 40 s`);
  const start = clickedAt + trimIn;
  const end = endAt - trimOut;
  const kept = frames.filter((f) => f.t >= start && f.t <= end);
  if (!kept.length) throw new Error(`no frames recorded for ${lang} ${group.name}`);
  return { dir, frames: kept, box, end };
}

function encode(rec, out) {
  const { dir, box } = rec;
  const tail = rec.end - rec.frames.at(-1).t; // 画面不变时 screencast 不发帧，最后一帧一直停到结尾
  const frames = [];
  for (const f of rec.frames) if (!frames.length || f.t - frames.at(-1).t >= minGap) frames.push(f);
  const small = path.join(dir, 'small');
  fs.mkdirSync(small, { recursive: true });
  for (const f of frames) {
    execFileSync('magick', [path.join(dir, f.name), '-crop', `${box.w}x${box.h}+${box.x}+${box.y}`, '+repage', '-resize', `${width}x`, '-strip', path.join(small, f.name)]);
  }
  const hold = Math.max(2200, Math.min(5000, Math.round(tail)));
  const durs = frames.map((f, i) => (i + 1 < frames.length ? Math.max(40, Math.round(frames[i + 1].t - f.t)) : hold));
  const seconds = Math.round((frames.at(-1).t - frames[0].t + hold) / 100) / 10;
  // 第一帧也是动图不播时看到的那张：从最后一帧（回答完整、停着的那一刻）开始，循环还是同一圈
  frames.unshift(frames.pop());
  durs.unshift(durs.pop());
  for (const q of format === 'gif' ? [0] : [90, 82, 74, 66, 58, 50]) {
    if (format === 'gif') {
      const list = [];
      frames.forEach((f, i) => list.push('-delay', String(Math.max(2, Math.round(durs[i] / 10))), path.join(small, f.name)));
      execFileSync('magick', ['-dispose', 'background', ...list, '-layers', 'OptimizePlus', '-loop', '0', out]);
    } else {
      const args = ['-loop', '0', '-lossy', '-q', String(q), '-m', '4'];
      frames.forEach((f, i) => args.push('-d', String(durs[i]), path.join(small, f.name)));
      execFileSync('img2webp', [...args, '-o', out]);
    }
    const kb = Math.round(fs.statSync(out).size / 1024);
    if (kb <= maxKB || format === 'gif') return { kb, q, frames: frames.length, seconds };
  }
  throw new Error(`${out} is still over ${maxKB} KB at the lowest quality`);
}

const { server, url } = arg('site') ? { server: null, url: arg('site').replace(/\/$/, '') } : await serveWebsite();
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'askfree-readme-assets-'));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  for (const lang of langs) {
    const outDir = path.join(root, 'docs', 'readme', lang);
    fs.mkdirSync(outDir, { recursive: true });
    for (const group of groups) {
      const rec = await recordGroup(browser, url, lang, group, tmp);
      const out = path.join(outDir, `${group.name}.${format}`);
      const info = encode(rec, out);
      console.log(`${path.relative(root, out)}: ${info.frames} frames, ${info.seconds} s, ${info.kb} KB${info.q ? ` (quality ${info.q})` : ''}`);
    }
  }
} finally {
  await browser.close();
  server?.close();
  if (!process.env.KEEP_FRAMES) fs.rmSync(tmp, { recursive: true, force: true }); else console.log(`frames kept in ${tmp}`);
}
