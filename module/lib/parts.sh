# Partitions under by-name, and the logical partitions inside super.

# Prints "name dev" for every partition, plus the MediaTek preloader on eMMC (mmcblk0boot0),
# which has no by-name link on most phones.
part_list() {
    _dir=$(byname_dir) || return 1
    _pre=0
    for _l in "$_dir"/*; do
        [ -e "$_l" ] || continue
        _n=${_l##*/}
        _d=$(readlink -f "$_l")
        echo "$_n ${_d##*/}"
        case $_n in preloader*) _pre=1 ;; esac
    done
    if [ $_pre = 0 ] && [ -e "$R/dev/block/mmcblk0boot0" ]; then
        echo "preloader_raw mmcblk0boot0"
    fi
}

parts_json() {
    _slot=$(current_slot)
    if ! _dir=$(byname_dir); then
        printf '{"dir":null,"slot":%s,"parts":[]}\n' "$(js "$_slot")"
        return
    fi
    printf '{"dir":%s,"slot":%s,"parts":[' "$(js "${_dir#"$R"}")" "$(js "$_slot")"
    _sep=
    # Partition and block device names are plain [A-Za-z0-9_.-], so they go out unescaped.
    part_list | while read -r _n _d; do
        rd "$R/sys/class/block/$_d/size"; num "$REPLY"
        category "$_n"
        printf '%s{"name":"%s","dev":"%s","sectors":%s,"cat":"%s"}' "$_sep" "$_n" "$_d" "$N" "$CAT"
        _sep=,
    done
    printf ']}\n'
}

# lpdump (Android 10 and later) knows both slots and the groups. Without it, fall back to what
# device-mapper has mapped right now, which is the current slot only.
super_json() {
    _slot=$(current_slot)
    if command -v lpdump >/dev/null 2>&1; then
        _o=$(lpdump -j 2>/dev/null)
        case $_o in
            '{'*)
                printf '{"source":"lpdump","slot":%s,"lp":%s}\n' "$(js "$_slot")" "$_o"
                return
                ;;
        esac
    fi
    _ss=null
    if _dir=$(byname_dir) && [ -e "$_dir/super" ]; then
        _t=$(readlink -f "$_dir/super")
        rd "$R/sys/class/block/${_t##*/}/size"; num "$REPLY"; _ss=$N
    fi
    printf '{"source":"mapper","slot":%s,"super_sectors":%s,"parts":[' "$(js "$_slot")" "$_ss"
    _sep=
    for _l in "$R"/dev/block/mapper/*; do
        [ -e "$_l" ] || continue
        _n=${_l##*/}
        # control is the device-mapper node; userdata may be mapped for encryption;
        # names with a dash are snapshot pieces (system_a-cow, system_a-base).
        case $_n in control | userdata | *-*) continue ;; esac
        _d=$(readlink -f "$_l")
        rd "$R/sys/class/block/${_d##*/}/size"; num "$REPLY"
        printf '%s{"name":"%s","sectors":%s}' "$_sep" "$_n" "$N"
        _sep=,
    done
    printf ']}\n'
}
