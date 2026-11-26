#!/bin/sh
# Opens the WebUI in headless Chrome with the demo bridge and checks that every tab filled in
# and nothing threw. $CHROME is the browser binary.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PAGE=$HERE/../module/webroot/index.html
CHROME=${CHROME:-google-chrome}
fails=0
for lang in en ar; do
    dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=5000 --dump-dom "file://$PAGE?lang=$lang" 2>/dev/null)
    check() {
        if printf '%s' "$dom" | grep -q -- "$2"; then :; else
            echo "FAIL [$lang] $1"
            fails=$((fails + 1))
        fi
    }
    check "header names the phone" 'id="whoLine">Demo Phone'
    check "kernel card has the KMI" '5.15-android13'
    check "black box shows the panic" 'class="hit"'
    check "partition table filled" '<div class="pn">nvram</div>'
    check "super card filled" 'system_a'
    check "backup sets described" 'id="setCritical">[^<]'
    check "reboot targets listed" 'data-r="bootloader"'
    check "no beta badge on a stable build" 'id="betaChip" hidden'
    check "backups can be deleted" 'data-act="delete"'
    check "links listed" 'data-url="https://t.me/IFOKNR1"'
    check "group link" 'data-url="https://t.me/BeNeXTBrO"'
    check "link to the Windows app" 'data-url="https://github.com/ifoknr/FastbootStudio/releases/latest"'
    check "day/night button" 'id="themeBtn"'
    check "modules tab" 'data-v="mods"'
    check "saved backups listed" 'Demo_Phone_DEMO0123456789_20260921-184012'
    if printf '%s' "$dom" | grep -q 'class="card alert"><p class="note"'; then
        echo "FAIL [$lang] the bridge error card is showing"
        fails=$((fails + 1))
    fi
    if [ "$lang" = ar ]; then
        check "page is right-to-left" 'dir="rtl"'
    fi
done
# The long jobs go through the bridge's spawn: a backup (checked afterwards, as the default is)
# and a Verify tap, in both languages.
for lang in en ar; do
    dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=12000 --dump-dom "file://$PAGE?lang=$lang&demo=backup#backup" 2>/dev/null)
    check "backup ran through spawn" 'class="st ok"[^>]*>✓'
    check "backup listed afterwards" 'data-name="Demo_Phone_DEMO0123456789_20261009-211407"'
    check "backup checked afterwards" 'data-name="Demo_Phone_DEMO0123456789_20261009-211407".*color:var(--ok)">✓'
    check "free space shown" 'id="backupFree" role="status">[^<]*48'
    check "a big partition reported its progress" 'data-n="md1img_a"[^>]*data-p="1"'
    dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=9000 --dump-dom "file://$PAGE?lang=$lang&demo=custom#backup" 2>/dev/null)
    check "a picked set copies what was picked" 'data-n="boot_a"'
    check "a picked set copies nothing else" 'id="progCount">2 / 2<'
    check "userdata cannot be picked" 'value="userdata" disabled'
    check "the pick is counted" 'id="customSum" role="status">2 '
    dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=6000 --dump-dom "file://$PAGE?lang=$lang&demo=archive#backup" 2>/dev/null)
    check "an archive is made and offered for sharing" 'data-act="share"'
    check "the archive path is shown" 'Demo_Phone_DEMO0123456789_20260921-184012.tar'
    dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=6000 --dump-dom "file://$PAGE?lang=$lang&demo=verify#backup" 2>/dev/null)
    check "verify ran through spawn" 'data-name="Demo_Phone_DEMO0123456789_20260921-184012".*color:var(--ok)">✓'
    check "no button left busy" 'data-act="verify">'
done
dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=4000 --dump-dom "file://$PAGE?theme=light" 2>/dev/null)
lang=light
check "day mode applies" 'data-theme="light"'
check "header button offers night mode" 'data-dark="0"'
# The page's own fonts are loaded, not the computer's.
fonts=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=4000 --dump-dom "file://$PAGE?lang=ar&fontcheck=1" 2>/dev/null | grep -o 'data-fonts="[^"]*"')
case $fonts in
    *"Noto Kufi Arabic"*"Roboto"*) ;;
    *) echo "FAIL the bundled fonts did not load: $fonts"; fails=$((fails + 1)) ;;
esac
[ $fails -eq 0 ] && echo "webui smoke passed"
[ $fails -eq 0 ]
