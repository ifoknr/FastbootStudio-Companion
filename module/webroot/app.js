'use strict';
// Fastboot Studio Companion WebUI. All data comes from bin/fbs through the root manager's
// WebUI bridge (window.ksu: KernelSU, APatch, MMRL and WebUI X all provide it). Opened in a
// plain browser, demo.js stands in for the bridge with a made-up phone.

const MOD = '/data/adb/modules/fastboot_studio_companion';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const T = (k, ...a) => i18n.t(k, ...a);
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

/* ---------------------------------------------------------------- bridge */

const Bridge = (() => {
  let n = 0;
  const cbName = kind => `fbs_${kind}_${Date.now()}_${n++}`;
  const quote = a => `'${String(a).replace(/'/g, `'\\''`)}'`;

  function emitter() {
    const listeners = {};
    return {
      on(ev, fn) { (listeners[ev] = listeners[ev] || []).push(fn); },
      emit(ev, ...args) { (listeners[ev] || []).forEach(fn => fn(...args)); },
    };
  }

  // One command, whole output at the end.
  function exec(args) {
    return new Promise((resolve, reject) => {
      const cb = cbName('exec');
      window[cb] = (errno, stdout, stderr) => { delete window[cb]; resolve({ errno, stdout, stderr }); };
      try {
        ksu.exec(['sh', MOD + '/bin/fbs', ...args].map(quote).join(' '), '{}', cb);
      } catch (e) {
        delete window[cb];
        reject(e);
      }
    });
  }

  // A long job: onLine gets each stdout line as it arrives; resolves with the exit code.
  function spawn(args, onLine) {
    return new Promise((resolve, reject) => {
      const cb = cbName('spawn');
      const child = emitter();
      child.stdin = emitter();
      child.stdout = emitter();
      child.stderr = emitter();
      child.stdout.on('data', d => String(d).split('\n').forEach(l => l && onLine(l)));
      child.on('exit', code => { delete window[cb]; resolve(code); });
      child.on('error', e => { delete window[cb]; reject(e); });
      window[cb] = child;
      try {
        ksu.spawn('sh', JSON.stringify([MOD + '/bin/fbs', ...args]), '{}', cb);
      } catch (e) {
        delete window[cb];
        reject(e);
      }
    });
  }

  return { exec, spawn };
})();

async function fbs(...args) {
  const r = await Bridge.exec(args);
  if (r.errno !== 0 && !r.stdout) throw new Error((r.stderr || '').trim() || 'exit ' + r.errno);
  return r.stdout;
}
const fbsJson = async (...args) => JSON.parse(await fbs(...args));

/* ---------------------------------------------------------------- formatting */

// Left-to-right isolate: keeps "340 MiB" or "boot_a, dtbo_a" in order inside Arabic text.
const iso = s => '\u2066' + s + '\u2069';
const MiB = 1048576, GiB = 1073741824;
function size(bytes) {
  if (bytes == null || isNaN(bytes)) return '–';
  if (bytes >= GiB) return iso(+(bytes / GiB).toFixed(bytes >= 10 * GiB ? 1 : 2) + ' GiB');
  if (bytes >= MiB) return iso(Math.round(bytes / MiB) + ' MiB');
  return iso(Math.max(1, Math.round(bytes / 1024)) + ' KiB');
}
const sectors = s => (s == null ? null : s * 512);
const celsius = (v, scale) => (v == null ? '–' : (v / scale).toFixed(1) + '°C');

let toastTimer;
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 3200);
}

async function copy(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.append(ta);
    ta.select();
    try { document.execCommand('copy'); } catch { /* the text stays selected for a manual copy */ }
    ta.remove();
  }
  toast(T('copied'));
}

// A bottom sheet. buttons: [{label, kind, onClick}]; a button without onClick just closes.
function sheet(title, bodyHtml, buttons) {
  $('#sheetTitle').textContent = title;
  $('#sheetBody').innerHTML = bodyHtml;
  const row = $('#sheetBtns');
  row.className = 'row2' + (buttons.length === 1 ? ' one' : '');
  row.innerHTML = '';
  buttons.forEach(b => {
    const el = document.createElement('button');
    el.className = 'btn ' + (b.kind || 'ghost');
    el.textContent = b.label;
    el.onclick = () => { if (b.onClick) b.onClick(); else closeSheet(); };
    row.append(el);
  });
  $('#sheet').hidden = false;
  row.lastElementChild?.focus();
}
function closeSheet() { $('#sheet').hidden = true; }
$('#sheet').addEventListener('click', e => { if (e.target.id === 'sheet') closeSheet(); });

/* ---------------------------------------------------------------- state and tabs */

const S = { info: null, parts: null, view: 'device' };

function show(view) {
  S.view = view;
  $$('.nav button').forEach(b => b.setAttribute('aria-selected', String(b.dataset.v === view)));
  $$('.view').forEach(v => { v.hidden = v.id !== 'v-' + view; });
  if (view === 'log') Log.kick();
  if (view === 'device') Cpu.kick();
  window.scrollTo(0, 0);
}
$$('.nav button').forEach(b => b.addEventListener('click', () => show(b.dataset.v)));

/* ---------------------------------------------------------------- device */

function kv(el, rows) {
  el.innerHTML = rows.filter(Boolean).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v ?? '–')}</dd>`).join('');
}

function renderDevice() {
  const i = S.info;
  const name = i.model && i.brand && !i.model.toLowerCase().startsWith(i.brand.toLowerCase()) ? `${i.brand} ${i.model}` : i.model || i.brand;
  $('#whoLine').textContent = [name, i.platform, i.slot ? 'slot ' + i.slot : ''].filter(Boolean).join(' · ');
  const root = $('#rootChip');
  root.textContent = i.root;
  root.hidden = !i.root || i.root === 'unknown';
  $('#betaChip').hidden = i.channel !== 'beta';

  const vb = (i.boot.vbstate || '').toLowerCase();
  const avb = $('#avbChip');
  avb.textContent = vb ? 'AVB ' + vb : 'AVB ?';
  avb.className = 'chip ' + (vb === 'green' ? '' : vb === 'orange' ? 'warn' : vb ? 'danger' : 'mute');
  const unlocked = i.boot.device_state ? i.boot.device_state === 'unlocked' : i.boot.locked === false;
  kv($('#bootKv'), [
    [T('boot.bootloader'), unlocked ? T('boot.unlocked') : T('boot.locked')],
    ['SELinux', i.selinux],
    [T('boot.slot'), i.slot || T('boot.none')],
    [T('boot.layout'), [i.slot ? 'A/B' : 'A-only', i.dynamic ? 'dynamic' : 'static'].join(' · ')],
    [T('boot.treble'), i.treble ? [T('yes'), i.vndk && 'VNDK ' + i.vndk, i.arch].filter(Boolean).join(' · ') : T('no')],
  ]);
  $('#spoofNote').hidden = !i.boot.spoofed;

  $('#kmiChip').hidden = !i.kmi;
  kv($('#kernelKv'), [
    [T('kernel.version'), i.kernel],
    ['KMI', i.kmi || T('kernel.nokmi')],
    [T('kernel.patch'), i.patch],
    [T('kernel.android'), i.android && `${i.android} (SDK ${i.sdk})`],
    [T('kernel.build'), i.build],
  ]);

  const stats = [];
  const b = i.battery;
  if (b.health != null) {
    const cls = b.health >= 80 ? 'good' : b.health >= 60 ? 'warn' : 'bad';
    stats.push(stat(T('stat.battery'), b.health + '%', T('stat.cycles', b.cycles ?? '–', celsius(b.temp_dc, 10)), b.health, cls));
  } else if (b.level != null) {
    stats.push(stat(T('stat.battery'), b.level + '%', T('stat.level', b.level), b.level, ''));
  }
  const st = i.storage;
  if (st) {
    const life = Math.max(parseInt(st.life_a, 16) || 0, parseInt(st.life_b, 16) || 0);
    const eol = parseInt(st.eol, 16) || 0;
    if (life) {
      const used = life >= 11 ? T('stat.exceeded') : `${(life - 1) * 10}–${life * 10}%`;
      const cls = life >= 9 || eol >= 3 ? 'bad' : life >= 6 || eol === 2 ? 'warn' : '';
      const note = (eol ? T('stat.eol.' + Math.min(eol, 3)) + ' · ' : '') + 'life ' + (st.life_a || '?');
      stats.push(stat(T('stat.storage', st.type === 'emmc' ? 'eMMC' : 'UFS'), used, note, Math.min(life, 10) * 10, cls));
    }
  }
  // Memory is live in the CPU card below.
  $('#stats').innerHTML = stats.join('');
  $('#stats').style.gridTemplateColumns = stats.length === 1 ? '1fr' : '';
}

function stat(label, value, note, pct, cls) {
  return `<div class="stat ${cls}"><span class="l">${esc(label)}</span><span class="v">${esc(value)}</span>` +
    `<span class="n">${esc(note)}</span><div class="meter"><i style="width:${Math.max(0, Math.min(100, pct)).toFixed(0)}%"></i></div></div>`;
}

/* The black box: the previous boot's kernel log from pstore. */
const PANIC = /Kernel panic|Internal error: Oops|\bOops\b|BUG: |Unable to handle kernel|hard LOCKUP|watchdog bite|Fatal exception|SError/i;

async function loadBlackBox() {
  const out = await fbs('last', '200');
  const lines = out.split('\n');
  const reason = (lines.find(l => l.startsWith('#reason=')) || '').slice(8);
  const source = (lines.find(l => l.startsWith('#source=')) || '').slice(8);
  const body = lines.filter(l => !l.startsWith('#') && l !== '');
  const hit = body.findIndex(l => PANIC.test(l));
  const bad = hit >= 0 || /panic|watchdog|oops|hw_reset|thermal/i.test(reason) || /dmesg-ramoops/.test(source);
  const box = $('#blackbox');
  const showLog = () => sheet(`${T('bb.sheet')} · ${reason || '?'}`,
    `<p class="note ltr">${esc(source || '')}</p><pre class="code wrap">${body.map(l => PANIC.test(l) ? `<span class="hit">${esc(l)}</span>` : esc(l)).join('\n')}</pre>`,
    [{ label: T('copy'), onClick: () => copy(body.join('\n')) }, { label: T('close'), kind: '' }]);

  if (!source) {
    box.innerHTML = `<div class="card calm"><span class="dot" style="background:var(--faint)"></span><span class="note" style="margin:0">${esc(T('bb.none'))}${reason ? ' · ' + esc(reason) : ''}</span></div>`;
    return;
  }
  if (bad) {
    box.innerHTML = `<div class="card alert"><h3><span style="color:var(--danger)">${esc(T('bb.title'))}</span><span class="chip danger ltr">${esc(reason || '?')}</span></h3>` +
      (hit >= 0 ? `<pre class="code wrap">${body.slice(Math.max(0, hit - 2), hit + 4).map(l => PANIC.test(l) ? `<span class="hit">${esc(l)}</span>` : esc(l)).join('\n')}</pre>` : '') +
      `<button class="btn ghost" id="bbShow" style="margin-top:10px">${esc(T('bb.show'))}</button></div>`;
  } else {
    box.innerHTML = `<div class="card calm"><span class="dot"></span><div style="flex:1;min-width:0"><div style="font-size:13px">${esc(T('bb.ok'))}</div>` +
      `<div class="note ltr" style="margin:0">${esc(reason || '?')}</div></div><button class="btn-s" id="bbShow">${esc(T('bb.show'))}</button></div>`;
  }
  $('#bbShow').onclick = showLog;
}

/* Live clocks, temperature and memory, once a second while the Device tab is open. */
const Cpu = {
  timer: null,
  kick() { if (!this.timer) this.tick(); },
  async tick() {
    this.timer = null;
    if (S.view !== 'device' || document.hidden) return;
    try {
      const c = await fbsJson('cpu');
      const cores = $('#cores');
      if (cores.children.length !== c.cores.length) {
        cores.style.setProperty('--n', c.cores.length);
        const top = Math.max(...c.cores.map(x => x.max || 0));
        cores.innerHTML = c.cores.map((x, n) => `<div class="core${x.max && x.max >= top && c.cores.some(y => y.max < top) ? ' big' : ''}"><div class="bar"></div><span>${n}</span></div>`).join('');
      }
      const top = Math.max(...c.cores.map(x => x.max || 0)) || 1;
      c.cores.forEach((x, n) => {
        const bar = cores.children[n].firstElementChild;
        bar.style.height = x.cur ? Math.max(4, (x.cur / top) * 100).toFixed(0) + '%' : '0';
        cores.children[n].title = x.cur ? Math.round(x.cur / 1000) + ' MHz' : 'offline';
      });
      $('#cpuTemp').textContent = c.cpu_temp == null ? '–' : celsius(c.cpu_temp, c.cpu_temp > 1000 ? 1000 : 1);
      if (c.mem_total_kb) {
        $('#memLine').textContent = `RAM ${size((c.mem_total_kb - c.mem_avail_kb) * 1024)} / ${size(c.mem_total_kb * 1024)}`;
      }
      $('#swapLine').textContent = c.swap_used_kb ? `swap ${size(c.swap_used_kb * 1024)}` : '';
    } catch { /* one missed second is fine */ }
    this.timer = setTimeout(() => this.tick(), 1000);
  },
};

/* ---------------------------------------------------------------- partitions */

const Parts = { f: 'all', q: '' };

function renderParts() {
  const p = S.parts;
  const rows = $('#partRows');
  if (!p || !p.dir) {
    rows.innerHTML = `<tr><td class="note">${esc(T('parts.none'))}</td></tr>`;
    $('#partCount').textContent = '';
    return;
  }
  const q = Parts.q.toLowerCase();
  const list = p.parts.filter(x =>
    (Parts.f === 'all' || x.cat === Parts.f || (Parts.f === 'other' && !['critical', 'boot'].includes(x.cat))) &&
    (!q || x.name.toLowerCase().includes(q)));
  rows.innerHTML = list.map(x => {
    const tag = { critical: ['warn', T('cat.critical')], boot: ['info', T('cat.boot')], super: ['', 'super'], never: ['danger', T('cat.never')] }[x.cat];
    return `<tr><td><div class="pn">${esc(x.name)}</div><div class="pd">${esc(x.dev)}</div></td>` +
      `<td class="pt">${tag ? `<span class="chip ${tag[0]}">${esc(tag[1])}</span>` : ''}</td><td class="ps">${size(sectors(x.sectors))}</td></tr>`;
  }).join('');
  $('#partCount').textContent = T('parts.count', list.length, p.parts.length, p.dir);
}

$('#partQ').addEventListener('input', e => { Parts.q = e.target.value.trim(); renderParts(); });
$$('#partF .fbtn').forEach(b => b.addEventListener('click', () => {
  Parts.f = b.dataset.f;
  $$('#partF .fbtn').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
  renderParts();
}));

const SUPER_COLORS = ['#3DD6C4', '#7FA7F5', '#B39CF0', '#F0B341', '#F2615C', '#5BD97A', '#E58FD0', '#9AA6B6'];

function renderSuper(s) {
  let total = 0, list = [];
  if (s.source === 'lpdump') {
    total = Number(s.lp?.block_devices?.[0]?.size || 0);
    list = (s.lp?.partitions || []).map(x => ({ name: x.name, bytes: Number(x.size || 0) }));
  } else {
    total = sectors(s.super_sectors) || 0;
    list = (s.parts || []).map(x => ({ name: x.name, bytes: sectors(x.sectors) || 0 }));
  }
  if (!total && !list.length) return;
  const slot = S.info?.slot || '';
  const mine = list.filter(x => x.bytes > 0 && (!slot || !/_[ab]$/.test(x.name) || x.name.endsWith(slot))).sort((a, b) => b.bytes - a.bytes);
  const other = list.filter(x => x.bytes > 0 && !mine.includes(x)).reduce((a, x) => a + x.bytes, 0);
  const used = mine.reduce((a, x) => a + x.bytes, 0) + other;
  const segs = mine.map((x, n) => ({ ...x, c: SUPER_COLORS[n % SUPER_COLORS.length] }));
  if (other) segs.push({ name: T('super.other'), bytes: other, c: 'var(--line)' });
  $('#superBar').innerHTML = total ? segs.map(x => `<i title="${esc(x.name)}" style="width:${(x.bytes / total * 100).toFixed(2)}%;background:${x.c}"></i>`).join('') : '';
  $('#superLegend').innerHTML = segs.map(x => `<div><b style="--c:${x.c}">${esc(x.name)}</b><span>${size(x.bytes)}</span></div>`).join('');
  $('#superFree').textContent = total ? T('super.free', size(Math.max(0, total - used))) + ' / ' + size(total) : '';
  $('#superNote').textContent = s.source === 'lpdump' ? T('super.lpdump') : T('super.mapper');
  $('#superCard').hidden = false;
}

/* ---------------------------------------------------------------- logs */

const AVC = /avc:\s+denied\s+\{([^}]+)\}.*?scontext=(\S+).*?tcontext=(\S+).*?tclass=(\S+)/;

function avcOf(line) {
  const m = line.match(AVC);
  if (!m) return null;
  const type = ctx => ctx.split(':')[2] || ctx;
  return { s: type(m[2]), t: type(m[3]), c: m[4], perms: m[1].trim().split(/\s+/), permissive: /permissive=1/.test(line) };
}
const permSet = p => (p.length > 1 ? `{ ${p.join(' ')} }` : p[0]);
const ruleOf = a => `allow ${a.s} ${a.t} ${a.c} ${permSet(a.perms)}`;
const teOf = a => `allow ${a.s} ${a.t}:${a.c} ${permSet(a.perms)};`;

const LEVEL_APP = /^\d\d-\d\d \d\d:\d\d:\d\d\.\d+\s+\d+\s+\d+\s+([VDIWEF])\s/;
function classify(src, text) {
  if (/avc:\s+denied/.test(text)) return 's';
  if (src === 'app') {
    const m = text.match(LEVEL_APP);
    return m ? (m[1] === 'E' || m[1] === 'F' ? 'e' : m[1] === 'W' ? 'w' : '') : '';
  }
  if (/panic|oops|BUG:|\berror\b|\bfail(ed|ure)?\b|fatal|segfault/i.test(text)) return 'e';
  if (/\bwarn(ing)?\b|throttl|lowmemorykiller|\bkill(ed|ing)?\b|timeout|denied/i.test(text)) return 'w';
  return '';
}

const Log = {
  src: 'kernel',
  lines: { kernel: [], app: [] },
  lvl: 'all',
  q: '',
  paused: false,
  timer: null,
  busy: false,
  MAX: 3000,

  kick() { if (!this.timer && !this.busy) this.poll(); else this.render(); },

  match(l) {
    if (l.gap) return this.lvl === 'all' && !this.q;
    return (this.lvl === 'all' || l.c === this.lvl) && (!this.q || l.text.toLowerCase().includes(this.q));
  },
  html(l) {
    if (l.gap) return `<p class="gap">··· ${esc(T('log.gap'))} ···</p>`;
    return `<p class="${l.c}">${esc(l.text)}</p>`;
  },
  render() {
    const box = $('#logBox');
    const list = this.lines[this.src].filter(l => this.match(l));
    box.innerHTML = list.length ? list.slice(-1500).map(l => this.html(l)).join('') : `<p class="empty">${esc(T('log.empty'))}</p>`;
    box.scrollTop = box.scrollHeight;
    this.updateRules();
  },

  async poll() {
    this.timer = null;
    if (S.view !== 'log' || this.paused || document.hidden) return;
    this.busy = true;
    const src = this.src;
    const arr = this.lines[src];
    const last = arr.length ? arr[arr.length - 1] : null;
    try {
      let args;
      if (src === 'kernel') args = ['log', 'kernel', '400'];
      else args = ['log', 'app', last && last.t ? last.t : '300'];
      const batch = (await fbs(...args)).split('\n').filter(Boolean);
      let start = 0;
      if (last) {
        const i = batch.lastIndexOf(last.text);
        if (i >= 0) start = i + 1;
        else if (batch.length) arr.push({ gap: true });
      }
      const fresh = batch.slice(start).map(text => ({
        text, c: classify(src, text), t: src === 'app' && /^\d\d-\d\d \d\d:/.test(text) ? text.slice(0, 18) : null,
      }));
      if (fresh.length && src === this.src) {
        arr.push(...fresh);
        if (arr.length > this.MAX) arr.splice(0, arr.length - this.MAX);
        this.append(fresh);
      }
    } catch { /* try again next second */ }
    this.busy = false;
    this.timer = setTimeout(() => this.poll(), 1000);
  },

  append(fresh) {
    const box = $('#logBox');
    const atEnd = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
    const shown = fresh.filter(l => this.match(l));
    if (!shown.length) return this.updateRules();
    box.querySelector('.empty')?.remove();
    box.insertAdjacentHTML('beforeend', shown.map(l => this.html(l)).join(''));
    while (box.childElementCount > 1500) box.firstElementChild.remove();
    if (atEnd) box.scrollTop = box.scrollHeight;
    this.updateRules();
  },

  rules() {
    const merged = new Map();
    for (const src of ['kernel', 'app']) {
      for (const l of this.lines[src]) {
        if (l.c !== 's') continue;
        const a = avcOf(l.text);
        if (!a) continue;
        const key = `${a.s} ${a.t} ${a.c}`;
        const m = merged.get(key) || { ...a, perms: [] };
        a.perms.forEach(p => { if (!m.perms.includes(p)) m.perms.push(p); });
        merged.set(key, m);
      }
    }
    return [...merged.values()];
  },
  updateRules() { $('#rulesBtn').textContent = T('log.rules', this.rules().length); },
};

$('#srcKernel').onclick = () => switchSource('kernel');
$('#srcApp').onclick = () => switchSource('app');
function switchSource(src) {
  Log.src = src;
  $('#srcKernel').setAttribute('aria-pressed', String(src === 'kernel'));
  $('#srcApp').setAttribute('aria-pressed', String(src === 'app'));
  Log.render();
  clearTimeout(Log.timer);
  Log.timer = null;
  if (!Log.busy) Log.poll();
}
$('#logQ').addEventListener('input', e => { Log.q = e.target.value.trim().toLowerCase(); Log.render(); });
$$('#logF .fbtn[data-l]').forEach(b => b.addEventListener('click', () => {
  Log.lvl = b.dataset.l;
  $$('#logF .fbtn[data-l]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
  Log.render();
}));
$('#logPause').onclick = e => {
  Log.paused = !Log.paused;
  e.currentTarget.setAttribute('aria-pressed', String(Log.paused));
  e.currentTarget.textContent = T(Log.paused ? 'log.resume' : 'log.pause');
  if (!Log.paused) Log.kick();
};
$('#logBox').addEventListener('click', e => {
  const p = e.target.closest('p.s');
  if (!p) return;
  const a = avcOf(p.textContent);
  if (!a) return;
  sheet(T('avc.title'),
    `<pre class="code wrap">${esc(p.textContent)}</pre>` +
    `<p class="note">${esc(T('avc.rule'))}</p><pre class="code">${esc(ruleOf(a))}</pre>` +
    `<p class="note">${esc(T('avc.te'))}</p><pre class="code">${esc(teOf(a))}</pre>` +
    (a.permissive ? `<p class="note">${esc(T('avc.permissive'))}</p>` : '') +
    `<p class="note warn">${esc(T('avc.warn'))}</p>`,
    [{ label: T('copy'), onClick: () => copy(ruleOf(a)) }, { label: T('close'), kind: '' }]);
});
$('#rulesBtn').onclick = () => {
  const rules = Log.rules();
  const text = rules.map(ruleOf).join('\n');
  sheet(T('avc.all'),
    rules.length ? `<pre class="code">${esc(text)}</pre><p class="note warn">${esc(T('avc.warn'))}</p>` : `<p class="note">${esc(T('avc.none'))}</p>`,
    rules.length ? [{ label: T('copy'), onClick: () => copy(text) }, { label: T('close'), kind: '' }] : [{ label: T('close'), kind: '' }]);
};

/* ---------------------------------------------------------------- backup */

// The same choices fbs makes in backup_run, so the numbers shown match what gets copied.
function backupSet(set) {
  const p = S.parts?.parts || [];
  const slot = S.info?.slot || '';
  return p.filter(x => {
    if (x.cat === 'never' || x.sectors == null) return false;
    if (set === 'critical') return x.cat === 'critical';
    if (set === 'boot') return x.cat === 'boot' && (!slot || !/_[ab]$/.test(x.name) || x.name.endsWith(slot));
    return true;
  });
}

function renderSets() {
  const names = l => iso(l.slice(0, 5).map(x => x.name).join(', ') + (l.length > 5 ? '…' : ''));
  const sum = l => T('set.sum', l.length, size(l.reduce((a, x) => a + sectors(x.sectors), 0)));
  const c = backupSet('critical'), b = backupSet('boot'), f = backupSet('full');
  $('#setCritical').textContent = `${T('set.desc.critical', names(c))} · ${sum(c)}`;
  $('#setBoot').textContent = `${T('set.desc.boot', names(b), iso(S.info?.slot || ''))} · ${sum(b)}`;
  $('#setFull').textContent = `${T('set.desc.full')} · ${sum(f)}`;
}

function backupError(ev) {
  if (ev.msg === 'space') return T('err.space', size(ev.need_kb * 1024), size(ev.free_kb * 1024));
  if (ev.msg === 'storage') return T('err.storage', '/sdcard/FastbootStudio');
  const key = 'err.' + ev.msg;
  return T(key) === key ? T('err.generic', ev.msg) : T(key);
}

let backupRunning = false;
$('#backupGo').onclick = () => {
  if (backupRunning) return;
  const set = $('input[name="set"]:checked').value;
  if (set === 'full') {
    const f = backupSet('full');
    sheet(T('backup.confirm'), `<p class="note">${esc(T('backup.confirmBody', f.length, size(f.reduce((a, x) => a + sectors(x.sectors), 0)), '/sdcard/FastbootStudio/Backups'))}</p>`,
      [{ label: T('cancel') }, { label: T('backup.start'), kind: '', onClick: () => { closeSheet(); runBackup(set); } }]);
  } else {
    runBackup(set);
  }
};

async function runBackup(set) {
  backupRunning = true;
  const go = $('#backupGo');
  go.disabled = true;
  go.textContent = T('backup.running');
  const rows = $('#progRows');
  rows.innerHTML = '';
  $('#progCard').hidden = false;
  $('#progBar').style.width = '0';
  let plan = null, doneKb = 0, saved = 0;
  const row = name => rows.querySelector(`[data-n="${CSS.escape(name)}"] .st`);
  try {
    await Bridge.spawn(['backup', set], line => {
      let ev;
      try { ev = JSON.parse(line); } catch { return; }
      if (ev.event === 'error') {
        toast(backupError(ev));
        $('#progCard').hidden = true;
      } else if (ev.event === 'plan') {
        plan = ev;
        $('#progTitle').textContent = ev.folder;
        $('#progCount').textContent = `0 / ${ev.count}`;
      } else if (ev.event === 'start') {
        rows.insertAdjacentHTML('afterbegin', `<div class="prow" data-n="${esc(ev.name)}"><span class="pn">${esc(ev.name)}.img</span><span class="st">${size(ev.kb * 1024)}…</span></div>`);
        ev.kb && (row(ev.name).dataset.kb = ev.kb);
      } else if (ev.event === 'done' || ev.event === 'fail') {
        const st = row(ev.name);
        if (st) {
          doneKb += Number(st.dataset.kb || 0);
          st.textContent = ev.event === 'done' ? '✓ ' + size(Number(ev.bytes)) : '✗';
          st.className = 'st ' + (ev.event === 'done' ? 'ok' : 'bad');
          if (ev.event === 'fail') st.title = ev.msg;
        }
        if (ev.event === 'done') saved++;
        if (plan) {
          $('#progCount').textContent = `${rows.childElementCount} / ${plan.count}`;
          $('#progBar').style.width = (plan.kb ? (doneKb / plan.kb) * 100 : 0).toFixed(1) + '%';
        }
      } else if (ev.event === 'finish') {
        $('#progBar').style.width = '100%';
        toast(T('backup.done', ev.saved) + (ev.failed ? ' · ' + T('backup.failed', ev.failed) : ''));
      }
    });
  } catch (e) {
    toast(T('err.generic', e.message || e));
  }
  backupRunning = false;
  go.disabled = false;
  go.textContent = T('backup.start');
  if (saved) loadBackups();
}

async function loadBackups() {
  const list = $('#backupList');
  try {
    const b = await fbsJson('backups');
    $('#backupRoot').textContent = b.root;
    if (!b.items.length) {
      list.innerHTML = `<p class="note">${esc(T('backup.none'))}</p>`;
      return;
    }
    list.innerHTML = b.items.map(x => `<div class="bitem" data-name="${esc(x.name)}"><span class="p">${esc(x.name)}/</span>` +
      `<button class="btn-s"${x.sums ? '' : ' disabled'}>${esc(T('backup.verify'))}</button>` +
      `<span class="m">${esc(T('backup.files', x.files, x.kb == null ? '–' : size(x.kb * 1024)))}</span></div>`).join('');
  } catch (e) {
    list.innerHTML = `<p class="note">${esc(T('err.generic', e.message || e))}</p>`;
  }
}

$('#backupList').addEventListener('click', async e => {
  const btn = e.target.closest('button');
  if (!btn || btn.disabled) return;
  const item = btn.closest('.bitem');
  const meta = item.querySelector('.m');
  btn.disabled = true;
  btn.textContent = T('backup.verifying');
  let result = null;
  const bad = [];
  try {
    await Bridge.spawn(['verify', item.dataset.name], line => {
      let ev;
      try { ev = JSON.parse(line); } catch { return; }
      if (ev.event === 'file' && ev.state !== 'ok') bad.push(ev.name);
      if (ev.event === 'finish') result = ev;
    });
  } catch { /* shown as no result below */ }
  btn.disabled = false;
  btn.textContent = T('backup.verify');
  if (!result) return toast(T('err.generic', 'verify'));
  meta.innerHTML = result.bad
    ? `<span style="color:var(--danger)">✗ ${esc(T('backup.bad', result.bad))}: ${esc(bad.join(', '))}</span>`
    : `<span style="color:var(--ok)">✓ ${esc(T('backup.ok', result.ok))}</span>`;
});

/* ---------------------------------------------------------------- tools */

function renderTools() {
  const i = S.info;
  const targets = [
    ['bootloader', 'Bootloader', 'reboot bootloader', true, ''],
    ['fastboot', 'fastbootd', 'reboot fastboot', i.dynamic, T('reboot.fastbootd')],
    ['recovery', 'Recovery', 'reboot recovery', true, ''],
    ['edl', 'EDL', 'reboot edl', i.soc === 'qualcomm', T('reboot.edl')],
  ];
  $('#rebootGrid').innerHTML = targets.map(([id, name, cmd, ok, why]) =>
    `<button class="rbtn" data-r="${id}"${ok ? '' : ' disabled'}><b>${name}</b><small class="ltr">${esc(ok ? cmd : why)}</small></button>`).join('');
  kv($('#aboutKv'), [
    [T('about.version'), 'v' + i.fbs + (i.channel === 'beta' ? ' · ' + T('beta') : '')],
    [T('about.backups'), '/sdcard/FastbootStudio/Backups'],
  ]);
}

$('#rebootGrid').addEventListener('click', e => {
  const b = e.target.closest('button[data-r]');
  if (!b || b.disabled) return;
  const name = b.querySelector('b').textContent;
  sheet(T('reboot.ask', name), `<p class="note">${esc(T('reboot.body'))}</p>`, [
    { label: T('cancel') },
    { label: T('reboot.go'), kind: 'danger', onClick: async () => { closeSheet(); try { await fbs('reboot', b.dataset.r); } catch (err) { toast(T('err.generic', err.message)); } } },
  ]);
});

$('#bundleGo').onclick = async e => {
  const btn = e.currentTarget;
  btn.disabled = true;
  btn.textContent = T('bundle.making');
  try {
    const r = await fbsJson(...($('#redact').checked ? ['bundle'] : ['bundle', 'plain']));
    $('#bundleOut').textContent = r.ok ? T('bundle.saved', r.file) : T('err.generic', r.msg);
  } catch (err) {
    $('#bundleOut').textContent = T('err.generic', err.message || err);
  }
  btn.disabled = false;
  btn.textContent = T('bundle.go');
};

// A saved choice, or one forced from the address (?lang=ar, ?theme=light) for previews.
function readPref(key, allowed) {
  const forced = new URLSearchParams(location.search).get(key);
  if (allowed.includes(forced)) return forced;
  try {
    const v = localStorage.getItem('fbs.' + key);
    return allowed.includes(v) ? v : 'auto';
  } catch { return 'auto'; }
}
function savePref(key, value) {
  try { localStorage.setItem('fbs.' + key, value); } catch { /* per-session only */ }
}
const readLang = () => readPref('lang', ['auto', 'ar', 'en']);
$$('#langSeg button').forEach(b => b.addEventListener('click', () => {
  savePref('lang', b.dataset.lang);
  setLang(b.dataset.lang);
}));
function setLang(choice) {
  i18n.pick(choice);
  $$('#langSeg button').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.lang === choice)));
  $('#logPause').textContent = T(Log.paused ? 'log.resume' : 'log.pause');
  if (S.info) { renderDevice(); renderTools(); loadBlackBox().catch(() => {}); }
  if (S.parts) { renderParts(); renderSets(); }
  if (S.super) renderSuper(S.super);
  Log.updateRules();
  Log.render();
  loadBackups();
  renderLinks();
  setTheme(Theme.choice);
}

/* ---------------------------------------------------------------- day and night */

// auto follows the phone; dark and light stick. data-dark tells the header button which
// icon to show (what a tap switches to).
const Theme = {
  choice: 'auto',
  media: matchMedia('(prefers-color-scheme: light)'),
  dark() {
    const t = document.documentElement.dataset.theme;
    return t ? t === 'dark' : !this.media.matches;
  },
};
function setTheme(choice) {
  Theme.choice = choice;
  const root = document.documentElement;
  if (choice === 'auto') delete root.dataset.theme; else root.dataset.theme = choice;
  root.dataset.dark = Theme.dark() ? '1' : '0';
  $$('#themeSeg button').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.theme === choice)));
  const btn = $('#themeBtn');
  btn.title = btn.ariaLabel = T(Theme.dark() ? 'theme.toLight' : 'theme.toDark');
}
Theme.media.addEventListener('change', () => setTheme(Theme.choice));
$('#themeBtn').addEventListener('click', () => {
  const next = Theme.dark() ? 'light' : 'dark';
  savePref('theme', next);
  setTheme(next);
});
$$('#themeSeg button').forEach(b => b.addEventListener('click', () => {
  savePref('theme', b.dataset.theme);
  setTheme(b.dataset.theme);
}));

/* ---------------------------------------------------------------- links */

// An entry with an empty url is not shown.
const LINKS = [
  { id: 'app', url: 'https://github.com/ifoknr/FastbootStudio/releases/latest', icon: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>' },
  { id: 'group', url: 'https://t.me/BeNeXTBrO', icon: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><path d="M16 4.5a3 3 0 0 1 0 6M18 14.5c1.8.8 3 2.7 3 5.5"/>' },
  { id: 'dm', url: 'https://t.me/IFOKNR1', icon: '<path d="M21 4 3 11l7 2.5L12.5 21 21 4z"/><path d="m10 13.5 4.5-4.5"/>' },
  { id: 'source', url: 'https://github.com/ifoknr/FastbootStudio-Companion', icon: '<path d="m8 8-4 4 4 4M16 8l4 4-4 4M13.5 5l-3 14"/>' },
];
function renderLinks() {
  const html = LINKS.filter(l => l.url).map(l =>
    `<button class="lbtn" type="button" data-url="${esc(l.url)}"><svg viewBox="0 0 24 24">${l.icon}</svg>` +
    `<span><b>${esc(T('links.' + l.id))}</b><small>${esc(l.url.replace(/^https:\/\//, ''))}</small></span></button>`).join('');
  $$('[data-links]').forEach(el => { el.innerHTML = html; });
}
// The root manager's WebView keeps links inside itself, so hand them to Android instead:
// Telegram links open Telegram, the rest the browser.
document.addEventListener('click', async e => {
  const b = e.target.closest('.lbtn[data-url]');
  if (!b) return;
  const url = b.dataset.url;
  if (window.FBS_DEMO) { window.open(url, '_blank', 'noopener'); return; }
  try {
    const r = JSON.parse(await fbs('open', url));
    if (!r.ok) throw new Error(r.msg);
  } catch {
    copy(url);
  }
});

/* ---------------------------------------------------------------- fit */

// The log box fills the screen: the header and, on phones, the bottom tab bar come off.
function fit() {
  const nav = $('.nav');
  const bottomBar = nav.getBoundingClientRect().width > nav.getBoundingClientRect().height;
  const chrome = $('.appbar').offsetHeight + (bottomBar ? nav.offsetHeight : 0);
  document.documentElement.style.setProperty('--chrome', chrome + 'px');
}
addEventListener('resize', fit);

/* ---------------------------------------------------------------- start */

document.addEventListener('visibilitychange', () => {
  if (document.hidden) return;
  if (S.view === 'device') Cpu.kick();
  if (S.view === 'log') Log.kick();
});

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = src;
    s.onload = resolve;
    s.onerror = reject;
    document.head.append(s);
  });
}

async function start() {
  const first = location.hash.slice(1);
  if (typeof ksu === 'undefined') {
    // Only for previews in a browser: the module zip leaves demo.js out, so a WebUI host
    // without the bridge gets the error card below rather than made-up data.
    try {
      await loadScript('demo.js');
      window.FBS_DEMO = true;
    } catch { /* fbs() fails next and the error card shows */ }
  }
  Theme.choice = readPref('theme', ['auto', 'dark', 'light']);
  setLang(readLang());
  fit();
  if (window.FBS_DEMO) toast(T('demo'));
  try {
    S.info = await fbsJson('info');
  } catch {
    $('#v-device').innerHTML = `<div class="card alert"><p class="note" style="margin:0">${esc(T('err.noroot'))}</p></div>`;
    return;
  }
  renderDevice();
  renderTools();
  Cpu.kick();
  loadBlackBox().catch(() => {});
  if (['parts', 'log', 'backup', 'tools'].includes(first)) show(first);
  try {
    S.parts = await fbsJson('parts');
    renderParts();
    renderSets();
  } catch { /* the Partitions tab shows the empty state */ }
  try {
    S.super = await fbsJson('super');
    renderSuper(S.super);
  } catch { /* no super card */ }
}

start();
