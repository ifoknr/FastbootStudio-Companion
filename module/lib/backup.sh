# Backups, in the same layout as the Windows app's Backup page, so either side can check or
# restore them:
#   <DATA>/Backups/<model>_<serial>_<yyyyMMdd-HHmmss>/
#     <partition>.img
#     SHA256SUMS        "hash  name.img", as sha256sum writes it
#     backup-info.txt   tab-separated header and a partition / bytes / sha256 table
#
# Long jobs print one JSON object per line so the WebUI can show progress as it goes.

# fbs backup critical|boot|full
backup_run() {
    _set=$1
    case $_set in
        critical | boot | full) ;;
        *)
            echo '{"event":"error","msg":"usage: fbs backup critical|boot|full"}'
            return 2
            ;;
    esac

    mkdir -p "$RUN"
    if [ -r "$RUN/backup.pid" ] && rd "$RUN/backup.pid" && kill -0 "$REPLY" 2>/dev/null; then
        echo '{"event":"error","msg":"busy"}'
        return 1
    fi
    echo $$ > "$RUN/backup.pid"
    trap 'rm -f "$RUN/backup.pid"' EXIT

    _slot=$(current_slot)
    _plan=
    _kb=0
    _count=0
    _rows=$(part_list) || {
        echo '{"event":"error","msg":"no-by-name"}'
        return 1
    }
    # Word splitting on purpose: one "name dev" pair per line.
    # shellcheck disable=SC2086
    set -- $_rows
    while [ $# -ge 2 ]; do
        _n=$1
        _d=$2
        shift 2
        category "$_n"
        case $_set:$CAT in
            *:never) continue ;;
            critical:critical | full:*) ;;
            boot:boot)
                # The current slot only; unslotted boot partitions are kept.
                case $_n in
                    *_a | *_b) [ -n "$_slot" ] && [ "${_n%"$_slot"}" = "$_n" ] && continue ;;
                esac
                ;;
            *) continue ;;
        esac
        rd "$R/sys/class/block/$_d/size"
        num "$REPLY"
        [ "$N" = null ] && continue
        _kb=$((_kb + N / 2))
        _count=$((_count + 1))
        _plan="$_plan $_n:$_d"
    done

    if [ $_count = 0 ]; then
        echo '{"event":"error","msg":"nothing"}'
        return 1
    fi

    mkdir -p "$DATA/Backups" || {
        echo '{"event":"error","msg":"storage"}'
        return 1
    }
    _free=$(df -Pk "$DATA/Backups" 2>/dev/null | tail -n 1 | { read -r _ _ _ _a _; echo "$_a"; })
    num "$_free"
    # Keep 256 MiB spare so a full backup never fills the phone to the last byte.
    if [ "$N" != null ] && [ $((_kb + 262144)) -gt "$N" ]; then
        printf '{"event":"error","msg":"space","need_kb":%s,"free_kb":%s}\n' "$_kb" "$N"
        return 1
    fi

    _model=$(prop ro.product.model)
    _serial=$(prop ro.serialno)
    _name="$(safe_name "${_model:-device}")_$(safe_name "${_serial:-unknown}")_$(date +%Y%m%d-%H%M%S)"
    _out=$DATA/Backups/$_name
    mkdir -p "$_out" || {
        echo '{"event":"error","msg":"storage"}'
        return 1
    }
    printf '{"event":"plan","set":"%s","folder":%s,"count":%s,"kb":%s}\n' "$_set" "$(js "$_name")" "$_count" "$_kb"

    _table=
    _saved=0
    _failed=0
    for _p in $_plan; do
        _n=${_p%%:*}
        _d=${_p#*:}
        rd "$R/sys/class/block/$_d/size"
        printf '{"event":"start","name":"%s","kb":%s}\n' "$_n" "$((REPLY / 2))"
        if _err=$(dd if="$R/dev/block/$_d" of="$_out/$_n.img" bs=4194304 2>&1); then
            _h=$(cd "$_out" && sha256sum "$_n.img")
            _h=${_h%% *}
            _bytes=$(stat -c %s "$_out/$_n.img")
            printf '%s  %s\n' "$_h" "$_n.img" >> "$_out/SHA256SUMS"
            _table="$_table$_n$TAB$_bytes$TAB$_h$NL"
            _saved=$((_saved + 1))
            printf '{"event":"done","name":"%s","bytes":"%s","sha256":"%s"}\n' "$_n" "$_bytes" "$_h"
        else
            rm -f "$_out/$_n.img"
            _failed=$((_failed + 1))
            printf '{"event":"fail","name":"%s","msg":%s}\n' "$_n" "$(js "$_err")"
        fi
    done

    if [ $_saved -gt 0 ]; then
        {
            echo "Fastboot Studio backup"
            printf 'date\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z' | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')"
            printf 'serial\t%s\n' "$_serial"
            printf 'model\t%s\n' "$_model"
            printf 'product\t%s\n' "$(prop ro.product.name)"
            printf 'mode\tcompanion\n'
            printf 'source\t%s\n' "/dev/block/by-name"
            echo ""
            printf 'partition\tbytes\tsha256\n'
            printf '%s' "$_table"
        } > "$_out/backup-info.txt"
    else
        rmdir "$_out" 2>/dev/null
    fi
    printf '{"event":"finish","folder":%s,"saved":%s,"failed":%s}\n' "$(js "$_name")" "$_saved" "$_failed"
}

# fbs backups: the backup folders on the phone, newest first.
backups_json() {
    printf '{"root":%s,"items":[' "$(js "$DATA/Backups")"
    _sep=
    # Folder names start with the model, so sort on the date at the end of the name.
    for _f in "$DATA"/Backups/*/; do
        [ -d "$_f" ] || continue
        _f=${_f%/}
        echo "${_f##*_} ${_f##*/}"
    done | sort -r | while read -r _ _n; do
        _files=0
        [ -r "$DATA/Backups/$_n/SHA256SUMS" ] && _files=$(wc -l < "$DATA/Backups/$_n/SHA256SUMS")
        _kb=$(du -sk "$DATA/Backups/$_n" 2>/dev/null | { read -r _s _; echo "$_s"; })
        num "$_kb"
        printf '%s{"name":%s,"files":%s,"kb":%s,"sums":%s}' "$_sep" "$(js "$_n")" "$((_files + 0))" "$N" \
            "$([ -r "$DATA/Backups/$_n/SHA256SUMS" ] && echo true || echo false)"
        _sep=,
    done
    printf ']}\n'
}

# fbs verify <folder name>: re-hashes every file listed in SHA256SUMS.
verify_run() {
    case $1 in
        '' | */* | .*)
            echo '{"event":"error","msg":"usage: fbs verify <folder name>"}'
            return 2
            ;;
    esac
    _out=$DATA/Backups/$1
    if [ ! -r "$_out/SHA256SUMS" ]; then
        echo '{"event":"error","msg":"no-sums"}'
        return 1
    fi
    _ok=0
    _bad=0
    while read -r _want _file; do
        _file=${_file#\*}
        [ -n "$_file" ] || continue
        if [ ! -r "$_out/$_file" ]; then
            _state=missing
        else
            _got=$(cd "$_out" && sha256sum "$_file")
            if [ "${_got%% *}" = "$_want" ]; then _state=ok; else _state=bad; fi
        fi
        if [ $_state = ok ]; then _ok=$((_ok + 1)); else _bad=$((_bad + 1)); fi
        printf '{"event":"file","name":%s,"state":"%s"}\n' "$(js "$_file")" "$_state"
    done < "$_out/SHA256SUMS"
    printf '{"event":"finish","ok":%s,"bad":%s}\n' "$_ok" "$_bad"
}
