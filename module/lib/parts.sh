# Partitions under by-name, and the logical partitions inside super.

# Prints "name dev" for every partition, plus the MediaTek preloader on eMMC (mmcblk0boot0),
# which has no by-name link on most phones.
#
# A third word says how sure it is that the link is a partition: "part", or "odd" when only
# one of the two signs of a whole disk shows. Android 10 and later also link the disks
# themselves under by-name (sda, mmcblk0, mmcblk0boot0), under their own device name; and a
# disk has no "partition" file in /sys/class/block/<dev>. With both signs it is a disk and is
# left out. With one (a partition nobody named, or a name that points at a whole device, as
# MediaTek's preloader_a does on UFS) it is listed, and backup_run keeps it out of the sets
# unless its name is a known one.
# A name with anything but letters, digits, dot, dash, plus and underscore is not listed:
# the lines here are split on spaces, and the name becomes a file name.
part_list() {
    _dir=$(byname_dir) || return 1
    _pre=0
    for _l in "$_dir"/*; do
        [ -e "$_l" ] || continue
        _n=${_l##*/}
        case $_n in *[!A-Za-z0-9._+-]*) continue ;; esac
        _d=$(readlink -f "$_l")
        _d=${_d##*/}
        case $_d in '' | *[!A-Za-z0-9._+-]*) continue ;; esac
        _k=part
        if [ -d "$R/sys/class/block/$_d" ] && [ ! -e "$R/sys/class/block/$_d/partition" ]; then
            [ "$_n" = "$_d" ] && continue
            _k=odd
        elif [ "$_n" = "$_d" ]; then
            _k=odd
        fi
        echo "$_n $_d $_k"
        case $_n in preloader*) _pre=1 ;; esac
    done
    if [ $_pre = 0 ] && [ -e "$R/dev/block/mmcblk0boot0" ]; then
        echo "preloader_raw mmcblk0boot0 part"
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
    # (part_list checks that; js costs nothing for such names and keeps the JSON whole anyway.)
    # "sure" is false for a link that may be a whole disk: it is in no backup set as "other".
    part_list | while read -r _n _d _k; do
        rd "$R/sys/class/block/$_d/size"; num "$REPLY"
        category "$_n"
        _sure=true
        [ "$_k" = odd ] && _sure=false
        printf '%s{"name":%s,"dev":%s,"sectors":%s,"cat":"%s","sure":%s}' "$_sep" "$(js "$_n")" "$(js "$_d")" "$N" "$CAT" "$_sure"
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
        printf '%s{"name":%s,"sectors":%s}' "$_sep" "$(js "$_n")" "$N"
        _sep=,
    done
    printf ']}\n'
}
