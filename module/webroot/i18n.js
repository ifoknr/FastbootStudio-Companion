'use strict';
// English and Arabic strings. Arabic is picked when the phone's language is Arabic, unless the
// user chose one in Tools. "{0}", "{1}" are filled in by t().

const STRINGS = {
  en: {
    'tab.device': 'Device', 'tab.parts': 'Partitions', 'tab.mods': 'Modules',
    'mods.title': 'Module conflicts', 'mods.count': '{0} modules · {1} on', 'mods.none': 'No conflicts',
    'mods.found': '{0} conflicts', 'mods.scan': 'Scan again', 'mods.scanning': 'Scanning…', 'mods.list': 'Installed modules',
    'mods.empty': 'No modules installed.', 'mods.files': '{0} files', 'mods.props': '{0} props',
    'mods.hint': "Finds modules that put the same system files in place, hide each other's files by replacing a whole folder, or set the same property to different values. Disabled modules are left out.",
    'conflict.file': 'Same files', 'conflict.file.body': 'These modules put the same {0} file(s) in place. Only one copy is used, so one of them may not work as intended.',
    'conflict.replace': 'Folder replaced', 'conflict.replace.body': '{0} replaces this whole folder, so what {1} adds inside it is hidden.',
    'conflict.prop': 'Same property, different values', 'conflict.prop.body': 'Only the value loaded last takes effect.',
    'conflict.more': '…and {0} more', 'flag.off': 'Off', 'flag.removing': 'Removing', 'flag.nomount': 'No mount', 'tab.log': 'Logs', 'tab.backup': 'Backup', 'tab.tools': 'Tools',
    'yes': 'yes', 'no': 'no',

    'boot.title': 'Boot and security', 'boot.bootloader': 'Bootloader', 'boot.locked': 'locked', 'boot.unlocked': 'unlocked',
    'boot.slot': 'Active slot', 'boot.layout': 'Layout', 'boot.treble': 'Treble / GSI', 'boot.none': 'none',
    'boot.spoofed': 'A hiding module changed ro.boot.verifiedbootstate. The state shown here is the one the bootloader reported.',
    'kernel.title': 'Kernel', 'kernel.version': 'Version', 'kernel.nokmi': 'not GKI', 'kernel.patch': 'Security patch',
    'kernel.android': 'Android', 'kernel.build': 'Build',

    'stat.battery': 'Battery health', 'stat.cycles': '{0} cycles · {1}', 'stat.level': 'charge {0}%',
    'stat.storage': '{0} wear', 'stat.used': 'used', 'stat.exceeded': 'past rated life',
    'stat.eol.1': 'reserve normal', 'stat.eol.2': 'reserve low', 'stat.eol.3': 'replace soon',
    'stat.ram': 'Memory', 'stat.ramfree': '{0} free of {1}',
    'cpu.title': 'CPU now',

    'bb.title': 'The last restart was not normal', 'bb.ok': 'The last restart was normal', 'bb.show': 'Show log',
    'bb.none': 'No log kept from the previous boot', 'bb.sheet': 'Previous boot',

    'parts.search': 'Search partitions', 'parts.all': 'All', 'parts.rest': 'Other', 'parts.count': '{0} of {1} · {2}',
    'parts.none': 'This phone has no /dev/block/by-name.',
    'cat.critical': 'Critical', 'cat.boot': 'Boot', 'cat.never': 'Never',
    'super.free': '{0} free', 'super.other': 'other slot', 'super.lpdump': 'From lpdump: both slots.',
    'super.mapper': 'lpdump is not available, so this shows what is mapped now (current slot only).',

    'log.kernel': 'Kernel · dmesg', 'log.app': 'Apps · logcat', 'log.search': 'search…', 'log.pause': 'Pause',
    'log.resume': 'Resume', 'log.all': 'All', 'log.errors': 'Errors', 'log.warnings': 'Warnings', 'log.rules': 'Rules ({0})',
    'log.tap': 'Tap a blue SELinux line to turn it into a sepolicy rule.', 'log.empty': 'No lines match.',
    'log.gap': 'lines skipped',
    'avc.title': 'SELinux denial', 'avc.rule': "For a module's sepolicy.rule:", 'avc.te': 'For a .te file:',
    'avc.warn': 'Allow only what you understand: every rule weakens SELinux a little.',
    'avc.permissive': 'This line was logged in permissive mode, so nothing was actually blocked.',
    'avc.all': 'All denials as rules', 'avc.none': 'No SELinux denials yet.',
    'copy': 'Copy', 'copied': 'Copied', 'close': 'Close', 'cancel': 'Cancel',

    'set.critical': 'Critical', 'set.boot': 'Boot', 'set.full': 'Full',
    'set.desc.critical': 'IMEI, calibration and boot chain: {0}', 'set.desc.boot': 'Current slot {1}: {0}',
    'set.desc.full': 'Everything except userdata', 'set.sum': '{0} partitions · {1}',
    'backup.start': 'Start backup', 'backup.running': 'Backing up…', 'backup.saved': 'Saved backups',
    'backup.format': 'Same layout as Fastboot Studio on Windows: copy the folder to your PC and check or restore it there, or check it with sha256sum -c.',
    'backup.none': 'No backups yet.', 'backup.verify': 'Verify', 'backup.verifying': 'Checking…',
    'backup.ok': 'All {0} match', 'backup.bad': '{0} changed or missing', 'backup.files': '{0} files · {1}',
    'backup.done': 'Saved {0} images', 'backup.failed': '{0} failed',
    'backup.confirm': 'Full backup', 'backup.confirmBody': 'This copies {0} partitions ({1}) to {2}. It can take several minutes.',

    'err.busy': 'A backup is already running.', 'err.space': 'Not enough space: needs {0}, {1} free.',
    'err.nothing': 'This phone has no partitions in that set.', 'err.storage': "Can't write to {0}.",
    'err.no-by-name': 'This phone has no /dev/block/by-name.', 'err.generic': 'Something went wrong: {0}',
    'err.noroot': "Can't reach the module. Open this page from your root manager's WebUI.",

    'reboot.title': 'Restart to', 'reboot.action': 'Action', 'reboot.ask': 'Restart to {0}?',
    'reboot.body': 'Open apps close and the phone restarts right away.', 'reboot.go': 'Restart',
    'reboot.edl': 'Qualcomm only', 'reboot.fastbootd': 'Dynamic partitions only',
    'bundle.title': 'Support bundle',
    'bundle.body': 'Kernel log, logcat, device info and the partition table in one file, for a bug report.',
    'bundle.redact': 'Mask IMEI, serial and MAC addresses', 'bundle.go': 'Make the file', 'bundle.making': 'Collecting…',
    'bundle.saved': 'Saved to {0}',
    'about.title': 'About', 'about.version': 'Version', 'about.backups': 'Backups', 'about.source': 'Source',
    'lang.auto': 'Auto', 'lang.title': 'Language', 'beta': 'Beta',
    'theme.title': 'Appearance', 'theme.auto': 'Auto', 'theme.dark': 'Night', 'theme.light': 'Day',
    'theme.toDark': 'Switch to night mode', 'theme.toLight': 'Switch to day mode',
    'links.app': 'Fastboot Studio for Windows', 'links.group': 'Telegram group', 'links.dm': 'Message me',
    'links.source': 'Module source',
    'demo': 'Demo data. Open this page from your root manager to see your own phone.',
  },
  ar: {
    'tab.device': 'الجهاز', 'tab.parts': 'البارتشنات', 'tab.mods': 'المودات',
    'mods.title': 'تعارض المودات', 'mods.count': '{0} مود · {1} مفعّل', 'mods.none': 'ما فيه تعارض',
    'mods.found': '{0} تعارض', 'mods.scan': 'افحص من جديد', 'mods.scanning': 'يفحص…', 'mods.list': 'المودات المثبتة',
    'mods.empty': 'ما فيه مودات مثبتة.', 'mods.files': '{0} ملف', 'mods.props': '{0} خاصية',
    'mods.hint': 'يفحص المودات اللي تحط نفس ملفات النظام، أو تخفي ملفات بعض لما تستبدل مجلد كامل، أو تحط نفس الخاصية بقيم مختلفة. المودات المعطّلة ما تنحسب.',
    'conflict.file': 'نفس الملفات', 'conflict.file.body': 'هالمودات تحط نفس الملفات ({0}). نسخة وحدة بس تشتغل، فممكن واحد منهم ما يشتغل صح.',
    'conflict.replace': 'مجلد مستبدل', 'conflict.replace.body': '{0} يستبدل هالمجلد كامل، فاللي يضيفه {1} داخله ما يبان.',
    'conflict.prop': 'نفس الخاصية بقيم مختلفة', 'conflict.prop.body': 'القيمة اللي تنحمّل آخر شي هي اللي تشتغل.',
    'conflict.more': '…و {0} غيرها', 'flag.off': 'معطّل', 'flag.removing': 'بينحذف', 'flag.nomount': 'بدون تركيب', 'tab.log': 'اللوق', 'tab.backup': 'باك أب', 'tab.tools': 'أدوات',
    'yes': 'نعم', 'no': 'لا',

    'boot.title': 'الإقلاع والحماية', 'boot.bootloader': 'البوت لودر', 'boot.locked': 'مقفول', 'boot.unlocked': 'مفتوح',
    'boot.slot': 'السلوت الحالي', 'boot.layout': 'التقسيم', 'boot.treble': 'Treble / GSI', 'boot.none': 'ما فيه',
    'boot.spoofed': 'فيه مود إخفاء غيّر ro.boot.verifiedbootstate. الحالة المعروضة هنا هي اللي أرسلها البوت لودر نفسه.',
    'kernel.title': 'الكيرنل', 'kernel.version': 'النسخة', 'kernel.nokmi': 'مو GKI', 'kernel.patch': 'الباتش الأمني',
    'kernel.android': 'أندرويد', 'kernel.build': 'البيلد',

    'stat.battery': 'صحة البطارية', 'stat.cycles': '{0} دورة · {1}', 'stat.level': 'الشحن {0}%',
    'stat.storage': 'استهلاك {0}', 'stat.used': 'مستهلك', 'stat.exceeded': 'تعدّى العمر المقدّر',
    'stat.eol.1': 'الاحتياطي طبيعي', 'stat.eol.2': 'الاحتياطي قليل', 'stat.eol.3': 'قرب نهاية العمر',
    'stat.ram': 'الذاكرة', 'stat.ramfree': '{0} فاضي من {1}',
    'cpu.title': 'المعالج الآن',

    'bb.title': 'آخر إعادة تشغيل ما كانت طبيعية', 'bb.ok': 'آخر إعادة تشغيل كانت طبيعية', 'bb.show': 'اعرض اللوق',
    'bb.none': 'ما انحفظ لوق من الإقلاع اللي قبل', 'bb.sheet': 'الإقلاع السابق',

    'parts.search': 'ابحث عن بارتشن', 'parts.all': 'الكل', 'parts.rest': 'الباقي', 'parts.count': '{0} من {1} · {2}',
    'parts.none': 'ما لقيت /dev/block/by-name في هذا الجوال.',
    'cat.critical': 'مهمة', 'cat.boot': 'إقلاع', 'cat.never': 'ممنوع',
    'super.free': '{0} فاضي', 'super.other': 'السلوت الثاني', 'super.lpdump': 'من lpdump: السلوتين.',
    'super.mapper': 'lpdump مو موجود، فهذا المركّب حالياً (السلوت الحالي بس).',

    'log.kernel': 'الكيرنل · dmesg', 'log.app': 'التطبيقات · logcat', 'log.search': 'بحث…', 'log.pause': 'إيقاف',
    'log.resume': 'متابعة', 'log.all': 'الكل', 'log.errors': 'أخطاء', 'log.warnings': 'تحذيرات', 'log.rules': 'القواعد ({0})',
    'log.tap': 'اضغط على أي سطر SELinux أزرق ويطلع لك قاعدة sepolicy جاهزة.', 'log.empty': 'ما فيه سطور تطابق.',
    'log.gap': 'سطور فاتت',
    'avc.title': 'رفض SELinux', 'avc.rule': 'لملف sepolicy.rule في المود:', 'avc.te': 'لملف ‎.te:',
    'avc.warn': 'لا تسمح إلا باللي تفهمه: كل قاعدة تضعف SELinux شوي.',
    'avc.permissive': 'هذا السطر انسجّل في وضع permissive، يعني ما انمنع شي فعلياً.',
    'avc.all': 'كل حالات الرفض كقواعد', 'avc.none': 'ما فيه رفض SELinux للحين.',
    'copy': 'نسخ', 'copied': 'انتسخ', 'close': 'إغلاق', 'cancel': 'إلغاء',

    'set.critical': 'المهمة', 'set.boot': 'الإقلاع', 'set.full': 'كامل',
    'set.desc.critical': 'الـ IMEI والمعايرة وسلسلة الإقلاع: {0}', 'set.desc.boot': 'السلوت الحالي {1}: {0}',
    'set.desc.full': 'كل شي ما عدا userdata', 'set.sum': '{0} بارتشن · {1}',
    'backup.start': 'ابدأ الباك أب', 'backup.running': 'جاري النسخ…', 'backup.saved': 'النسخ المحفوظة',
    'backup.format': 'نفس صيغة Fastboot Studio في الويندوز: انقل المجلد للكمبيوتر وتحقق منه أو استرجعه من البرنامج، أو تحقق منه بـ sha256sum -c.',
    'backup.none': 'ما فيه نسخ للحين.', 'backup.verify': 'تحقق', 'backup.verifying': 'يتحقق…',
    'backup.ok': 'كلها مطابقة ({0})', 'backup.bad': '{0} متغيّر أو ناقص', 'backup.files': '{0} ملف · {1}',
    'backup.done': 'انحفظت {0} صورة', 'backup.failed': '{0} فشلت',
    'backup.confirm': 'باك أب كامل', 'backup.confirmBody': 'بينسخ {0} بارتشن ({1}) إلى {2}. ممكن ياخذ كم دقيقة.',

    'err.busy': 'فيه باك أب شغال الحين.', 'err.space': 'المساحة ما تكفي: يحتاج {0} والفاضي {1}.',
    'err.nothing': 'ما فيه بارتشنات من هذا النوع في جوالك.', 'err.storage': 'ما قدرت أكتب في {0}.',
    'err.no-by-name': 'ما لقيت /dev/block/by-name في هذا الجوال.', 'err.generic': 'صار خطأ: {0}',
    'err.noroot': 'ما قدرت أوصل للمود. افتح الصفحة من WebUI حق تطبيق الروت.',

    'reboot.title': 'إعادة التشغيل إلى', 'reboot.action': 'إجراء', 'reboot.ask': 'إعادة التشغيل إلى {0}؟',
    'reboot.body': 'التطبيقات المفتوحة بتتقفل والجوال بيعيد التشغيل على طول.', 'reboot.go': 'أعد التشغيل',
    'reboot.edl': 'Qualcomm فقط', 'reboot.fastbootd': 'للبارتشنات الديناميكية فقط',
    'bundle.title': 'حزمة دعم فني',
    'bundle.body': 'لوق الكيرنل و logcat ومعلومات الجهاز وجدول البارتشنات في ملف واحد، عشان تبلّغ عن مشكلة.',
    'bundle.redact': 'إخفاء الـ IMEI والسيريال وعناوين MAC', 'bundle.go': 'جهّز الملف', 'bundle.making': 'يجمع…',
    'bundle.saved': 'انحفظ في {0}',
    'about.title': 'عن الوحدة', 'about.version': 'النسخة', 'about.backups': 'الباك أب', 'about.source': 'الكود',
    'lang.auto': 'تلقائي', 'lang.title': 'اللغة', 'beta': 'تجريبي',
    'theme.title': 'المظهر', 'theme.auto': 'تلقائي', 'theme.dark': 'ليلي', 'theme.light': 'نهاري',
    'theme.toDark': 'التبديل للوضع الليلي', 'theme.toLight': 'التبديل للوضع النهاري',
    'links.app': 'برنامج Fastboot Studio للويندوز', 'links.group': 'قروب تيليجرام', 'links.dm': 'راسلني على الخاص',
    'links.source': 'كود الوحدة',
    'demo': 'بيانات تجريبية. افتح الصفحة من تطبيق الروت عشان تشوف جوالك.',
  },
};

const i18n = {
  lang: 'en',
  choice: 'auto',

  t(key, ...args) {
    let s = STRINGS[this.lang][key] ?? STRINGS.en[key] ?? key;
    args.forEach((v, i) => { s = s.split('{' + i + '}').join(v); });
    return s;
  },

  pick(choice) {
    this.choice = choice;
    const nav = (navigator.language || 'en').toLowerCase();
    this.lang = choice === 'auto' ? (nav.startsWith('ar') ? 'ar' : 'en') : choice;
    document.documentElement.lang = this.lang;
    document.documentElement.dir = this.lang === 'ar' ? 'rtl' : 'ltr';
    document.querySelectorAll('[data-i]').forEach(el => { el.textContent = this.t(el.dataset.i); });
    document.querySelectorAll('[data-ph]').forEach(el => { el.placeholder = this.t(el.dataset.ph); });
  },
};
