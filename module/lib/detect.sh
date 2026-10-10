# What the phone is: identity, boot chain state, kernel, root manager and hardware health.
# collect() fills I_* variables once; info_json and report_text print them.

soc_vendor() {
    _m=$(prop ro.soc.manufacturer | tr 'A-Z' 'a-z')
    case $_m in
        mediatek* | mtk*) echo mediatek; return ;;
        qti* | qualcomm*) echo qualcomm; return ;;
        spreadtrum* | unisoc*) echo unisoc; return ;;
        samsung*) echo samsung; return ;;
        google*) echo google; return ;;
    esac
    for _p in "$(prop ro.board.platform | tr 'A-Z' 'a-z')" "$(prop ro.hardware | tr 'A-Z' 'a-z')"; do
        case $_p in
            mt[0-9]*) echo mediatek; return ;;
            msm* | sdm* | sm[0-9]* | qcom | lahaina | kona | taro | kalama | pineapple | sun | holi | \
                bengal | lito | trinket | atoll | parrot | crow | blair | monaco | niobe | cliffs | \
                volcano | pitti) echo qualcomm; return ;;
            ums* | sp9* | s9863*) echo unisoc; return ;;
            exynos* | universal* | s5e* | erd*) echo samsung; return ;;
            gs[0-9]* | zuma* | laguna*) echo google; return ;;
        esac
    done
    echo unknown
}

root_manager() {
    if [ -e "$R/data/adb/ksud" ]; then
        echo KernelSU
    elif [ -e "$R/data/adb/apd" ]; then
        echo APatch
    elif [ -d "$R/data/adb/magisk" ]; then
        echo Magisk
    else
        echo unknown
    fi
}

# "5.15.148-android13-8-g1234" gives "5.15-android13". Older, non-GKI kernels give nothing.
kmi_of() {
    printf '%s' "$1" | sed -n 's/^\([0-9]*\.[0-9]*\)\.[0-9]*-\(android[0-9]*\)-.*/\1-\2/p'
}

# UFS and eMMC both report wear in steps of 10%: 0x01 is 0-10% used, 0x0B is past the rated life.
storage_json() {
    for _f in "$R"/sys/devices/platform/*/health_descriptor "$R"/sys/devices/platform/soc/*/health_descriptor \
        "$R"/sys/devices/platform/*/*/health_descriptor "$R"/sys/bus/platform/drivers/*/*/health_descriptor; do
        [ -d "$_f" ] || continue
        rd "$_f/life_time_estimation_a"; _a=$REPLY
        rd "$_f/life_time_estimation_b"; _b=$REPLY
        rd "$_f/eol_info"; _e=$REPLY
        printf '{"type":"ufs","life_a":%s,"life_b":%s,"eol":%s}' "$(js "$_a")" "$(js "$_b")" "$(js "$_e")"
        return
    done
    for _f in "$R"/sys/class/mmc_host/mmc0/mmc0:*; do
        [ -r "$_f/life_time" ] || continue
        rd "$_f/life_time"
        set -- $REPLY
        rd "$_f/pre_eol_info"
        printf '{"type":"emmc","life_a":%s,"life_b":%s,"eol":%s}' "$(js "${1:-}")" "$(js "${2:-}")" "$(js "$REPLY")"
        return
    done
    printf null
}

collect() {
    I_MODEL=$(prop ro.product.model)
    I_BRAND=$(prop ro.product.brand)
    I_DEVICE=$(prop ro.product.device)
    I_PRODUCT=$(prop ro.product.name)
    I_SERIAL=$(prop ro.serialno)
    I_ANDROID=$(prop ro.build.version.release)
    I_SDK=$(prop ro.build.version.sdk)
    I_PATCH=$(prop ro.build.version.security_patch)
    I_BUILD=$(prop ro.build.display.id)
    I_PLATFORM=$(prop ro.board.platform)
    I_SOC=$(soc_vendor)
    I_ARCH=$(prop ro.product.cpu.abi)
    I_SLOT=$(current_slot)
    I_DYNAMIC=$(prop ro.boot.dynamic_partitions)
    I_TREBLE=$(prop ro.treble.enabled)
    I_VNDK=$(prop ro.vndk.version)

    # The bootloader's own words first; a hiding module may have rewritten the property.
    I_VBSTATE=$(bootarg verifiedbootstate)
    _p=$(prop ro.boot.verifiedbootstate)
    I_VB_SPOOFED=false
    if [ -z "$I_VBSTATE" ]; then
        I_VBSTATE=$_p
    elif [ -n "$_p" ] && [ "$_p" != "$I_VBSTATE" ]; then
        I_VB_SPOOFED=true
    fi
    I_DEVSTATE=$(bootarg vbmeta.device_state)
    [ -n "$I_DEVSTATE" ] || I_DEVSTATE=$(prop ro.boot.vbmeta.device_state)
    I_LOCKED=$(prop ro.boot.flash.locked)

    rd "$R/proc/sys/kernel/osrelease"; I_KERNEL=$REPLY
    I_KMI=$(kmi_of "$I_KERNEL")
    rd "$R/sys/fs/selinux/enforce"
    case $REPLY in 1) I_SELINUX=Enforcing ;; 0) I_SELINUX=Permissive ;; *) I_SELINUX=$(getenforce 2>/dev/null) ;; esac
    I_ROOT=$(root_manager)
    I_REASON=$(prop sys.boot.reason)
    [ -n "$I_REASON" ] || I_REASON=$(prop ro.boot.bootreason)

    _bat=$R/sys/class/power_supply/battery
    rd "$_bat/capacity"; num "$REPLY"; I_BAT_LEVEL=$N
    rd "$_bat/cycle_count"; num "$REPLY"; I_BAT_CYCLES=$N
    rd "$_bat/temp"; num "$REPLY"; I_BAT_TEMP=$N
    rd "$_bat/charge_full"; num "$REPLY"; _full=$N
    rd "$_bat/charge_full_design"; num "$REPLY"; _design=$N
    I_BAT_HEALTH=null
    # Both are in µAh (about 5 000 000), so the product stays inside 32 bits.
    if [ "$_full" != null ] && [ "$_design" != null ] && [ "$_design" -gt 0 ]; then
        I_BAT_HEALTH=$((_full * 100 / _design))
    fi

    I_MEM_TOTAL=null
    I_MEM_AVAIL=null
    if [ -r "$R/proc/meminfo" ]; then
        while read -r _k _v _u; do
            case $_k in
                MemTotal:) I_MEM_TOTAL=$_v ;;
                MemAvailable:) I_MEM_AVAIL=$_v ;;
            esac
        done < "$R/proc/meminfo"
    fi
}

info_json() {
    collect
    printf '{"fbs":%s,"channel":%s,"model":%s,"brand":%s,"device":%s,"product":%s,' \
        "$(js "$FBS_VERSION")" "$(js "$FBS_CHANNEL")" "$(js "$I_MODEL")" "$(js "$I_BRAND")" "$(js "$I_DEVICE")" "$(js "$I_PRODUCT")"
    printf '"android":%s,"sdk":%s,"patch":%s,"build":%s,' \
        "$(js "$I_ANDROID")" "$(js "$I_SDK")" "$(js "$I_PATCH")" "$(js "$I_BUILD")"
    printf '"platform":%s,"soc":%s,"arch":%s,"slot":%s,"dynamic":%s,"treble":%s,"vndk":%s,' \
        "$(js "$I_PLATFORM")" "$(js "$I_SOC")" "$(js "$I_ARCH")" "$(js "$I_SLOT")" \
        "$(jb "$I_DYNAMIC")" "$(jb "$I_TREBLE")" "$(js "$I_VNDK")"
    printf '"boot":{"vbstate":%s,"device_state":%s,"locked":%s,"spoofed":%s},' \
        "$(js "$I_VBSTATE")" "$(js "$I_DEVSTATE")" "$(jb "$I_LOCKED")" "$I_VB_SPOOFED"
    printf '"kernel":%s,"kmi":%s,"selinux":%s,"root":%s,"boot_reason":%s,' \
        "$(js "$I_KERNEL")" "$(js "$I_KMI")" "$(js "$I_SELINUX")" "$(js "$I_ROOT")" "$(js "$I_REASON")"
    printf '"battery":{"level":%s,"health":%s,"cycles":%s,"temp_dc":%s},' \
        "$I_BAT_LEVEL" "$I_BAT_HEALTH" "$I_BAT_CYCLES" "$I_BAT_TEMP"
    printf '"memory":{"total_kb":%s,"avail_kb":%s},"storage":%s}\n' \
        "$I_MEM_TOTAL" "$I_MEM_AVAIL" "$(storage_json)"
}

# key=value lines for Fastboot Studio on Windows, which reads them over adb (through su) and
# keeps them per serial number: the kernel and patch level it checks a boot image against
# before flashing, and what the device page shows about the phone. The first five keys are the
# ones the app also reads without root (DeviceFacts.Command); values never contain newlines.
facts_text() {
    collect
    _c=$(modules_json 2>/dev/null | grep -o '"kind":' | wc -l)
    _vpatch=$(prop ro.vendor.build.security_patch)
    for _kv in "kernel=$I_KERNEL" "patch=$I_PATCH" "vendor_patch=$_vpatch" "model=$I_MODEL" "android=$I_ANDROID" \
        "companion=$FBS_VERSION $FBS_CHANNEL" "root=$I_ROOT" "avb=$I_VBSTATE" "device_state=$I_DEVSTATE" \
        "spoofed=$I_VB_SPOOFED" "selinux=$I_SELINUX" "kmi=$I_KMI" "conflicts=$((_c + 0))"; do
        printf '%s\n' "$_kv" | tr -d '\r\t'
    done
}

# Plain text for the Action button's console.
report_text() {
    collect
    _n=0
    if _dir=$(byname_dir); then
        for _l in "$_dir"/*; do [ -e "$_l" ] && _n=$((_n + 1)); done
    fi
    _ab=; [ -n "$I_SLOT" ] && _ab=" · A/B"
    _dyn=; [ "$I_DYNAMIC" = true ] && _dyn=" · dynamic"
    _vb=$I_VBSTATE; [ "$I_VB_SPOOFED" = true ] && _vb="$_vb (property says otherwise)"
    echo "Fastboot Studio Companion $FBS_VERSION ($FBS_CHANNEL)"
    echo ""
    echo "Device      $I_BRAND $I_MODEL ($I_DEVICE)"
    echo "Chip        $I_PLATFORM · $I_SOC · $I_ARCH"
    echo "Android     $I_ANDROID (SDK $I_SDK) · patch $I_PATCH"
    echo "Slot        ${I_SLOT:-none}$_ab$_dyn"
    echo "Boot        AVB ${_vb:-unknown} · ${I_DEVSTATE:-unknown}"
    echo "Kernel      $I_KERNEL"
    [ -n "$I_KMI" ] && echo "KMI         $I_KMI"
    echo "SELinux     $I_SELINUX"
    echo "Root        $I_ROOT"
    echo "Partitions  $_n"
    echo "Last boot   ${I_REASON:-unknown}"
    _c=$(modules_json 2>/dev/null | grep -o '"kind":' | wc -l)
    echo "Conflicts   $((_c + 0)) between modules"
    echo ""
    echo "Open the WebUI for partitions, live logs and backups."
}

# One line, every second, while the Device tab is open. Builtins only.
cpu_json() {
    printf '{"cores":['
    _sep=
    for _c in "$R"/sys/devices/system/cpu/cpu[0-9] "$R"/sys/devices/system/cpu/cpu[0-9][0-9]; do
        [ -d "$_c" ] || continue
        rd "$_c/cpufreq/scaling_cur_freq"; num "$REPLY"; _cur=$N
        rd "$_c/cpufreq/cpuinfo_max_freq"; num "$REPLY"; _max=$N
        printf '%s{"cur":%s,"max":%s}' "$_sep" "$_cur" "$_max"
        _sep=,
    done
    _hot=null
    for _z in "$R"/sys/class/thermal/thermal_zone*; do
        rd "$_z/type"
        case $REPLY in *cpu* | *CPU* | *soc* | mtktscpu*) ;; *) continue ;; esac
        rd "$_z/temp"; num "$REPLY"
        [ "$N" = null ] && continue
        if [ "$_hot" = null ] || [ "$N" -gt "$_hot" ]; then _hot=$N; fi
    done
    _total=null
    _avail=null
    if [ -r "$R/proc/meminfo" ]; then
        while read -r _k _v _u; do
            case $_k in
                MemTotal:) _total=$_v ;;
                MemAvailable:) _avail=$_v ;;
                SwapTotal:) _swt=$_v ;;
                SwapFree:) _swf=$_v ;;
            esac
        done < "$R/proc/meminfo"
    fi
    _swap=null
    [ -n "${_swt:-}" ] && [ -n "${_swf:-}" ] && _swap=$((_swt - _swf))
    rd "$R/sys/class/power_supply/battery/temp"; num "$REPLY"
    printf '],"cpu_temp":%s,"battery_temp_dc":%s,"mem_total_kb":%s,"mem_avail_kb":%s,"swap_used_kb":%s}\n' \
        "$_hot" "$N" "$_total" "$_avail" "$_swap"
}
