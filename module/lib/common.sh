# Shared helpers for fbs. POSIX sh only: it has to run under mksh (Android's /system/bin/sh),
# busybox ash (Magisk, KernelSU, APatch) and dash (the tests).
#
# mksh does 32-bit arithmetic, so sizes stay in 512-byte sectors or KiB here and the WebUI
# turns them into bytes. Reads go through the "read" builtin where they can, because "fbs cpu"
# runs every second and every $(...) costs a fork.

# Tests point these at a fake device; on a phone they stay at their defaults.
R=${FBS_ROOT:-}
DATA=${FBS_DATA:-/sdcard/FastbootStudio}
RUN=${FBS_RUN:-/data/adb/fastboot_studio_companion}

TAB=$(printf '\t')
NL='
'

# First line of a file into REPLY. Empty when the file is missing or unreadable.
rd() {
    REPLY=
    [ -r "$1" ] || return 1
    IFS= read -r REPLY < "$1" || [ -n "$REPLY" ]
}

# N becomes $1 when it is a whole number (an optional leading minus), otherwise null.
num() {
    N=null
    case ${1#-} in
        '' | *[!0-9]*) ;;
        *) N=$1 ;;
    esac
}

# A JSON string for one line of text: control characters dropped, \ and " escaped.
js() {
    printf '"%s"' "$(printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# true, false or null.
jb() {
    case $1 in
        1 | true | yes) printf true ;;
        0 | false | no) printf false ;;
        *) printf null ;;
    esac
}

prop() {
    getprop "$1" 2>/dev/null
}

# A value the bootloader passed to the kernel (androidboot.<name>). Hiding modules often
# change the matching ro.boot.* property; /proc/bootconfig and /proc/cmdline keep the original.
bootarg() {
    _v=
    if [ -r "$R/proc/bootconfig" ]; then
        _v=$(sed -n "s/^androidboot\.$1 *= *\"\(.*\)\" *\$/\1/p" "$R/proc/bootconfig" | head -n 1)
    fi
    if [ -z "$_v" ] && [ -r "$R/proc/cmdline" ]; then
        _v=$(tr ' ' '\n' < "$R/proc/cmdline" | sed -n "s/^androidboot\.$1=//p" | head -n 1)
    fi
    printf '%s' "$_v"
}

# The folder of partition links, which moves around between vendors.
byname_dir() {
    for _d in "$R/dev/block/by-name" "$R/dev/block/bootdevice/by-name" \
        "$R"/dev/block/platform/*/by-name "$R"/dev/block/platform/*/*/by-name; do
        if [ -d "$_d" ]; then
            printf '%s' "$_d"
            return 0
        fi
    done
    return 1
}

current_slot() {
    _s=$(prop ro.boot.slot_suffix)
    [ -n "$_s" ] || _s=$(bootarg slot_suffix)
    printf '%s' "$_s"
}

# CAT becomes the partition's group: never, super, boot, critical or other.
# The critical list is the same as PartitionSafety.BrickRisk in the Windows app.
category() {
    _b=${1%_a}
    _b=${_b%_b}
    case $_b in
        userdata) CAT=never ;;
        super) CAT=super ;;
        boot | init_boot | vendor_boot | vendor_kernel_boot | dtbo | recovery | \
            vbmeta | vbmeta_system | vbmeta_vendor) CAT=boot ;;
        xbl | xbl_config | xbl_ramdump | abl | tz | tz_mem | aop | aop_config | hyp | devcfg | \
            keymaster | cmnlib | cmnlib64 | qupfw | uefi | uefisecapp | imagefv | shrm | cpucp | \
            rpm | sbl1 | pmic | storsec | multiimgoem | multiimgqti | featenabler | apdp | msadp | \
            secdata | ddr | limits | toolsfv | qweslicstore | spunvm | \
            modem | modemst1 | modemst2 | fsg | fsc | persist | efs | sec | frp | devinfo | \
            ssd | keystore | prov | dip | mdtp | mdtpsecapp | dsp | \
            preloader | preloader_raw | lk | tee | tee1 | tee2 | sspm | spmfw | scp | mcupm | dpm | \
            gz | gz1 | gz2 | pi_img | md1img | md1dsp | nvram | nvdata | nvcfg | protect1 | protect2 | \
            proinfo | seccfg | efuse | sec1 | otp | persistent) CAT=critical ;;
        *) CAT=other ;;
    esac
}

# Letters, digits, dot, dash and underscore; anything else becomes "_".
safe_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}
