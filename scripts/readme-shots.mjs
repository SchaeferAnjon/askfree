#!/usr/bin/env node
// README 的真机截图：开发版 Ask Free Dev 真问真答，截它自己的窗口，写到 docs/readme/<zh|en>/：
//   answer-light.jpg / answer-dark.jpg      看屏幕回答：演示桌面上指着报错问一句，右上角回答卡（问题旁是发给 AI 的截图，红框是指着的地方）
//   followup-light.jpg / followup-dark.jpg  追问：回答卡里第 1 问折成两行，第 2 问连着编号线
//   home-light.jpg / home-dark.jpg          主窗口首页：三种问法、说话时的手势、最近问过
//   history-light.jpg / history-dark.jpg    主窗口历史：按天列出的话题，右边是发给 AI 的截图（带红框）、回答、追问
// 和 docs/readme/shots/ 里两张欢迎引导（第 1 步欢迎、第 2 步授权；界面只有中文，中英文共用）：
//   onboarding-welcome.jpg / onboarding-permissions.jpg
//
//   node scripts/readme-shots.mjs              # 中英两份（英文那份问题和回答是英文，App 界面只有中文）
//   node scripts/readme-shots.mjs --lang zh        # 只拍一种语言（不拍引导）
//   node scripts/readme-shots.mjs --onboarding-only   # 只拍引导
//   node scripts/readme-shots.mjs --no-build   # 用上次编好的开发版
//   node scripts/readme-shots.mjs --screens /tmp/x   # 只画演示桌面看看，不启动开发版
//
// 怎么做到不截到你自己的东西：
// - 「屏幕」是这个脚本用 Chrome 画的演示桌面（终端里的报错、一篇英文 PDF、表格、备忘录），开发版带 -demoScreen 启动，
//   看屏幕问时拿这张图当屏幕，不截真屏幕；发给模型的图、回答卡和历史里的截图都只有演示桌面。
// - 开发版带 -demoData 启动，配置和历史放在临时目录，只有这里问的几题；Key 读开发版自己的 dev_secrets.json，脚本不碰。
//   演示模式不收全局快捷键，不会误开麦。
// - 只截开发版自己的窗口（screencapture -l），回答卡后面先垫一块演示桌面（它的磨砂底会透出后面的东西），
//   再把窗口贴到演示桌面或渐变底上。
// - 开发版的偏好（外观深浅、窗口位置）先导出、跑完原样导回。
// 会真的调用 DeepSeek：每种语言 8 到 20 次提问（回答卡装不下要滚动、英文问题拿中文答了，就撤掉那遍重问，最多 3 遍），
// 用的是开发版里填的 Key。
// 回答每次不一样，截完自己看一遍。
//
// 要 Google Chrome、Playwright（全局装在 /opt/homebrew/lib/node_modules/playwright，或设 PLAYWRIGHT_DIR）、
// ImageMagick、Xcode（编开发版、编两个小工具），开发版要有辅助功能、麦克风、屏幕录制权限（首页才是「一切就绪」），
// 跑脚本的终端要有屏幕录制权限（screencapture -l 截窗口）。

import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_DIR || '/opt/homebrew/lib/node_modules/playwright');

const arg = (name, def) => { const i = process.argv.indexOf('--' + name); return i > 0 ? process.argv[i + 1] : def; };
const onboardingOnly = process.argv.includes('--onboarding-only');
const langs = onboardingOnly ? [] : arg('lang', 'zh,en').split(',');
const build = !process.argv.includes('--no-build');
const DEV_APP = path.join(os.homedir(), 'Applications/Ask Free Dev.app');
const DEV_BIN = path.join(DEV_APP, 'Contents/MacOS/AskFree');
const DEV_ID = 'io.github.schaeferanjon.askfree.dev';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- 演示桌面 ----------

// 屏幕按这台 Mac 的主屏算（点），图是 2 倍像素
function screenInfo(bin) {
  const [w, h, top, bottom] = execFileSync(path.join(bin, 'windows'), ['--screen']).toString().trim().split(' ').map(Number);
  return { w, h, menu: top, dock: bottom };
}

const TEXT = {
  zh: { menus: ['文件', '编辑', '显示', '窗口', '帮助'], clock: '周四 9:41', apps: { term: '终端', word: '预览', sheet: 'Numbers 表格', notes: '备忘录' } },
  en: { menus: ['File', 'Edit', 'View', 'Window', 'Help'], clock: 'Thu 9:41', apps: { term: 'Terminal', word: 'Preview', sheet: 'Numbers', notes: 'Notes' } },
};

const ESC = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const GLYPH = '<svg viewBox="80 80 864 864" width="17" height="17"><path d="M300,268 L300,690 L404,590 L470,744 L540,714 L474,562 L616,562 Z" fill="currentColor" stroke="currentColor" stroke-width="28" stroke-linejoin="round"/><circle cx="660" cy="330" r="128" fill="currentColor"/><path d="M584,428 L560,482 L628,452 Z" fill="currentColor"/></svg>';
const WIFI = '<svg viewBox="0 0 16 16" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2 6.5a9 9 0 0 1 12 0M4.2 9a5.6 5.6 0 0 1 7.6 0M6.5 11.4a2.2 2.2 0 0 1 3 0"/></svg>';

const SHEET = {
  zh: { title: '10 月报销', sub: '上海出差 · 待提交', head: ['A · 日期', 'B · 项目', 'C · 金额（元）'], rows: [['10 月 2 日', '打车', '46'], ['10 月 3 日', '午餐', ''], ['10 月 5 日', '高铁票', '553'], ['10 月 6 日', '酒店', ''], ['10 月 8 日', '打印', '18'], ['10 月 9 日', '午餐', '62'], ['10 月 11 日', '快递', ''], ['10 月 12 日', '打车', '35'], ['10 月 14 日', '会议室', '300'], ['10 月 15 日', '晚餐', '128']] },
  en: { title: 'October expenses', sub: 'Shanghai trip · to submit', head: ['A · Date', 'B · Item', 'C · Amount (CNY)'], rows: [['Oct 2', 'Taxi', '46'], ['Oct 3', 'Lunch', ''], ['Oct 5', 'Train ticket', '553'], ['Oct 6', 'Hotel', ''], ['Oct 8', 'Printing', '18'], ['Oct 9', 'Lunch', '62'], ['Oct 11', 'Courier', ''], ['Oct 12', 'Taxi', '35'], ['Oct 14', 'Meeting room', '300'], ['Oct 15', 'Dinner', '128']] },
};

const NOTES = {
  zh: { title: '周六 · 杭州一日游', lines: ['上午：西湖边骑车，断桥到苏堤', '中午：知味观吃小笼', '下午：灵隐寺、飞来峰', '晚上：河坊街逛逛，九点前回酒店'], target: 0 },
  en: { title: 'Saturday in Zermatt', lines: ['Morning: Gornergrat railway, views of the Matterhorn', 'Lunch: hut at Riffelberg', 'Afternoon: walk down to Riffelsee', 'Evening: dinner in the village, last train 9 pm'], target: 0 },
};

// 每个场景：窗口画什么、指针指哪（data-target 那个元素的中间偏左）
function sceneWindow(scene, lang) {
  const t = TEXT[lang];
  if (scene === 'term') {
    return { title: 'photo-site — zsh — 96×30', dark: true, body: `<pre class="term"><span class="dim">lin@MacBook photo-site %</span> npm run dev

&gt; photo-site@0.3.0 dev
&gt; node scripts/thumbs.js &amp;&amp; vite

<span class="dim">node:internal/modules/cjs/loader:1228
  throw err;
  ^</span>

<span class="er" data-target>Error: Cannot find module 'sharp'</span>
Require stack:
- /Users/lin/photo-site/scripts/thumbs.js
<span class="dim">    at Module._resolveFilename (node:internal/modules/cjs/loader:1225:15)
    at Module._load (node:internal/modules/cjs/loader:1051:27)
    at Module.require (node:internal/modules/cjs/loader:1311:12)
    at require (node:internal/modules/helpers:136:16)
    at Object.&lt;anonymous&gt; (/Users/lin/photo-site/scripts/thumbs.js:2:15) {
  code: 'MODULE_NOT_FOUND',
  requireStack: [ '/Users/lin/photo-site/scripts/thumbs.js' ]
}</span>

Node.js v22.11.0
<span class="dim">lin@MacBook photo-site %</span> </pre>` };
  }
  if (scene === 'word') {
    return { title: 'slow-travel.pdf', body: `<article class="doc"><h1>Notes on slow travel</h1><div class="by">4 min read</div>
<p>Slow travel is less about distance than attention. Instead of ticking off sights, you stay long enough for a place to become ordinary: the baker learns your order, the tram stops start to feel familiar, and the city stops performing for you.</p>
<blockquote>The <span data-target>ephemeral</span> pleasures are the ones you remember.</blockquote>
<p>A market that only appears on Thursdays, the light on the river at six, a conversation that would never have happened if you had been in a hurry.</p>
<p>None of this needs a long holiday. Pick one neighbourhood, leave a free afternoon in the plan, and let the day decide.</p></article>` };
  }
  if (scene === 'sheet') {
    const s = SHEET[lang];
    const rows = s.rows.map((r, i) => `<tr><td class="idx">${i + 2}</td><td>${r[0]}</td><td>${r[1]}</td><td class="n"${i === 3 ? ' data-target' : ''}>${r[2]}</td></tr>`).join('');
    return { title: `${s.title}.numbers`, body: `<div class="sheet"><div class="st">${s.title}</div><div class="ss">${s.sub}</div><table><tr><th class="idx"></th><th>${s.head[0]}</th><th>${s.head[1]}</th><th>${s.head[2]}</th></tr>${rows}</table></div>` };
  }
  const n = NOTES[lang];
  return { title: t.apps.notes, body: `<div class="notes"><div class="nt">${n.title}</div>${n.lines.map((l, i) => `<p${i === n.target ? ' data-target' : ''}>${l}</p>`).join('')}</div>` };
}

function desktopHTML(scene, lang, mode, scr) {
  const t = TEXT[lang];
  const win = sceneWindow(scene, lang);
  const dark = mode === 'dark';
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  *{box-sizing:border-box} html,body{margin:0;width:${scr.w}px;height:${scr.h}px;overflow:hidden}
  body{font:13px -apple-system,"PingFang SC",sans-serif;color:${dark ? '#ececef' : '#1d1d1f'};
    background:${dark ? 'radial-gradient(120% 90% at 20% 10%,#3a4256,#1c1f27 60%,#121318)' : 'radial-gradient(120% 90% at 20% 10%,#eef2f8,#d3dcea 55%,#b9c5d9)'}}
  .mb{position:absolute;left:0;right:0;top:0;height:${scr.menu}px;display:flex;align-items:center;gap:22px;padding:0 20px;font-size:14px;
    background:${dark ? 'rgba(30,32,38,.55)' : 'rgba(255,255,255,.5)'};backdrop-filter:blur(20px)}
  .mb b{font-weight:600} .mb .r{margin-left:auto;display:flex;align-items:center;gap:18px}
  .win{position:absolute;left:96px;top:${scr.menu + 70}px;width:880px;height:${Math.min(660, scr.h - scr.menu - scr.dock - 110)}px;border-radius:12px;overflow:hidden;
    background:${win.dark ? '#1c1c1e' : dark ? '#232326' : '#fff'};box-shadow:0 0 0 .5px rgba(0,0,0,.25),0 22px 60px rgba(0,0,0,${dark ? '.55' : '.25'})}
  .tb{height:40px;display:flex;align-items:center;gap:9px;padding:0 14px;font-size:13px;
    background:${win.dark ? '#2a2a2d' : dark ? '#2b2b2f' : '#f1f1f3'};color:${win.dark || dark ? '#a1a1a8' : '#6e6e73'};border-bottom:1px solid ${win.dark || dark ? 'rgba(255,255,255,.06)' : 'rgba(0,0,0,.08)'}}
  .tb i{width:12px;height:12px;border-radius:6px;background:#ff5f57} .tb i:nth-child(2){background:#febc2e} .tb i:nth-child(3){background:#28c840;margin-right:12px}
  .tb span{flex:1;text-align:center;margin-right:80px}
  pre.term{margin:0;padding:14px 18px;font:14px/1.6 Menlo,monospace;color:#d8d8dc;white-space:pre}
  .term .er{color:#ff7b72;font-weight:600} .term .dim{color:#7d7d86}
  .doc{padding:34px 64px;font:17px/1.7 Georgia,'Songti SC',serif} .doc h1{font:700 30px/1.25 -apple-system,sans-serif;margin:0 0 6px} .doc .by{font-size:13px;color:#8e8e93;font-family:-apple-system,sans-serif;margin-bottom:18px} .doc p{margin:0 0 16px} .doc blockquote{margin:64px 0 64px;padding-left:22px;border-left:3px solid #c7c7cc;font-size:24px;font-style:italic}
  .sheet{padding:18px 22px} .st{font-size:22px;font-weight:600} .ss{font-size:13px;color:${dark ? '#a1a1a8' : '#6e6e73'};margin-top:2px}
  table{border-collapse:collapse;margin-top:16px;width:100%;font-size:14px}
  th,td{border:1px solid ${dark ? 'rgba(255,255,255,.12)' : 'rgba(0,0,0,.1)'};height:40px;padding:0 12px;text-align:left;font-weight:400}
  th{background:${dark ? '#2b2b2f' : '#f5f5f7'};color:${dark ? '#a1a1a8' : '#6e6e73'};font-size:13px;font-weight:500}
  td.n{text-align:right;font-variant-numeric:tabular-nums} .idx{width:38px;text-align:center;color:#8e8e93;background:${dark ? '#2b2b2f' : '#f5f5f7'};padding:0}
  .notes{padding:26px 34px;font-size:16px;line-height:1.7} .nt{font-size:24px;font-weight:700;margin-bottom:12px} .notes p{margin:0 0 6px}
  </style></head><body>
  <div class="mb"><b>${t.apps[scene]}</b>${t.menus.map((m) => `<span>${m}</span>`).join('')}<div class="r">${GLYPH}${WIFI}<span>${t.clock}</span></div></div>
  <div class="win" data-window><div class="tb"><i></i><i></i><i></i><span>${ESC(win.title)}</span></div>${win.body}</div>
  </body></html>`;
}

// 画一张演示桌面（2 倍像素的 PNG），返回指针和窗口（点，原点在屏幕左上）
async function renderDesktop(browser, scene, lang, mode, scr, out) {
  const page = await browser.newPage({ viewport: { width: scr.w, height: scr.h }, deviceScaleFactor: 2 });
  await page.setContent(desktopHTML(scene, lang, mode, scr), { waitUntil: 'load' });
  const geo = await page.evaluate(() => {
    const r = (el) => { const b = el.getBoundingClientRect(); return { x: b.left, y: b.top, w: b.width, h: b.height }; };
    const t = r(document.querySelector('[data-target]'));
    const w = r(document.querySelector('[data-window]'));
    // 指着这一行靠左三分之一处，像人指着读的地方
    return { pointer: { x: Math.round(t.x + Math.min(t.w * 0.35, 150)), y: Math.round(t.y + t.h / 2) }, window: w };
  });
  await page.screenshot({ path: out });
  await page.close();
  return geo;
}

// ---------- 两个小工具：列窗口、在回答卡后面垫演示桌面 ----------

const WINDOWS_SWIFT = `import AppKit
let a = CommandLine.arguments
if a[1] == "--screen" {
    let s = NSScreen.screens[0]
    print(Int(s.frame.width), Int(s.frame.height), Int(s.frame.maxY - s.visibleFrame.maxY), Int(s.visibleFrame.minY - s.frame.minY))
    exit(0)
}
let pid = Int32(a[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!)
}
`;

// backdrop <png> x y w h：无边框窗口，层级在普通窗口之上、回答卡之下，显示演示桌面的这一块（点，原点在屏幕左上）
const BACKDROP_SWIFT = `import AppKit
let a = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let image = NSImage(contentsOfFile: a[1])!
let x = Double(a[2])!, y = Double(a[3])!, w = Double(a[4])!, h = Double(a[5])!
let screen = NSScreen.screens[0].frame
let rect = NSRect(x: x, y: screen.height - y - h, width: w, height: h)
image.size = rect.size
let win = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
win.hasShadow = false
win.collectionBehavior = [.canJoinAllSpaces, .stationary]
let view = NSImageView(frame: NSRect(origin: .zero, size: rect.size))
view.image = image
view.imageScaling = .scaleAxesIndependently
win.contentView = view
win.orderFrontRegardless()
app.run()
`;

function buildTools(dir) {
  for (const [name, src] of [['windows', WINDOWS_SWIFT], ['backdrop', BACKDROP_SWIFT]]) {
    fs.writeFileSync(path.join(dir, `${name}.swift`), src);
    execFileSync('swiftc', ['-O', '-o', path.join(dir, name), path.join(dir, `${name}.swift`)], { stdio: 'inherit' });
  }
}

// ---------- 开发版 ----------

function devPid() {
  try { return Number(execFileSync('pgrep', ['-f', DEV_BIN]).toString().trim().split('\n')[0]); } catch { return null; }
}

function stopDev() { execFileSync('bash', [path.join(root, 'scripts/dev_run.sh'), '--stop'], { stdio: 'ignore' }); }

async function startDev(args) {
  stopDev();
  execFileSync('bash', [path.join(root, 'scripts/dev_run.sh'), '--no-build', ...args], { stdio: 'ignore' });
  for (let i = 0; i < 40 && !devPid(); i++) await sleep(250);
  if (!devPid()) throw new Error('Ask Free Dev did not start');
}

function devWindows(bin) {
  const pid = devPid();
  return execFileSync(path.join(bin, 'windows'), [String(pid)]).toString().trim().split('\n').filter(Boolean)
    .map((l) => { const [id, layer, x, y, w, h] = l.split(' ').map(Number); return { id, layer, x, y, w, h }; });
}

// 最新那一轮的回答（history.jsonl 最后一行）
function lastAnswer(dataDir) {
  return JSON.parse(fs.readFileSync(path.join(dataDir, 'history.jsonl'), 'utf8').trim().split('\n').at(-1)).answer;
}
const hasChinese = (s) => /[\u4e00-\u9fff]/.test(s);

function historyCount(dataDir) {
  const f = path.join(dataDir, 'history.jsonl');
  return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n').filter(Boolean).length : 0;
}

async function waitFor(what, test, timeoutMs) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) { const v = test(); if (v) return v; await sleep(300); }
  throw new Error(`timed out waiting for ${what}`);
}

// 回答卡：层级 3（floating）、宽 400 的那个窗口；高度要连着两次一样才算停稳
async function settledPanel(bin) {
  let last = null;
  for (let i = 0; i < 40; i++) {
    const p = devWindows(bin).find((w) => w.layer === 3 && w.w === 400);
    if (p && last && p.h === last.h && p.y === last.y && p.x === last.x) return p;
    last = p;
    await sleep(400);
  }
  throw new Error('answer card did not settle');
}

function setAppearance(mode) {
  execFileSync('defaults', ['write', DEV_ID, 'MainWindowAppearance', mode]);
}

// ---------- 拼图 ----------

// screencapture -l 截出来的窗口带阴影（四周透明）：找出窗口本体（不透明的部分）在图里的位置
function opaqueBox(png) {
  const g = execFileSync('magick', [png, '-alpha', 'extract', '-threshold', '99%', '-format', '%@', 'info:']).toString().trim();
  const m = g.match(/(\d+)x(\d+)\+(\d+)\+(\d+)/);
  return { w: +m[1], h: +m[2], x: +m[3], y: +m[4] };
}

function capture(id, out) {
  execFileSync('screencapture', ['-x', '-l', String(id), out]);
  return opaqueBox(out);
}

// 指针：和官网演示台同一个箭头，用 Chrome 画（ImageMagick 画不出白描边），尖在 PNG 的 (12, 12) 像素
const CURSOR = '<svg width="22" height="30" viewBox="0 0 22 30"><path d="M2 2 L2 23 L7.2 18 L10.6 26.4 L14.2 24.9 L10.8 16.8 L18 16.8 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
async function renderCursor(browser, out) {
  const page = await browser.newPage({ viewport: { width: 30, height: 40 }, deviceScaleFactor: 2 });
  await page.setContent(`<body style="margin:0;background:transparent"><div style="position:absolute;left:4px;top:4px;filter:drop-shadow(0 1px 1.5px rgba(0,0,0,.4))">${CURSOR}</div></body>`);
  await page.screenshot({ path: out, omitBackground: true });
  await page.close();
}

function jpg(src, out, widthPx, quality = 86) {
  execFileSync('magick', [src, '-resize', `${widthPx}x`, '-strip', '-sampling-factor', '4:2:0', '-quality', String(quality), '-interlace', 'Plane', out]);
  return Math.round(fs.statSync(out).size / 1024);
}

// ---------- 主流程 ----------

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'askfree-readme-shots-'));
const bin = path.join(tmp, 'bin');
fs.mkdirSync(bin);
buildTools(bin);
const scr = screenInfo(bin);
const defaultsBackup = path.join(tmp, 'dev-defaults.plist');
execFileSync('defaults', ['export', DEV_ID, defaultsBackup]);

const QUESTIONS = {
  zh: { word: ['这个词什么意思？', '用它造个句子'], sheet: ['这一列怎么求和？空着的格子要紧吗？'], notes: ['搜一下周六杭州会下雨吗'], term: ['这个报错是什么意思？怎么弄好？', '装完要重启终端吗？'] },
  en: { word: ['What does this word mean?', 'Use it in a sentence'], sheet: ['How do I add up this column? Do the empty cells matter?'], notes: ['Search the web: will it rain in Zermatt on Saturday?'], term: ['What does this error mean? How do I fix it?', 'Do I need to restart the terminal after installing?'] },
};
const CONFIG = { ask_provider: 'deepseek', ask_hotkey_mode: 'modifier', ask_hotkey_modifier: 'rightOption', ask_plain_hotkey_mode: 'none', ask_type_double_tap: 'control', hide_from_screen_share: false };

const browser = await chromium.launch({ channel: 'chrome', headless: true });
// --screens <目录>：只把演示桌面画出来看看，不启动开发版
if (arg('screens')) {
  const dir = path.resolve(arg('screens'));
  fs.mkdirSync(dir, { recursive: true });
  for (const lang of langs) for (const scene of ['term', 'word', 'sheet', 'notes']) for (const mode of ['light', 'dark']) {
    const geo = await renderDesktop(browser, scene, lang, mode, scr, path.join(dir, `${lang}-${scene}-${mode}.png`));
    console.log(lang, scene, mode, JSON.stringify(geo));
  }
  await browser.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  process.exit(0);
}
let backdrop = null;
const stopBackdrop = () => { if (backdrop) { backdrop.kill(); backdrop = null; } };
try {
  if (build) {
    // 只编不留：编完 dev_run.sh 会启动一次，用空的演示目录启动、马上停掉
    const probe = path.join(tmp, 'probe');
    fs.mkdirSync(probe);
    execFileSync('bash', [path.join(root, 'scripts/dev_run.sh'), '-demoData', probe], { stdio: 'inherit' });
    stopDev();
  }
  for (const lang of langs) {
    const outDir = path.join(root, 'docs', 'readme', lang);
    fs.mkdirSync(outDir, { recursive: true });
    const work = path.join(tmp, lang);
    fs.mkdirSync(work);
    const dataDir = path.join(work, 'data');
    fs.mkdirSync(dataDir);
    fs.writeFileSync(path.join(dataDir, 'config.json'), JSON.stringify(CONFIG, null, 2));

    // 回答卡后面垫的那块：屏幕右边一条，从菜单栏下到程序坞上
    const pad = { x: scr.w - 470, y: scr.menu, w: 470, h: scr.h - scr.menu - scr.dock };
    // 回答卡最高 = 可用高度的 70% 减 140（AnswerPanel 里的正文上限）再加卡头卡尾 106（实测）；到顶了就是回答太长、卡里要滚动
    const panelMax = Math.round(Math.max(160, pad.h * 0.7 - 140)) + 106;
    const cursor = path.join(work, 'cursor.png');
    await renderCursor(browser, cursor);

    // 一个场景问一次（可能带追问）；onAnswer(第几问, 回答卡窗口) 在每一问答完时截图
    async function ask(scene, mode, dir, onAnswer) {
      const png = path.join(work, `${scene}-${mode}.png`);
      const geo = await renderDesktop(browser, scene, lang, mode, scr, png);
      const crop = path.join(work, `${scene}-${mode}-pad.png`);
      execFileSync('magick', [png, '-crop', `${pad.w * 2}x${pad.h * 2}+${pad.x * 2}+${pad.y * 2}`, '+repage', crop]);
      setAppearance(mode);
      const before = historyCount(dir);
      const qs = QUESTIONS[lang][scene];
      const args = ['-demoData', dir, '-demoScreen', png, '-demoPointer', `${geo.pointer.x},${geo.pointer.y}`,
        '-demoWindow', `${geo.window.x},${geo.window.y},${geo.window.w},${geo.window.h}`];
      qs.forEach((q) => args.push('-askText', q));
      backdrop = spawn(path.join(bin, 'backdrop'), [crop, pad.x, pad.y, pad.w, pad.h].map(String), { stdio: 'ignore' });
      await startDev(args);
      let finished = true;
      for (let i = 0; i < qs.length; i++) {
        await waitFor(`answer ${i + 1} to "${qs[i]}"`, () => historyCount(dir) >= before + i + 1, 120000);
        const panel = await settledPanel(bin);
        if (onAnswer && (await onAnswer(i, panel, png, geo, lastAnswer(dir))) === false) { finished = false; break; }
      }
      stopDev();
      stopBackdrop();
      return finished;
    }

    // 一个场景问到能用为止，最多 3 遍，不能用的那遍从历史里撤掉：
    // - 英文那份回答里不能有中文：DeepSeek 有时拿中文答英文问题（system prompt 写了「用用户提问的语言回答」也一样）
    // - 要截回答卡的，回答不能长到卡里要滚动（看不到整段回答和编号线）
    // 第 3 遍不再挑，照实截，并打一行提醒
    async function askScene(scene, mode, dir, shoot) {
      for (let attempt = 1; attempt <= 3; attempt++) {
        const saved = `${dir}.saved`;
        fs.cpSync(dir, saved, { recursive: true });
        const last = attempt === 3;
        const ok = await ask(scene, mode, dir, async (i, panel, png, geo, answer) => {
          const problem = lang === 'en' && hasChinese(answer) ? 'answered in Chinese'
            : shoot && panel.h >= panelMax - 2 ? `too long for the card (${panel.h} pt)` : null;
          if (problem) console.log(`${lang} ${scene} ${mode}: answer ${i + 1} ${problem}${last ? ', keeping it (3rd try)' : ', asking again'}`);
          if (problem && !last) return false;
          if (shoot) { if (i === 0) shootAnswer(mode, panel, png, geo); else shootPanel('followup', mode, panel, png); }
          return true;
        });
        if (ok) { fs.rmSync(saved, { recursive: true }); return; }
        fs.rmSync(dir, { recursive: true });
        fs.renameSync(saved, dir);
      }
    }

    // 回答卡贴回演示桌面：整屏宽的「看屏幕回答」
    function shootAnswer(mode, panel, png, geo) {
      const shot = path.join(work, `panel-answer-${mode}.png`);
      const box = capture(panel.id, shot);
      const full = path.join(work, `answer-${mode}.png`);
      // 窗口和回答卡下面只剩桌面，裁掉
      const bottom = Math.max(geo.window.y + geo.window.h, panel.y + panel.h) + 44;
      execFileSync('magick', [png,
        cursor, '-geometry', `+${geo.pointer.x * 2 - 12}+${geo.pointer.y * 2 - 12}`, '-composite',
        shot, '-geometry', `+${panel.x * 2 - box.x}+${panel.y * 2 - box.y}`, '-composite',
        '-crop', `${scr.w * 2}x${bottom * 2}+0+0`, '+repage', full]);
      console.log(`${lang}/answer-${mode}.jpg: ${jpg(full, path.join(outDir, `answer-${mode}.jpg`), 1600)} KB`);
    }

    // 只有回答卡：贴在它后面那块演示桌面上
    function shootPanel(name, mode, panel, png) {
      const shot = path.join(work, `panel-${name}-${mode}.png`);
      const box = capture(panel.id, shot);
      const margin = 36;
      const full = path.join(work, `${name}-${mode}.png`);
      execFileSync('magick', [png, '-crop', `${panel.w * 2 + margin * 4}x${panel.h * 2 + margin * 4}+${panel.x * 2 - margin * 2}+${panel.y * 2 - margin * 2}`, '+repage',
        shot, '-geometry', `+${margin * 2 - box.x}+${margin * 2 - box.y}`, '-composite', full]);
      console.log(`${lang}/${name}-${mode}.jpg: ${jpg(full, path.join(outDir, `${name}-${mode}.jpg`), 900)} KB`);
    }

    // 历史里的几个话题，最后问报错那一题（历史页默认选中最新的）
    for (const scene of ['word', 'sheet', 'notes']) await askScene(scene, 'light', dataDir, false);
    await askScene('term', 'light', dataDir, true);
    // 深色的回答卡另问一遍，记进另一个目录，历史里不重复
    const darkDir = path.join(work, 'data-dark');
    fs.mkdirSync(darkDir);
    fs.writeFileSync(path.join(darkDir, 'config.json'), JSON.stringify(CONFIG, null, 2));
    await askScene('term', 'dark', darkDir, true);

    // 主窗口：首页、历史，深浅各一张，贴在渐变底上
    for (const mode of ['light', 'dark']) {
      setAppearance(mode);
      for (const [name, page] of [['home', 'start'], ['history', 'history']]) {
        await startDev(['-demoData', dataDir, '-openPage', page]);
        // 你在用别的 App 时系统不让开发版抢到前台，窗口是没激活的样子（红绿灯是灰的）
        const main = await waitFor('main window', () => devWindows(bin).find((w) => w.layer === 0 && w.w >= 800), 15000);
        await sleep(2500);
        const shot = path.join(work, `${name}-${mode}-window.png`);
        capture(main.id, shot);
        const full = path.join(work, `${name}-${mode}.png`);
        const bg = mode === 'dark' ? 'radial-gradient:#3a4256-#16181e' : 'radial-gradient:#f3f6fb-#c9d3e3';
        const size = execFileSync('magick', [shot, '-format', '%wx%h', 'info:']).toString().trim();
        execFileSync('magick', ['-size', size, bg, shot, '-composite', full]);
        console.log(`${lang}/${name}-${mode}.jpg: ${jpg(full, path.join(outDir, `${name}-${mode}.jpg`), 1600)} KB`);
        stopDev();
      }
    }
  }

  // 欢迎引导的第 1 步（欢迎）和第 2 步（授权）：界面只有中文、也没有问答，中英文 README 共用，放 docs/readme/shots/。
  // 引导窗口只有浅色；第 3、4 步是填 Key 的框，不截
  if (onboardingOnly || !arg('lang')) {
    const shotsDir = path.join(root, 'docs', 'readme', 'shots');
    fs.mkdirSync(shotsDir, { recursive: true });
    const dir = path.join(tmp, 'onboarding');
    fs.mkdirSync(dir);
    fs.writeFileSync(path.join(dir, 'config.json'), JSON.stringify(CONFIG, null, 2));
    for (const [step, name] of [[0, 'onboarding-welcome'], [1, 'onboarding-permissions']]) {
      execFileSync('defaults', ['write', DEV_ID, 'onboardingStep', '-int', String(step)]);
      await startDev(['-demoData', dir, '-openPage', 'onboarding']);
      const win = await waitFor('onboarding window', () => devWindows(bin).find((w) => w.layer === 0 && w.w >= 600), 15000);
      await sleep(2500);
      const shot = path.join(tmp, `${name}-window.png`);
      capture(win.id, shot);
      const full = path.join(tmp, `${name}.png`);
      const size = execFileSync('magick', [shot, '-format', '%wx%h', 'info:']).toString().trim();
      execFileSync('magick', ['-size', size, 'radial-gradient:#f3f6fb-#c9d3e3', shot, '-composite', full]);
      console.log(`shots/${name}.jpg: ${jpg(full, path.join(shotsDir, `${name}.jpg`), 1400)} KB`);
      stopDev();
    }
  }
} finally {
  stopBackdrop();
  stopDev();
  await browser.close();
  // 开发版偏好原样放回（外观、窗口位置）
  execFileSync('defaults', ['import', DEV_ID, defaultsBackup]);
  if (!process.env.KEEP_WORK) fs.rmSync(tmp, { recursive: true, force: true }); else console.log(`work files kept in ${tmp}`);
}
