# The installed root modules, and where they get in each other's way. Read-only: it lists files
# and reads module.prop and system.prop, nothing more.
#
# Three kinds of conflict:
#   file     two or more modules put the same file in place; only one copy is used
#   replace  a module replaces a whole folder (.replace), hiding files another module adds there
#   prop     modules set the same system.prop property to different values; the last one wins
#
# vendor/, product/, system_ext/ and odm/ at a module's top level are the same places as
# system/vendor/ and so on, so both spellings are compared as one.

MOD_DIRS="system vendor product system_ext odm"

# fbs modules
modules_json() {
    _root=$R/data/adb/modules
    _w=$RUN/scan
    rm -rf "$_w"
    mkdir -p "$_w" || {
        echo '{"error":"run-dir"}'
        return 1
    }
    : > "$_w/files"
    : > "$_w/repl"
    : > "$_w/props"

    printf '{"root":"/data/adb/modules","modules":['
    _msep=
    for _m in "$_root"/*/; do
        _m=${_m%/}
        [ -f "$_m/module.prop" ] || continue
        _id=${_m##*/}
        _name=
        _ver=
        _author=
        while IFS='=' read -r _k _v; do
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

        _nfiles=0
        if [ $_live = true ] && [ $_mount = true ]; then
            (
                cd "$_m" || exit 0
                for _p in $MOD_DIRS; do
                    [ -d "$_p" ] && find "$_p" \( -type f -o -type l \) 2>/dev/null
                done
            ) | sed -E 's#^(vendor|product|system_ext|odm)/#system/\1/#' > "$_w/one"
            grep '/\.replace$' "$_w/one" | sed -e 's#/\.replace$##' -e "s#^#/#" -e "s#\$#$TAB$_id#" >> "$_w/repl"
            grep -v '/\.replace$' "$_w/one" | sed -e "s#^#/#" -e "s#\$#$TAB$_id#" > "$_w/mine"
            _nfiles=$(wc -l < "$_w/mine")
            cat "$_w/mine" >> "$_w/files"
        fi

        _nprops=0
        if [ $_live = true ] && [ -f "$_m/system.prop" ]; then
            tr -d '\r' < "$_m/system.prop" | grep -v '^[[:space:]]*#' | grep '=' |
                sed -e "s#=#$TAB#" -e "s#\$#$TAB$_id#" > "$_w/mine"
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

        printf '%s{"id":"%s","name":%s,"version":%s,"author":%s,"enabled":%s,"removing":%s,"mount":%s,"files":%s,"props":%s,"scripts":[%s],"webui":%s,"action":%s}' \
            "$_msep" "$_id" "$(js "${_name:-$_id}")" "$(js "$_ver")" "$(js "$_author")" \
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
    while IFS="$TAB" read -r _d _by; do
        grep -F "$_d/" "$_w/sorted" > "$_w/inside" || continue
        _hit=
        while IFS="$TAB" read -r _p _id; do
            [ "$_id" = "$_by" ] && continue
            case $_p in "$_d"/*) ;; *) continue ;; esac
            case " $_hit " in *" $_id "*) ;; *) _hit="$_hit $_id" ;; esac
        done < "$_w/inside"
        [ -n "$_hit" ] || continue
        printf '%s{"kind":"replace","path":%s,"by":"%s","modules":[%s]}' \
            "$_csep" "$(js "$_d")" "$_by" "$(id_list $_hit)"
        _csep=,
    done < "$_w/repl"

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
        _vals="$_vals${_vals:+,}{\"module\":\"$_id\",\"value\":$(js "$_v")}"
    done < "$_w/props.s"
    [ -n "$_key" ] && prop_conflict

    printf ']}\n'
    rm -rf "$_w"
}

# '"a","b"' from 'a b'.
id_list() {
    _l=
    for _i in "$@"; do _l="$_l${_l:+,}\"$_i\""; done
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
