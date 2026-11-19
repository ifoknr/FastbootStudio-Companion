# The installed root modules, and where they get in each other's way. Read-only: it lists files
# and reads module.prop and system.prop, nothing more.
#
# Three kinds of conflict:
#   file     two or more modules put the same file in place; only one copy is used
#   replace  a module replaces a whole folder (.replace), hiding files another module adds there
#   prop     modules set the same system.prop property to different values; the last one wins
#   remove   a module removes a file or folder (a whiteout: a character device in its place)
#            that another module puts there or adds files inside
#
# vendor/, product/, system_ext/ and odm/ at a module's top level are the same places as
# system/vendor/ and so on, so both spellings are compared as one.

MOD_DIRS="system vendor product system_ext odm"

# fbs modules
modules_json() {
    _root=$R/data/adb/modules
    _w=$RUN/scan
    # One folder per process (the WebUI, the Action button and the Windows app may all scan
    # at once), removed when the process ends however it ends. What a killed scan left
    # behind goes too, once its process is gone.
    for _old in "$RUN"/scan "$RUN"/scan.*; do
        [ -d "$_old" ] || continue
        case ${_old##*.} in
            *[!0-9]*) ;;
            *) kill -0 "${_old##*.}" 2>/dev/null && continue ;;
        esac
        rm -rf "$_old"
    done
    _w=$RUN/scan.$$
    trap 'rm -rf "$RUN/scan.$$"' EXIT
    rm -rf "$_w"
    mkdir -p "$_w" || {
        echo '{"error":"run-dir"}'
        return 1
    }
    : > "$_w/files"
    : > "$_w/repl"
    : > "$_w/props"
    : > "$_w/gone"

    printf '{"root":"/data/adb/modules","modules":['
    _msep=
    for _m in "$_root"/*/; do
        _m=${_m%/}
        [ -f "$_m/module.prop" ] || continue
        _id=${_m##*/}
        _name=
        _ver=
        _author=
        # "|| [ -n ... ]": a last line without a newline still counts.
        while IFS='=' read -r _k _v || [ -n "$_k" ]; do
            case $_k in
                name) _name=$_v ;;
                version) _ver=$_v ;;
                author) _author=$_v ;;
            esac
        done < "$_m/module.prop"

        _on=true
        _removing=false
        _mount=true
        [ -e "$_m/disable" ] && _on=false
        [ -e "$_m/remove" ] && _removing=true
        [ -e "$_m/skip_mount" ] && _mount=false
        _live=$_on
        [ $_removing = true ] && _live=false
        # A root manager takes only letters, digits, dot, dash and underscore in an id. A
        # folder named otherwise is listed, but not scanned: its name would not survive the
        # tab-separated lists below.
        case $_id in *[!A-Za-z0-9._-]*) _live=false ;; esac

        _nfiles=0
        # KernelSU and APatch move system/vendor (product, ...) to the module's top level and
        # leave a link system/vendor -> ../vendor behind. The link is not a file the module
        # puts in place, so it is dropped: every such module has one.
        if [ $_live = true ] && [ $_mount = true ]; then
            (
                cd "$_m" || exit 0
                for _p in $MOD_DIRS; do
                    [ -d "$_p" ] && find "$_p" \( -type f -o -type l \) 2>/dev/null
                done
            ) | sed -E -e 's#^(vendor|product|system_ext|odm)/#system/\1/#' \
                -e '/^(system\/)?(vendor|product|system_ext|odm)$/d' > "$_w/one"
            grep '/\.replace$' "$_w/one" | sed -e 's#/\.replace$##' -e "s#^#/#" -e "s#\$#$TAB$_id#" >> "$_w/repl"
            grep -v '/\.replace$' "$_w/one" | sed -e "s#^#/#" -e "s#\$#$TAB$_id#" > "$_w/mine"
            _nfiles=$(wc -l < "$_w/mine")
            cat "$_w/mine" >> "$_w/files"
            # Whiteouts. Any character device in a module's tree is one (root managers make
            # them with "mknod c 0 0"), so the device numbers are not read: stat spells them
            # differently from one toolbox to the next.
            (
                cd "$_m" || exit 0
                for _p in $MOD_DIRS; do
                    [ -d "$_p" ] && [ ! -L "$_p" ] && find "$_p" -type c 2>/dev/null
                done
            ) | sed -E -e 's#^(vendor|product|system_ext|odm)/#system/\1/#' -e "s#^#/#" -e "s#\$#$TAB$_id#" >> "$_w/gone"
        fi

        _nprops=0
        if [ $_live = true ] && [ -f "$_m/system.prop" ]; then
            # Spaces around the key and the value go here, before the sort: "ro.x" and
            # " ro.x " are one property and have to end up next to each other.
            tr -d '\r' < "$_m/system.prop" | grep -v '^[[:space:]]*#' | grep '=' |
                sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s#[[:space:]]*=[[:space:]]*#$TAB#" \
                    -e "s#\$#$TAB$_id#" > "$_w/mine"
            _nprops=$(wc -l < "$_w/mine")
            cat "$_w/mine" >> "$_w/props"
        fi

        _scripts=
        for _s in post-fs-data.sh post-mount.sh service.sh boot-completed.sh; do
            [ -f "$_m/$_s" ] && _scripts="$_scripts${_scripts:+,}\"$_s\""
        done
        _webui=false
        [ -f "$_m/webroot/index.html" ] && _webui=true
        _action=false
        [ -f "$_m/action.sh" ] && _action=true

        printf '%s{"id":%s,"name":%s,"version":%s,"author":%s,"enabled":%s,"removing":%s,"mount":%s,"files":%s,"props":%s,"scripts":[%s],"webui":%s,"action":%s}' \
            "$_msep" "$(js "$_id")" "$(js "${_name:-$_id}")" "$(js "$_ver")" "$(js "$_author")" \
            "$_on" "$_removing" "$_mount" "$((_nfiles + 0))" "$((_nprops + 0))" "$_scripts" "$_webui" "$_action"
        _msep=,
    done
    printf '],"conflicts":['
    _csep=

    # file: one record per shared path ("a b<TAB>/system/…"), then grouped by the set of modules,
    # so two font modules that share 300 files make one entry, not 300.
    sort -t "$TAB" -k1,1 -k2,2 "$_w/files" > "$_w/sorted"
    : > "$_w/shared"
    _prev=
    _ids=
    _cnt=0
    while IFS="$TAB" read -r _p _id; do
        if [ "$_p" = "$_prev" ]; then
            case " $_ids " in
                *" $_id "*) ;;
                *) _ids="$_ids $_id"; _cnt=$((_cnt + 1)) ;;
            esac
        else
            [ $_cnt -gt 1 ] && printf '%s%s%s\n' "$_ids" "$TAB" "$_prev" >> "$_w/shared"
            _prev=$_p
            _ids=$_id
            _cnt=1
        fi
    done < "$_w/sorted"
    [ $_cnt -gt 1 ] && printf '%s%s%s\n' "$_ids" "$TAB" "$_prev" >> "$_w/shared"

    sort "$_w/shared" > "$_w/shared.s"
    _set=
    _paths=
    _n=0
    while IFS="$TAB" read -r _s _p; do
        if [ "$_s" != "$_set" ]; then
            [ -n "$_set" ] && file_conflict
            _set=$_s
            _paths=
            _n=0
        fi
        _n=$((_n + 1))
        # The first 12 paths are enough to tell what the modules fight over.
        [ $_n -le 12 ] && _paths="$_paths${_paths:+,}$(js "$_p")"
    done < "$_w/shared.s"
    [ -n "$_set" ] && file_conflict

    # replace: a folder one module replaces, against files other modules add inside it.
    hidden_conflicts replace "$_w/repl"
    # remove: a path one module removes, against the same path or files inside it from others.
    hidden_conflicts remove "$_w/gone"

    # prop: the same key from two or more modules with different values.
    sort -t "$TAB" -k1,1 "$_w/props" > "$_w/props.s"
    _key=
    _vals=
    _first=
    _differ=false
    _count=0
    while IFS="$TAB" read -r _k _v _id; do
        _k=$(printf '%s' "$_k" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        _v=$(printf '%s' "$_v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [ "$_k" != "$_key" ]; then
            [ -n "$_key" ] && prop_conflict
            _key=$_k
            _vals=
            _first=$_v
            _differ=false
            _count=0
        fi
        [ "$_v" = "$_first" ] || _differ=true
        _count=$((_count + 1))
        _vals="$_vals${_vals:+,}{\"module\":$(js "$_id"),\"value\":$(js "$_v")}"
    done < "$_w/props.s"
    [ -n "$_key" ] && prop_conflict

    printf ']}\n'
    rm -rf "$_w"
}

# hidden_conflicts <kind> <list of "path<TAB>module">: one conflict for every path in the list
# that other modules put files at or under.
hidden_conflicts() {
    while IFS="$TAB" read -r _d _by; do
        grep -F "$_d" "$_w/sorted" > "$_w/inside" || continue
        _hit=
        while IFS="$TAB" read -r _p _id; do
            [ "$_id" = "$_by" ] && continue
            case $_p in "$_d" | "$_d"/*) ;; *) continue ;; esac
            case " $_hit " in *" $_id "*) ;; *) _hit="$_hit $_id" ;; esac
        done < "$_w/inside"
        [ -n "$_hit" ] || continue
        # Word splitting on purpose: _hit is a space-separated list of module ids.
        # shellcheck disable=SC2086
        printf '%s{"kind":"%s","path":%s,"by":%s,"modules":[%s]}' \
            "$_csep" "$1" "$(js "$_d")" "$(js "$_by")" "$(id_list $_hit)"
        _csep=,
    done < "$2"
}

# '"a","b"' from 'a b'.
id_list() {
    _l=
    for _i in "$@"; do _l="$_l${_l:+,}$(js "$_i")"; done
    printf '%s' "$_l"
}

file_conflict() {
    # Word splitting on purpose: _set is a space-separated list of module ids.
    # shellcheck disable=SC2086
    printf '%s{"kind":"file","modules":[%s],"count":%s,"paths":[%s]}' \
        "$_csep" "$(id_list $_set)" "$_n" "$_paths"
    _csep=,
}

prop_conflict() {
    [ $_count -gt 1 ] && [ $_differ = true ] || return 0
    printf '%s{"kind":"prop","key":%s,"values":[%s]}' "$_csep" "$(js "$_key")" "$_vals"
    _csep=,
}
