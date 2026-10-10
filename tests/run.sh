#!/bin/sh
# Runs fbs against the fake phone from fixture.sh under each shell in $SHELLS
# (default "sh"; CI uses "dash mksh busybox-sh"). Needs jq and coreutils.
# The sh -c snippets get their text through "$1" on purpose.
# shellcheck disable=SC2016
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SHELLS=${SHELLS:-sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
total=0
fails=0

pass() { total=$((total + 1)); }
fail() {
    total=$((total + 1))
    fails=$((fails + 1))
    echo "  FAIL [$SHN] $*"
}
# expect <description> <command...>
expect() {
    _d=$1
    shift
    if "$@" >/dev/null 2>&1; then pass; else fail "$_d"; fi
}
# jqt <json> <filter>: the filter must give true
# refuses <command...>: the command must fail
refuses() { if "$@" >/dev/null 2>&1; then return 1; else return 0; fi; }
jqt() { printf '%s\n' "$1" | jq -e "$2" >/dev/null 2>&1; }
# jql <json lines> <filter>: slurped into one array
jql() { printf '%s\n' "$1" | jq -s -e "$2" >/dev/null 2>&1; }

fbs() {
    FBS_ROOT=$R FBS_DATA=$WORK/data FBS_RUN=$WORK/run PATH="$HERE/shims:$PATH" $SH "$ROOT/module/bin/fbs" "$@"
}

for SHN in $SHELLS; do
    case $SHN in
        busybox-sh) SH="busybox sh" ;;
        *) SH=$SHN ;;
    esac
    echo "== $SHN"
    R=$WORK/phone
    rm -rf "$WORK/data" "$WORK/run"
    sh "$HERE/fixture.sh" "$R"

    # ---- info
    out=$(fbs info)
    expect "info is JSON" jqt "$out" 'type == "object"'
    expect "model" jqt "$out" '.model == "Demo Phone"'
    expect "KMI from the kernel release" jqt "$out" '.kmi == "5.15-android13"'
    expect "AVB state from bootconfig, not the spoofed prop" jqt "$out" '.boot.vbstate == "orange" and .boot.spoofed == true'
    expect "device state from bootconfig" jqt "$out" '.boot.device_state == "unlocked" and .boot.locked == false'
    expect "slot, dynamic, treble" jqt "$out" '.slot == "_a" and .dynamic == true and .treble == true and .vndk == "34"'
    expect "MediaTek and KernelSU" jqt "$out" '.soc == "mediatek" and .root == "KernelSU"'
    expect "battery health 4550000/5000000" jqt "$out" '.battery.health == 91 and .battery.cycles == 312 and .battery.temp_dc == 334'
    expect "eMMC wear" jqt "$out" '.storage.type == "emmc" and .storage.life_a == "0x02" and .storage.eol == "0x01"'
    expect "memory" jqt "$out" '.memory.total_kb == 7864320 and .memory.avail_kb == 2725000'
    expect "SELinux" jqt "$out" '.selinux == "Enforcing"'
    expect "channel is reported" jqt "$out" '.channel == "beta" or .channel == "stable"'

    # ---- report
    out=$(fbs report)
    expect "report names the KMI" sh -c 'printf "%s" "$1" | grep -q "^KMI  *5.15-android13$"' _ "$out"
    expect "report counts partitions" sh -c 'printf "%s" "$1" | grep -q "^Partitions  *22$"' _ "$out"

    # ---- parts
    out=$(fbs parts)
    expect "parts is JSON" jqt "$out" '.parts | type == "array"'
    expect "by-name dir found under platform/" jqt "$out" '.dir == "/dev/block/platform/bootdevice/by-name"'
    expect "22 by-name + raw preloader" jqt "$out" '.parts | length == 23'
    expect "raw preloader is critical" jqt "$out" '.parts[] | select(.name == "preloader_raw") | .dev == "mmcblk0boot0" and .cat == "critical"'
    expect "super keeps its 9 GiB in sectors" jqt "$out" '.parts[] | select(.name == "super") | .sectors == 18874368 and .cat == "super"'
    expect "userdata is never" jqt "$out" '.parts[] | select(.name == "userdata") | .cat == "never"'
    expect "nvram is critical, boot_a is boot, misc is other" jqt "$out" \
        '([.parts[] | select(.name == "nvram")][0].cat == "critical") and ([.parts[] | select(.name == "boot_a")][0].cat == "boot") and ([.parts[] | select(.name == "misc")][0].cat == "other")'

    # ---- super
    out=$(fbs super)
    expect "super falls back to device-mapper" jqt "$out" '.source == "mapper" and .super_sectors == 18874368'
    expect "mapper skips control, userdata and snapshot pieces" jqt "$out" '[.parts[].name] == ["odm_a","product_a","system_a","system_ext_a","vendor_a"]'
    : > "$R/use-lpdump"
    out=$(fbs super)
    expect "super from lpdump" jqt "$out" '.source == "lpdump" and .lp.block_devices[0].size == "9663676416"'
    rm -f "$R/use-lpdump"

    # ---- cpu
    out=$(fbs cpu)
    expect "cpu: 8 cores" jqt "$out" '.cores | length == 8'
    expect "cpu: clocks" jqt "$out" '.cores[7].cur == 1500000 and .cores[7].max == 2200000'
    expect "cpu: hottest cpu/soc zone" jqt "$out" '.cpu_temp == 47900'
    expect "cpu: swap in use" jqt "$out" '.swap_used_kb == 1258292'

    # ---- logs
    out=$(fbs log kernel 2)
    expect "kernel log tail" test "$(printf '%s\n' "$out" | wc -l)" -eq 2
    rm -f "$R/logcat.args"
    fbs log app '10-09 21:14:02.400' > /dev/null
    expect "logcat since a time" grep -qx -- '-d|-v|threadtime|-t|10-09 21:14:02.400|' "$R/logcat.args"
    rm -f "$R/logcat.args"
    fbs log app '$(reboot)' > /dev/null
    expect "logcat refuses odd input" grep -qx -- '-d|-v|threadtime|-t|300|' "$R/logcat.args"
    expect "log needs a source" refuses fbs log nothing

    # ---- last boot
    out=$(fbs last)
    expect "last: reason header" sh -c 'printf "%s\n" "$1" | grep -qx "#reason=reboot,userrequested"' _ "$out"
    expect "last: console-ramoops" sh -c 'printf "%s\n" "$1" | grep -qx "#source=/sys/fs/pstore/console-ramoops-0"' _ "$out"
    printf 'Kernel panic - not syncing: Fatal exception\n' > "$R/sys/fs/pstore/dmesg-ramoops-0"
    out=$(fbs last)
    expect "last: a panic dump goes first" sh -c 'printf "%s\n" "$1" | grep -qx "#source=/sys/fs/pstore/dmesg-ramoops-0"' _ "$out"
    rm -f "$R/sys/fs/pstore/dmesg-ramoops-0"

    # ---- backup: critical
    out=$(fbs backup critical)
    expect "backup events are JSON lines" jql "$out" 'length > 2'
    expect "critical plan" jql "$out" '.[0].event == "plan" and .[0].count == 11'
    expect "critical has the identity partitions and raw preloader, not boot" jql "$out" \
        '[.[] | select(.event == "done") | .name] | (index("nvram") != null and index("preloader_raw") != null and index("seccfg") != null and index("boot_a") == null)'
    expect "critical finished clean" jql "$out" '.[-1].event == "finish" and .[-1].saved == 11 and .[-1].failed == 0'
    dir=$WORK/data/Backups/$(printf '%s\n' "$out" | jq -r 'select(.event == "finish") | .folder')
    expect "folder named like the Windows app" sh -c 'case "${1##*/}" in Demo_Phone_DEMO0123456789_[0-9]*-[0-9]*) ;; *) exit 1 ;; esac' _ "$dir"
    expect "SHA256SUMS checks with sha256sum -c" sh -c 'cd "$1" && sha256sum -c --quiet SHA256SUMS' _ "$dir"
    expect "images match the partitions" cmp "$dir/nvram.img" "$R/dev/block/mmcblk0p3"
    expect "backup-info header" sh -c 'head -n 1 "$1" | grep -qx "Fastboot Studio backup"' _ "$dir/backup-info.txt"
    expect "backup-info table is tab-separated" sh -c 'grep -q "^nvram	4096	[0-9a-f]\{64\}$" "$1"' _ "$dir/backup-info.txt"
    expect "backup-info mode" grep -q "^mode	companion$" "$dir/backup-info.txt"
    expect "lock released" test ! -e "$WORK/run/backup.pid"

    # ---- backup: boot (current slot only)
    sleep 1
    out=$(fbs backup boot)
    expect "boot set is the current slot" jql "$out" \
        '[.[] | select(.event == "done") | .name] | sort == ["boot_a","dtbo_a","init_boot_a","vbmeta_a"]'

    # ---- backup: full
    sleep 1
    out=$(fbs backup full)
    expect "full skips userdata only" jql "$out" \
        '[.[] | select(.event == "done") | .name] | (index("userdata") == null and index("super") != null and length == 22)'

    # ---- backup refusals
    out=$(FAKE_DF_AVAIL=1000 fbs backup critical)
    expect "not enough space" jqt "$out" '.event == "error" and .msg == "space"'
    mkdir -p "$WORK/run"
    sleep 300 &
    busy=$!
    echo $busy > "$WORK/run/backup.pid"
    out=$(fbs backup critical)
    kill $busy
    rm -f "$WORK/run/backup.pid"
    expect "one backup at a time" jqt "$out" '.msg == "busy"'
    out=$(fbs backup everything)
    expect "unknown set" jqt "$out" '.event == "error"'

    # ---- backups and verify
    out=$(fbs backups)
    expect "three backups listed" jqt "$out" '.items | length == 3'
    expect "newest first" jqt "$out" '.items[0].files == 22 and .items[2].files == 11'
    name=${dir##*/}
    out=$(fbs verify "$name")
    expect "verify passes" jql "$out" '.[-1] == {"event":"finish","ok":11,"bad":0}'
    printf 'x' >> "$dir/nvram.img"
    out=$(fbs verify "$name")
    expect "verify catches a changed image" jql "$out" \
        '(.[] | select(.name == "nvram.img") | .state == "bad") and .[-1].bad == 1'
    out=$(fbs verify ../etc)
    expect "verify stays inside Backups" jqt "$out" '.event == "error"'

    # ---- reboot
    rm -f "$R/reboot.log"
    fbs reboot bootloader > /dev/null
    expect "reboot bootloader" grep -qx bootloader "$R/reboot.log"
    out=$(fbs reboot edl)
    expect "EDL refused on MediaTek" jqt "$out" '.ok == false and .msg == "edl-qualcomm-only"'
    expect "unknown reboot target" refuses fbs reboot sideways
    expect "only one reboot ran" test "$(wc -l < "$R/reboot.log")" -eq 1

    # ---- modules and their conflicts
    out=$(fbs modules)
    expect "modules is JSON" jqt "$out" '.modules | length == 9'
    expect "a disabled module is listed but not scanned" jqt "$out" '.modules[] | select(.id == "off") | .enabled == false and .files == 0'
    expect "skip_mount: no files, props still count" jqt "$out" '.modules[] | select(.id == "nomount") | .mount == false and .files == 0 and .props == 1'
    expect "WebUI, Action and boot scripts" jqt "$out" '.modules[] | select(.id == "ui") | .webui and .action and .scripts == ["service.sh"]'
    expect "names are escaped" jqt "$out" '.modules[] | select(.id == "hosts_b") | .name == "Hosts \"B\""'
    expect "same file, and vendor/ is system/vendor/" jqt "$out" \
        '[.conflicts[] | select(.kind == "file" and .modules == ["hosts_a","hosts_b"])][0] | .count == 2 and (.paths | index("/system/etc/hosts") != null) and (.paths | index("/system/vendor/lib/libdemo.so") != null)'
    expect "shared files are grouped per module pair" jqt "$out" \
        '[.conflicts[] | select(.kind == "file" and .modules == ["fonts_1","fonts_2"])][0] | .count == 20 and (.paths | length) == 12'
    expect "a replaced folder hides another module's files" jqt "$out" \
        '[.conflicts[] | select(.kind == "replace")] | length == 1 and .[0].path == "/system/app/Foo" and .[0].by == "debloat" and .[0].modules == ["addon"]'
    expect "same property, different values" jqt "$out" \
        '[.conflicts[] | select(.kind == "prop")] | length == 1 and .[0].key == "ro.demo.x" and (.[0].values | length) == 3'
    expect "disabled and unmounted modules are not file conflicts" jqt "$out" \
        '[.conflicts[] | select(.kind == "file") | .modules[]] | (index("off") == null and index("nomount") == null)'
    expect "four conflicts in all" jqt "$out" '.conflicts | length == 4'
    expect "scan files cleaned up" test ! -d "$WORK/run/scan"
    out=$(fbs report)
    expect "report counts conflicts" sh -c 'printf "%s" "$1" | grep -q "^Conflicts  *4 between modules$"' _ "$out"

    # ---- facts for the Windows app
    out=$(fbs facts)
    expect "facts: kernel first" sh -c 'printf "%s\n" "$1" | head -n 1 | grep -qx "kernel=5.15.148-android13-8-00017-gabc123"' _ "$out"
    expect "facts: companion version and channel" sh -c 'printf "%s\n" "$1" | grep -qx "companion=[0-9.]* \(beta\|stable\)"' _ "$out"
    expect "facts: root, AVB from the bootloader, spoofing" sh -c 'printf "%s\n" "$1" | grep -qx "root=KernelSU" && printf "%s\n" "$1" | grep -qx "avb=orange" && printf "%s\n" "$1" | grep -qx "spoofed=true"' _ "$out"
    expect "facts: conflicts counted" sh -c 'printf "%s\n" "$1" | grep -qx "conflicts=4"' _ "$out"
    expect "facts: every line is key=value" sh -c '! printf "%s\n" "$1" | grep -qv "^[a-z_]*="' _ "$out"

    # ---- open
    rm -f "$R/am.log"
    out=$(fbs open https://t.me/IFOKNR1)
    expect "open a link" jqt "$out" '.ok == true'
    expect "open hands it to am" grep -qx -- '-a android.intent.action.VIEW -d https://t.me/IFOKNR1' "$R/am.log"
    out=$(fbs open 'javascript:alert(1)')
    expect "open takes https only" jqt "$out" '.ok == false'
    out=$(fbs open "https://x.example/a'b")
    expect "open refuses quotes" jqt "$out" '.msg == "bad-url"'
    expect "nothing else reached am" test "$(wc -l < "$R/am.log")" -eq 1

    # ---- bundle
    out=$(fbs bundle)
    expect "bundle made" jqt "$out" '.ok == true and .redacted == true and (.file | endswith(".tar.gz"))'
    file=$(printf '%s' "$out" | jq -r .file)
    mkdir -p "$WORK/x" && tar -xzf "$file" -C "$WORK/x"
    expect "bundle has the logs and device info" sh -c 'ls "$1"/*/device.json "$1"/*/logcat.txt "$1"/*/dmesg.txt "$1"/*/props.txt "$1"/*/partitions.json' _ "$WORK/x"
    expect "IMEI masked" sh -c '! grep -rq 356938035643809 "$1"' _ "$WORK/x"
    expect "serial masked" sh -c '! grep -rq DEMO0123456789 "$1"' _ "$WORK/x"
    expect "MAC masked" sh -c '! grep -rq "3c:84:6a:12:9e:01" "$1"' _ "$WORK/x"
    expect "device.json still JSON after masking" sh -c 'jq -e .model "$1"/*/device.json' _ "$WORK/x"
    rm -rf "$WORK/x"

    # ---- the Action button runs from the module folder
    out=$(FBS_ROOT=$R FBS_RUN=$WORK/run PATH="$HERE/shims:$PATH" $SH "$ROOT/module/action.sh")
    expect "action prints the report" sh -c 'printf "%s\n" "$1" | head -n 1 | grep -q "^Fastboot Studio Companion "' _ "$out"

    # ---- cli
    expect "version" test "$(fbs version)" = "$(sed -n 's/^version=v//p' "$ROOT/module/module.prop")"
    expect "unknown command fails" refuses fbs frobnicate
done

echo "$((total - fails)) / $total passed"
[ $fails -eq 0 ]
