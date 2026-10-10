#!/bin/sh
# Builds a fake MediaTek phone under $1: /dev, /sys, /proc and the files the shims read.
# eMMC, A/B, dynamic partitions, KernelSU, and a hiding module that set
# ro.boot.verifiedbootstate to green while the bootloader said orange.
set -eu
R=$1
rm -rf "$R"
mkdir -p "$R"

w() { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "$2" > "$R/$1"; }

cat > "$R/props" <<'EOF'
ro.product.model=Demo Phone
ro.product.brand=Demo
ro.product.device=demo
ro.product.name=demo_mt6789
ro.serialno=DEMO0123456789
ro.build.version.release=14
ro.build.version.sdk=34
ro.build.version.security_patch=2026-08-05
ro.build.display.id=DEMO-14.0.1
ro.board.platform=mt6789
ro.soc.manufacturer=Mediatek
ro.product.cpu.abi=arm64-v8a
ro.boot.slot_suffix=_a
ro.boot.dynamic_partitions=true
ro.treble.enabled=true
ro.vndk.version=34
ro.boot.verifiedbootstate=green
ro.boot.vbmeta.device_state=locked
ro.boot.flash.locked=0
sys.boot.reason=reboot,userrequested
persist.radio.imei=356938035643809
EOF

w proc/bootconfig 'androidboot.verifiedbootstate = "orange"
androidboot.vbmeta.device_state = "unlocked"
androidboot.slot_suffix = "_a"'
w proc/cmdline 'console=ttyS0 androidboot.hardware=mt6789'
w proc/sys/kernel/osrelease '5.15.148-android13-8-00017-gabc123'
w sys/fs/selinux/enforce 1
mkdir -p "$R/data/adb"
: > "$R/data/adb/ksud"

w sys/class/power_supply/battery/capacity 78
w sys/class/power_supply/battery/cycle_count 312
w sys/class/power_supply/battery/temp 334
w sys/class/power_supply/battery/charge_full 4550000
w sys/class/power_supply/battery/charge_full_design 5000000
w sys/class/mmc_host/mmc0/mmc0:0001/life_time '0x02 0x01'
w sys/class/mmc_host/mmc0/mmc0:0001/pre_eol_info 0x01
w proc/meminfo 'MemTotal:        7864320 kB
MemFree:          412000 kB
MemAvailable:    2725000 kB
SwapTotal:       4194304 kB
SwapFree:        2936012 kB'

for c in 0 1 2 3 4 5 6 7; do
    max=2000000
    [ $c -ge 6 ] && max=2200000
    w sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq $max
    w sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq $((800000 + c * 100000))
done
w sys/class/thermal/thermal_zone0/type mtktscpu
w sys/class/thermal/thermal_zone0/temp 47900
w sys/class/thermal/thermal_zone1/type battery
w sys/class/thermal/thermal_zone1/temp 33400
w sys/class/thermal/thermal_zone2/type soc_max
w sys/class/thermal/thermal_zone2/temp 45100

# name  device  sectors. Small partitions get real 4 KiB contents; the big ones only claim
# their size in sysfs (super is 9 GiB, userdata 112 GiB: both past 32-bit byte counts).
mkdir -p "$R/dev/block/platform/bootdevice/by-name"
i=1
while read -r name sectors; do
    dev=mmcblk0p$i
    if [ "$sectors" -le 8 ]; then
        head -c 4096 /dev/urandom > "$R/dev/block/$dev"
    else
        printf 'big' > "$R/dev/block/$dev"
    fi
    w "sys/class/block/$dev/size" "$sectors"
    ln -s "../../../$dev" "$R/dev/block/platform/bootdevice/by-name/$name"
    i=$((i + 1))
done <<'EOF'
lk_a 8
lk_b 8
nvram 8
nvdata 8
nvcfg 8
protect1 8
protect2 8
seccfg 8
persist 8
boot_a 8
boot_b 8
init_boot_a 8
init_boot_b 8
vbmeta_a 8
vbmeta_b 8
dtbo_a 8
dtbo_b 8
md1img_a 8
metadata 8
misc 8
super 18874368
userdata 234881024
EOF
# The preloader lives in the eMMC boot area and has no by-name link here.
head -c 4096 /dev/urandom > "$R/dev/block/mmcblk0boot0"
w sys/class/block/mmcblk0boot0/size 8

mkdir -p "$R/dev/block/mapper"
d=0
for name in system_a vendor_a product_a system_ext_a odm_a system_a-cow userdata control; do
    : > "$R/dev/block/dm-$d"
    w "sys/class/block/dm-$d/size" $(( (d + 1) * 1048576 ))
    ln -s "../dm-$d" "$R/dev/block/mapper/$name"
    d=$((d + 1))
done

w sys/fs/pstore/console-ramoops-0 '[    0.000000] Booting Linux on physical CPU 0x0
[ 4211.120400] reboot: Restarting system with command '"'"'userrequested'"'"''

cat > "$R/dmesg.txt" <<'EOF'
[  812.443100] healthd: battery l=78 v=4012 t=33.4 h=2 st=3 c=-412
[  812.901200] avc: denied { read } for comm="system_server" name="cmdline" dev="proc" scontext=u:r:system_server:s0 tcontext=u:r:init:s0 tclass=file permissive=0
[  813.102000] thermal: zone[cpu-0-0] temp=47900
[  813.552100] lowmemorykiller: Kill 'com.example.game' (8342), adj 900, to free 182340kB
[  814.000100] usb: [USB] DEVICE STATE: CONFIGURED
[  814.221000] wlan: connected to 3c:84:6a:12:9e:01
EOF

cat > "$R/logcat.txt" <<'EOF'
10-09 21:14:02.118  1452  1503 I ActivityManager: Start proc 8342:com.example.game/u0a212
10-09 21:14:02.400  1452  1503 W PackageManager: Unknown permission demo.permission.X
10-09 21:14:03.010  2001  2001 I RIL: IMEI 356938035643809 serial DEMO0123456789
EOF

cat > "$R/lpdump.json" <<'EOF'
{"partitions":[{"name":"system_a","group_name":"main_a","is_dynamic":true,"size":"3446718464"},{"name":"system_b","group_name":"main_b","is_dynamic":true,"size":"0"}],"block_devices":[{"name":"super","first_sector":"2048","size":"9663676416","block_size":4096}],"groups":[{"name":"main_a","maximum_size":"9659482112"},{"name":"main_b","maximum_size":"9659482112"}]}
EOF

# Root modules that get in each other's way, plus two that must not count: one disabled, one
# that does not mount (its system.prop still applies).
M=$R/data/adb/modules
mod() {
    mkdir -p "$M/$1"
    printf 'id=%s\nname=%s\nversion=v1.0\nversionCode=1\nauthor=tester\n' "$1" "$2" > "$M/$1/module.prop"
}
put() {
    mkdir -p "$(dirname "$M/$1/$2")"
    : > "$M/$1/$2"
}
mod hosts_a 'Hosts A'
put hosts_a system/etc/hosts
put hosts_a system/vendor/lib/libdemo.so
printf 'ro.demo.x=1\nro.only.a=1\n' > "$M/hosts_a/system.prop"
mod hosts_b 'Hosts "B"'
put hosts_b system/etc/hosts
put hosts_b vendor/lib/libdemo.so
mod fonts_1 'Fonts 1'
mod fonts_2 'Fonts 2'
for i in $(seq 1 20); do
    put fonts_1 "system/fonts/Demo$i.ttf"
    put fonts_2 "system/fonts/Demo$i.ttf"
done
mod debloat 'Debloat'
put debloat system/app/Foo/.replace
printf '# comment=ignored\nro.demo.x=2\n' > "$M/debloat/system.prop"
mod addon 'Addon'
put addon system/app/Foo/extra.apk
mod off 'Off'
put off system/etc/hosts
: > "$M/off/disable"
mod nomount 'No mount'
put nomount system/etc/hosts
: > "$M/nomount/skip_mount"
printf 'ro.demo.x = 1\n' > "$M/nomount/system.prop"
mod ui 'With WebUI'
put ui webroot/index.html
put ui action.sh
put ui service.sh
