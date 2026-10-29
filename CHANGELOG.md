# Changelog · سجل التعديلات

<!-- The "## vX.Y.Z" section is the release notes and the Telegram post (.github/scripts/telegram-release.sh): keep it short. -->

## v2.5.2
- البوت لودر يطلع «مفتوح» صح حتى لو الروم أو مود إخفاء خلّى خصائص الإقلاع تقول «مقفل» (مثل أجهزة كوالكوم القديمة)
- الحالة تنقرا من البوت لودر نفسه أول، والروت يعني إن البوت لودر مفتوح
- لو الحالة مو معروفة تطلع «؟» بدل «مقفل»

**English**
- The bootloader shows as unlocked even when the ROM or a hiding module makes the boot properties say locked (older Qualcomm phones, for one)
- The state comes from the bootloader itself first, and root means the bootloader is unlocked
- An unknown state shows as "?" instead of "locked"

## v2.5.1
- أول إصدار رسمي: الإضافة طلعت من التجريبي (Beta)
- زر «حذف» لكل نسخة احتياطية في تبويب الباك أب، مع تأكيد قبل الحذف
- أمر fbs delete يحذف نسخة وحدة من مجلد Backups بس

**English**
- First stable release: the module is out of beta
- A Delete button for each backup in the Backup tab, with a confirmation first
- fbs delete removes one backup, and only inside the Backups folder

## v2.5.0
- متوافق مع صفحة «الجوال» في Fastboot Studio v2.5.0: المواصفات والحماية والتعارضات والنسخ الاحتياطية
- النسخة الاحتياطية تنكتب في مجلد مخفي وما يطلع اسمها إلا لما تكتمل، فالبرنامج ما ينقل نسخة ناقصة
- النسخة اللي انقطعت تنحذف تلقائي مع النسخة الجاية
- ملف backup-info.txt يذكر نوع النسخة (حرجة، إقلاع، كاملة)

**English**
- Works with the Phone page in Fastboot Studio v2.5.0: specs, security, conflicts and backups
- A backup is written to a hidden folder and named only when complete, so the app never copies a half-written one
- A backup that was cut off is removed by the next one
- backup-info.txt names the set (critical, boot, full)

## v2.4.0
- تبويب الوحدات: يكشف التعارض بين مودات الروت (ملف مكرر، مجلد مستبدل، خاصية بقيمتين)
- تصميم للتابلت والشاشات الكبيرة، وخط وقوائم أكبر
- وضع ليلي ونهاري، والتلقائي يمشي مع الجوال
- روابط البرنامج والقروب والخاص والسورس
- أمر fbs facts يقرا منه Fastboot Studio v2.4.0 على الويندوز

**English**
- Modules tab: finds conflicts between root modules (shared files, replaced folders, clashing props)
- Layout for tablets and large screens, bigger text and lists
- Day and night themes; Auto follows the phone
- Links to the Windows app, the Telegram group, private chat and the source
- fbs facts, read by Fastboot Studio v2.4.0 on Windows

## v2.3.0
- إصدار تجريبي (Beta)، ورقمه نفس Fastboot Studio v2.3.0
- للقراءة فقط: ما يشتغل وقت الإقلاع وما يكتب على أي بارتشن
- فحص الجهاز: حالة البوت لودر الحقيقية، والكيرنل و KMI، وصحة البطارية والذاكرة
- الصندوق الأسود: لوق آخر كراش مع أسطر الـ panic
- البارتشنات وخريطة super، واللوق اللحظي مع قواعد SELinux جاهزة
- باك أب بنفس صيغة Fastboot Studio مع SHA-256، وحزمة دعم تخفي الـ IMEI
