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
    check "beta badge shown" 'id="betaChip" data-i="beta">'
    check "links listed" 'data-url="https://t.me/IFOKNR1"'
    check "link to the Windows app" 'data-url="https://github.com/ifoknr/FastbootStudio/releases/latest"'
    check "day/night button" 'id="themeBtn"'
    check "saved backups listed" 'Demo_Phone_DEMO0123456789_20260921-184012'
    if printf '%s' "$dom" | grep -q 'class="card alert"><p class="note"'; then
        echo "FAIL [$lang] the bridge error card is showing"
        fails=$((fails + 1))
    fi
    if [ "$lang" = ar ]; then
        check "page is right-to-left" 'dir="rtl"'
    fi
done
dom=$("$CHROME" --headless --no-sandbox --disable-gpu --virtual-time-budget=4000 --dump-dom "file://$PAGE?theme=light" 2>/dev/null)
lang=light
check "day mode applies" 'data-theme="light"'
check "header button offers night mode" 'data-dark="0"'
[ $fails -eq 0 ] && echo "webui smoke passed"
[ $fails -eq 0 ]
