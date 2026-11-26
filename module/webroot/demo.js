'use strict';
// A stand-in for the root manager's bridge when index.html is opened in a plain browser:
// a made-up MediaTek phone that answers like bin/fbs does. Never loaded on a real phone,
// where window.ksu already exists.

(() => {
  const S = 512;
  const parts = [
    ['preloader_raw', 'mmcblk0boot0', 4 * 2048, 'critical'],
    ['lk_a', 'mmcblk0p20', 2 * 2048, 'critical'], ['lk_b', 'mmcblk0p21', 2 * 2048, 'critical'],
    ['nvram', 'mmcblk0p10', 64 * 2048, 'critical'], ['nvdata', 'mmcblk0p11', 64 * 2048, 'critical'],
    ['nvcfg', 'mmcblk0p12', 32 * 2048, 'critical'], ['protect1', 'mmcblk0p13', 8 * 2048, 'critical'],
    ['protect2', 'mmcblk0p14', 8 * 2048, 'critical'], ['seccfg', 'mmcblk0p15', 8 * 2048, 'critical'],
    ['persist', 'mmcblk0p16', 48 * 2048, 'critical'], ['md1img_a', 'mmcblk0p24', 100 * 2048, 'critical'],
    ['boot_a', 'mmcblk0p30', 32 * 2048, 'boot'], ['boot_b', 'mmcblk0p31', 32 * 2048, 'boot'],
    ['init_boot_a', 'mmcblk0p32', 8 * 2048, 'boot'], ['init_boot_b', 'mmcblk0p33', 8 * 2048, 'boot'],
    ['vendor_boot_a', 'mmcblk0p34', 64 * 2048, 'boot'], ['vendor_boot_b', 'mmcblk0p35', 64 * 2048, 'boot'],
    ['dtbo_a', 'mmcblk0p36', 8 * 2048, 'boot'], ['dtbo_b', 'mmcblk0p37', 8 * 2048, 'boot'],
    ['vbmeta_a', 'mmcblk0p38', 8 * 2048, 'boot'], ['vbmeta_b', 'mmcblk0p39', 8 * 2048, 'boot'],
    ['metadata', 'mmcblk0p17', 32 * 2048, 'other'], ['misc', 'mmcblk0p18', 1 * 2048, 'other'],
    ['super', 'mmcblk0p45', 9 * 1024 * 2048, 'super'], ['userdata', 'mmcblk0p50', 112 * 1024 * 2048, 'never'],
  ];

  const info = {
    fbs: '2.5.3', channel: 'stable', model: 'Demo Phone', brand: 'Demo', device: 'demo', product: 'demo_mt6789',
    android: '14', sdk: '34', patch: '2026-08-05', build: 'DEMO-14.0.1', platform: 'mt6789', soc: 'mediatek',
    arch: 'arm64-v8a', slot: '_a', dynamic: true, treble: true, vndk: '34',
    boot: { vbstate: 'orange', device_state: 'unlocked', locked: false, spoofed: true, bootloader_word: 'unlocked', root_contradicts: false },
    kernel: '5.15.148-android13-8-00017-gabc123', kmi: '5.15-android13', selinux: 'Enforcing', root: 'KernelSU', root_also: '',
    boot_reason: 'kernel_panic',
    battery: { level: 78, health: 91, cycles: 312, temp_dc: 334 },
    memory: { total_kb: 7864320, avail_kb: 2725000 },
    storage: { type: 'emmc', life_a: '0x02', life_b: '0x01', eol: '0x01' },
  };

  const lp = {
    partitions: [
      ['system_a', 3.21], ['product_a', 1.62], ['system_ext_a', 0.94], ['vendor_a', 0.71],
      ['vendor_dlkm_a', 0.05], ['odm_a', 0.004], ['system_b', 0], ['vendor_b', 0],
    ].map(([name, g]) => ({ name, group_name: 'main' + name.slice(-2), is_dynamic: true, size: String(Math.round(g * 1073741824)) })),
    block_devices: [{ name: 'super', first_sector: '2048', size: String(9 * 1073741824), block_size: 4096 }],
    groups: [{ name: 'main_a', maximum_size: '9659482112' }, { name: 'main_b', maximum_size: '9659482112' }],
  };

  const kernelPool = [
    'healthd: battery l=78 v=4012 t=33.4 h=2 st=3 c=-412',
    'mtk_charger: chg_type=SDP vbus=4980mV ibus=480mA',
    'thermal: zone[cpu-0-0] temp=47900 trip=0',
    'avc: denied { read } for comm="system_server" name="cmdline" dev="proc" ino=4026531842 scontext=u:r:system_server:s0 tcontext=u:r:init:s0 tclass=file permissive=0',
    'lowmemorykiller: Kill \'com.example.game\' (8342), adj 900, to free 182340kB',
    'usb: [USB] DEVICE STATE: CONFIGURED',
    'EXT4-fs (dm-48): mounted filesystem with ordered data mode',
    'binder: 1452:1503 transaction failed 29189/-22, size 0-0 line 3093',
    'F2FS-fs (dm-50): checkpoint=enable has some unwritten data, warning',
    'wlan: [WLAN] RSSI -58 dBm, link speed 433 Mbps',
    'init: Service \'vendor.demo-hal\' (pid 902) exited with status 1, error',
    'avc: denied { getattr search } for comm="ksud" path="/data/adb" dev="dm-50" scontext=u:r:su:s0 tcontext=u:object_r:adb_data_file:s0 tclass=dir permissive=1',
    'cpufreq: policy6 target 2200000 kHz',
    'thermal: zone[battery] temp=41200 trip=1 throttling',
  ];
  const appPool = [
    'I ActivityManager: Start proc 8342:com.example.game/u0a212',
    'I WindowManager: Changing focus to Window{ok com.android.launcher3}',
    'W PackageManager: Unknown permission demo.permission.X in package com.example',
    'E AndroidRuntime: FATAL EXCEPTION: main java.lang.NullPointerException',
    'I KernelSU: webui loaded fastboot_studio_companion',
    'D ConnectivityService: NetworkAgentInfo [WIFI] validation passed',
    'W BatteryStats: battery temperature 41.2C, throttling',
  ];
  const kernel = [];
  const app = [];
  let kt = 800, at = Date.UTC(2026, 9, 9, 18, 14, 2);
  const pad = (n, w = 2) => String(n).padStart(w, '0');
  function grow() {
    for (let i = 0; i < 1 + Math.random() * 3; i++) {
      kt += 0.05 + Math.random() * 0.5;
      kernel.push(`[${kt.toFixed(6).padStart(12)}] ${kernelPool[Math.floor(Math.random() * kernelPool.length)]}`);
      at += 80 + Math.random() * 700;
      const d = new Date(at);
      const msg = appPool[Math.floor(Math.random() * appPool.length)];
      app.push(`${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}.${pad(d.getUTCMilliseconds(), 3)}  1452  1503 ${msg}`);
    }
  }
  for (let i = 0; i < 60; i++) grow();
  setInterval(grow, 900);

  const backups = [
    { name: 'Demo_Phone_DEMO0123456789_20260921-184012', files: 11, kb: 352256, sums: true, tar: false },
    { name: 'Demo_Phone_DEMO0123456789_20260830-091233', files: 4, kb: 114688, sums: true, tar: false },
  ];

  const last = `#reason=kernel_panic
#source=/sys/fs/pstore/console-ramoops-0
[ 4211.118200] binder: 1452:1503 transaction failed 29189/-22
[ 4211.120100] mtk_demo_hal: request_irq failed: -16
[ 4211.120380] Unable to handle kernel NULL pointer dereference at virtual address 0000000000000008
[ 4211.120391] Mem abort info:
[ 4211.120400] Internal error: Oops: 96000005 [#1] PREEMPT SMP
[ 4211.120612] pc : demo_sensor_poll+0x40/0x120 [demo_sensor]
[ 4211.121800] Kernel panic - not syncing: Fatal exception
[ 4211.121812] SMP: stopping secondary CPUs
[ 4211.130000] Rebooting in 5 seconds..`;

  function answer(args) {
    const [cmd, a1, a2] = args;
    switch (cmd) {
      case 'info': return JSON.stringify(info);
      case 'parts': return JSON.stringify({ dir: '/dev/block/platform/bootdevice/by-name', slot: '_a', parts: parts.map(([name, dev, sectors, cat]) => ({ name, dev, sectors, cat, sure: true })) });
      case 'super': return JSON.stringify({ source: 'lpdump', slot: '_a', lp });
      case 'cpu': return JSON.stringify({
        cores: Array.from({ length: 8 }, (_, n) => { const max = n < 6 ? 2000000 : 2200000; return { cur: Math.round((500000 + Math.random() * (max - 500000)) / 100000) * 100000, max }; }),
        cpu_temp: Math.round(45000 + Math.random() * 5000), battery_temp_dc: 334, mem_total_kb: 7864320,
        mem_avail_kb: Math.round(2600000 + Math.random() * 300000), swap_used_kb: 1258292,
      });
      case 'log': {
        if (a1 === 'kernel') return kernel.slice(-(Number(a2) || 300)).join('\n') + '\n';
        if (/^\d+$/.test(a2 || '300')) return app.slice(-(Number(a2) || 300)).join('\n') + '\n';
        return app.filter(l => l.slice(0, 18) >= a2).join('\n') + '\n';
      }
      case 'last': return last + '\n';
      case 'backups': return JSON.stringify({ root: '/sdcard/FastbootStudio/Backups', free_kb: 48 * 1048576, items: backups });
      case 'bundle': return JSON.stringify({ ok: true, file: '/sdcard/FastbootStudio/Reports/companion-report_20261009-211407.tar.gz', redacted: a1 !== 'plain' });
      case 'reboot': return JSON.stringify({ ok: true });
      case 'open': return JSON.stringify({ ok: true });
      // As on a phone where MediaStore gives no address for the file: not shared, path given.
      case 'share': return JSON.stringify(query.get('share') === 'ok' ? { ok: true, file: a1, uri: 'content://media/external/file/4711' } : { ok: false, msg: 'no-uri', file: a1 });
      case 'modules': return JSON.stringify(modules);
      case 'delete': {
        const i = backups.findIndex(x => x.name === a1);
        if (i < 0) return JSON.stringify({ ok: false, msg: 'missing' });
        backups.splice(i, 1);
        return JSON.stringify({ ok: true, folder: a1 });
      }
      default: return '';
    }
  }

  // ?slow=1 gives each step of a long job a second or so, so a state can be looked at (and
  // photographed) while it lasts; ?share=ok makes the share sheet "open".
  const query = new URLSearchParams(location.search);
  const slow = query.get('slow') ? 6 : 1;

  function events(args) {
    // Anything else is what a shell would make of arguments that were not quoted: no job.
    if (!['verify', 'archive'].includes(args[0]) && !(args[0] === 'backup' && ['critical', 'boot', 'full', 'custom'].includes(args[1]))) return null;
    if (args[0] === 'verify') {
      const b = backups.find(x => x.name === args[1]);
      if (!b) return [{ event: 'error', msg: 'no-sums' }];
      const n = b.files, each = Math.round(b.kb / n);
      const out = [{ event: 'plan', count: n, kb: each * n }];
      for (let i = 0; i < n; i++) out.push({ event: 'start', name: `part${i}.img`, kb: each }, { event: 'file', name: `part${i}.img`, state: 'ok' });
      return [...out, { event: 'finish', ok: n, bad: 0 }];
    }
    if (args[0] === 'archive') {
      const b = backups.find(x => x.name === args[1]);
      if (!b) return [{ event: 'error', msg: 'missing' }];
      const file = `/sdcard/FastbootStudio/Backups/${b.name}.tar`;
      const out = [{ event: 'plan', file, count: b.files + 2, kb: b.kb }];
      for (let i = 1; i <= 4; i++) out.push({ event: 'progress', name: b.name, bytes: String(Math.round(b.kb * 1024 * i / 4)), of: '' });
      b.tar = true;
      return [...out, { event: 'finish', file, files: b.files + 2, kb: b.kb + 20 }];
    }
    const set = args[1];
    const slot = info.slot;
    // The same refusals as backup_run: a name it does not know, or one it never copies.
    if (set === 'custom') {
      const bad = args.slice(2).find(n => !parts.some(([p, , , c]) => p === n && c !== 'never'));
      if (bad !== undefined) return [{ event: 'error', msg: 'bad-name', name: bad }];
      if (args.length < 3) return [{ event: 'error', msg: 'nothing' }];
    }
    const list = parts.filter(([n, , , c]) => c !== 'never' && (set === 'full' || (set === 'critical' && c === 'critical') ||
      (set === 'custom' && args.slice(2).includes(n)) ||
      (set === 'boot' && c === 'boot' && (!/_[ab]$/.test(n) || n.endsWith(slot)))));
    const folder = 'Demo_Phone_DEMO0123456789_20261009-211407';
    const out = [{ event: 'plan', set, folder, count: list.length, kb: list.reduce((a, p) => a + p[2] / 2, 0) }];
    list.forEach(([name, , sec]) => {
      out.push({ event: 'start', name, kb: sec / 2 });
      // 32 MiB and up: progress about once a second while it copies, as fbs reports it.
      if (sec >= 65536) {
        const steps = sec >= 4194304 ? 8 : 2;
        for (let i = 1; i <= steps; i++) out.push({ event: 'progress', name, bytes: String(Math.round(sec * S * i / steps)), of: String(sec * S) });
      }
      out.push({ event: 'hash', name });
      out.push({ event: 'done', name, bytes: String(sec * S), sha256: 'demo' });
    });
    out.push({ event: 'finish', folder, saved: list.length, failed: 0 });
    backups.unshift({ name: folder, files: list.length, kb: out[0].kb, sums: true, tar: false });
    return out;
  }

  const m = (id, name, version, extra) => ({ id, name, version, author: 'demo', enabled: true, removing: false, mount: true, files: 0, props: 0, scripts: [], webui: false, action: false, ...extra });
  const modules = {
    root: '/data/adb/modules',
    modules: [
      m('fastboot_studio_companion', 'Fastboot Studio Companion', 'v2.5.3', { webui: true, action: true }),
      m('systemless_hosts', 'Systemless Hosts', 'v1.2', { files: 1 }),
      m('adblock_plus', 'AdBlock Plus', 'v4.0', { files: 1, props: 2, scripts: ['service.sh'] }),
      m('google_sans_font', 'Google Sans Font', 'v3.1', { files: 46 }),
      m('ios_emoji', 'iOS Emoji', 'v17.4', { files: 31 }),
      m('debloater', 'Debloater', 'v2.0', { files: 12, props: 1 }),
      m('youtube_vanced', 'YouTube Patched', 'v19.16', { files: 4, webui: true }),
      m('gpu_tweaks', 'GPU Tweaks', 'v1.5', { props: 3, scripts: ['post-fs-data.sh'] }),
      m('old_tweaks', 'Old Tweaks', 'v0.9', { enabled: false }),
    ],
    conflicts: [
      { kind: 'file', modules: ['adblock_plus', 'systemless_hosts'], count: 1, paths: ['/system/etc/hosts'] },
      { kind: 'file', modules: ['google_sans_font', 'ios_emoji'], count: 3, paths: ['/system/fonts/NotoColorEmoji.ttf', '/system/fonts/NotoColorEmojiFlags.ttf', '/system/etc/fonts.xml'] },
      { kind: 'replace', path: '/system/app/YouTube', by: 'debloater', modules: ['youtube_vanced'] },
      { kind: 'remove', path: '/system/etc/hosts', by: 'debloater', modules: ['adblock_plus', 'systemless_hosts'] },
      { kind: 'prop', key: 'debug.hwui.renderer', values: [{ module: 'debloater', value: 'skiagl' }, { module: 'gpu_tweaks', value: 'skiavk' }] },
    ],
  };

  const unquote = s => [...s.matchAll(/'((?:[^']|'\\'')*)'/g)].map(m => m[1].split("'\\''").join("'"));

  // For the smoke test: ?demo=backup taps "Start backup" and ?demo=verify the first "Verify",
  // so the spawn path (quoting, events, the list drawn again) is run, not only the first screen.
  // ?demo=custom picks nvram and boot_a by hand (or the names in ?pick=a,b) and backs those
  // up; ?demo=full starts the full set (its confirmation included), where super reports
  // progress for a while.
  const auto = new URLSearchParams(location.search).get('demo');
  if (['backup', 'verify', 'custom', 'full', 'archive'].includes(auto)) {
    const tap = () => {
      const b = document.querySelector('#backupList [data-act="verify"]');
      if (!b || !document.querySelector('#customRows input')) return setTimeout(tap, 100);
      if (auto === 'verify') return b.click();
      if (auto === 'archive') return document.querySelector('#backupList [data-act="archive"]').click();
      if (auto === 'custom' || auto === 'full') {
        document.querySelector(`input[name="set"][value="${auto}"]`).click();
        if (auto === 'custom') {
          document.querySelectorAll('#customRows input:checked').forEach(x => x.click());
          (query.get('pick') || 'nvram,boot_a').split(',').forEach(n => document.querySelector(`#customRows input[value="${n}"]`).click());
        }
      }
      document.querySelector('#backupGo').click();
      // A full backup, or a large pick, asks first.
      setTimeout(() => { if (!document.querySelector('#sheet').hidden) document.querySelector('#sheetBtns button:last-child').click(); }, 100);
    };
    setTimeout(tap, 300);
  }

  // For the smoke test: ?fontcheck=1 writes the families that really loaded on <html>.
  if (new URLSearchParams(location.search).get('fontcheck') && document.fonts) {
    // After the first screen is drawn: a font is fetched only once some text needs it.
    setTimeout(() => document.fonts.ready.then(() => {
      const got = new Set();
      document.fonts.forEach(f => { if (f.status === 'loaded') got.add(f.family.replace(/"/g, '')); });
      document.documentElement.dataset.fonts = [...got].sort().join(', ');
    }), 1500);
  }

  window.ksu = {
    exec(command, _options, cb) {
      const args = unquote(command).slice(2);
      setTimeout(() => window[cb](0, answer(args), ''), 60);
    },
    spawn(_cmd, argsJson, _options, cb) {
      // The real bridge joins the arguments with spaces into one shell line.
      const args = unquote(JSON.parse(argsJson).join(' ')).slice(1);
      const list = events(args) || [];
      let i = 0;
      const step = () => {
        const child = window[cb];
        if (!child) return;
        if (i < list.length) {
          child.stdout.emit('data', JSON.stringify(list[i++]));
          setTimeout(step, (args[0] === 'verify' ? 60 : 140) * slow);
        } else {
          child.emit('exit', 0);
        }
      };
      setTimeout(step, 200);
    },
  };
})();
