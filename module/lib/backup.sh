# Backups, in the same layout as the Windows app's Backup page, so either side can check or
# restore them:
#   <DATA>/Backups/<model>_<serial>_<yyyyMMdd-HHmmss>/
#     <partition>.img
#     SHA256SUMS        "hash  name.img", as sha256sum writes it
#     backup-info.txt   tab-separated header and a partition / bytes / sha256 table
#
# A backup is written to a hidden .partial-<name> folder and gets its name when it is done, so
# Fastboot Studio's Phone page (which lists and copies these folders over adb) and fbs backups
# never see one that is still being written or was cut off.
#
# Long jobs print one JSON object per line so the WebUI can show progress as it goes.

# Says how far a copy has come, about once a second, while process $1 writes file $2:
#   {"event":"progress","name":<$3>,"bytes":"<size so far>","of":"<$4>"}
# The numbers are text: a size past 4 GiB does not fit mksh's 32-bit arithmetic, and none is
# done on them. dd's own progress (status=progress, a USR1 signal) differs between toybox,
# busybox and GNU, so the file's size is read instead; a line goes out only when it changed.
poll_copy() {
    _pl=
    while kill -0 "$1" 2>/dev/null; do
        sleep 1
        _pn=$(stat -c %s "$2" 2>/dev/null) || continue
        [ "$_pn" = "$_pl" ] || printf '{"event":"progress","name":%s,"bytes":"%s","of":"%s"}\n' "$(js "$3")" "$_pn" "$4"
        _pl=$_pn
    done
}

# fbs backup critical|boot|full
# fbs backup custom <partition> [<partition> ...]   the partitions named, and only those
backup_run() {
    _set=$1
    [ $# -gt 0 ] && shift
    case $_set in
        critical | boot | full) ;;
        custom)
            # The names are only ever compared with the ones part_list gives (below): none
            # is used to build a path or a command. One with an odd character cannot match
            # anyway, and is refused here with its own message.
            _want=
            for _n in "$@"; do
                case $_n in
                    '' | *[!A-Za-z0-9._+-]*)
                        printf '{"event":"error","msg":"bad-name","name":%s}\n' "$(js "$_n")"
                        return 2
                        ;;
                esac
                case " $_want " in *" $_n "*) ;; *) _want="$_want $_n" ;; esac
            done
            if [ -z "$_want" ]; then
                echo '{"event":"error","msg":"nothing"}'
                return 2
            fi
            ;;
        *)
            echo '{"event":"error","msg":"usage: fbs backup critical|boot|full | custom <partition>..."}'
            return 2
            ;;
    esac

    mkdir -p "$RUN"
    if [ -r "$RUN/backup.pid" ] && rd "$RUN/backup.pid" && kill -0 "$REPLY" 2>/dev/null; then
        echo '{"event":"error","msg":"busy"}'
        return 1
    fi
    echo $$ > "$RUN/backup.pid"
    # _partial is the folder being written; it goes too when the job is cut off (bin/fbs turns
    # a signal into an exit), so a half-written backup is not left for the next run to find.
    _partial=
    # JOB is the dd that is copying in the background, if one is: it must not outlive fbs.
    JOB=
    trap '[ -z "$JOB" ] || kill "$JOB" 2>/dev/null; rm -f "$RUN/backup.pid"; [ -z "$_partial" ] || rm -rf "$_partial"' EXIT

    _slot=$(current_slot)
    _plan=
    _kb=0
    _count=0
    _rows=$(part_list) || {
        echo '{"event":"error","msg":"no-by-name"}'
        return 1
    }
    # Word splitting on purpose: one "name dev" pair per line.
    # (and a third word, "part" or "odd": see part_list)
    # shellcheck disable=SC2086
    set -- $_rows
    while [ $# -ge 3 ]; do
        _n=$1
        _d=$2
        _k=$3
        shift 3
        category "$_n"
        # A link that may be a whole disk is copied only under a name from the lists in
        # category: as "other" (or super) it could be the whole phone, userdata included.
        case $_k:$CAT in
            odd:critical | odd:boot) ;;
            odd:*) continue ;;
        esac
        case $_set:$CAT in
            *:never) continue ;;
            critical:critical | full:*) ;;
            custom:*)
                case " $_want " in *" $_n "*) ;; *) continue ;; esac
                ;;
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

    # Every name asked for has to be in the plan: one that is not is unknown, userdata, a
    # link that may be a whole disk, or has no size. Nothing is copied then, rather than
    # a backup that silently lacks what was asked for.
    if [ "$_set" = custom ]; then
        for _n in $_want; do
            case " $_plan " in
                *" $_n:"*) ;;
                *)
                    printf '{"event":"error","msg":"bad-name","name":%s}\n' "$(js "$_n")"
                    return 1
                    ;;
            esac
        done
    fi
    if [ $_count = 0 ]; then
        echo '{"event":"error","msg":"nothing"}'
        return 1
    fi

    mkdir -p "$DATA/Backups" || {
        echo '{"event":"error","msg":"storage"}'
        return 1
    }
    # Left by a backup that was cut off (the phone restarted, the job was killed). Only one
    # backup runs at a time, so none of these is still being written.
    for _old in "$DATA"/Backups/.partial-*/; do
        [ -d "$_old" ] && rm -rf "${_old%/}"
    done
    free_kb "$DATA/Backups"
    # Keep 256 MiB spare so a full backup never fills the phone to the last byte.
    if [ "$N" != null ] && [ $((_kb + 262144)) -gt "$N" ]; then
        printf '{"event":"error","msg":"space","need_kb":%s,"free_kb":%s}\n' "$_kb" "$N"
        return 1
    fi

    _model=$(prop ro.product.model)
    _serial=$(prop ro.serialno)
    _name="$(safe_name "${_model:-device}")_$(safe_name "${_serial:-unknown}")_$(date +%Y%m%d-%H%M%S)"
    _out=$DATA/Backups/.partial-$_name
    mkdir -p "$_out" || {
        echo '{"event":"error","msg":"storage"}'
        return 1
    }
    _partial=$_out
    printf '{"event":"plan","set":"%s","folder":%s,"count":%s,"kb":%s}\n' "$_set" "$(js "$_name")" "$_count" "$_kb"

    _table=
    _saved=0
    _failed=0
    for _p in $_plan; do
        _n=${_p%%:*}
        _d=${_p#*:}
        rd "$R/sys/class/block/$_d/size"
        printf '{"event":"start","name":%s,"kb":%s}\n' "$(js "$_n")" "$((REPLY / 2))"
        bytes_of "$REPLY"
        # An image counts only when dd ended well, the file is as long as the partition and
        # its hash could be taken: a short copy must not pass for a backup.
        _bytes=
        _h=
        # A big partition (32 MiB and up) is copied in the background so its progress can be
        # reported; a small one is done before a second is over and is copied as before.
        if [ "$REPLY" -ge 65536 ]; then
            dd if="$R/dev/block/$_d" of="$_out/$_n.img" bs=4194304 2> "$_out/.dd-err" &
            JOB=$!
            poll_copy "$JOB" "$_out/$_n.img" "$_n" "$BYTES"
            wait "$JOB"
            _rc=$?
            JOB=
            _err=$(cat "$_out/.dd-err" 2>/dev/null)
            rm -f "$_out/.dd-err"
        else
            _err=$(dd if="$R/dev/block/$_d" of="$_out/$_n.img" bs=4194304 2>&1)
            _rc=$?
        fi
        if [ "$_rc" = 0 ]; then
            _bytes=$(stat -c %s "$_out/$_n.img" 2>/dev/null)
            if [ "$_bytes" != "$BYTES" ]; then
                _err="size: $_bytes of $BYTES bytes"
            else
                # Reading a big image back for its hash takes a while too: said, so the
                # WebUI can show it as its own step.
                printf '{"event":"hash","name":%s}\n' "$(js "$_n")"
                _h=$(cd "$_out" && sha256sum "$_n.img")
                _h=${_h%% *}
                case $_h in
                    *[!0-9a-f]*) _h= ;;
                esac
                [ ${#_h} -eq 64 ] || {
                    _h=
                    _err="sha256sum gave no hash"
                }
            fi
        fi
        if [ -n "$_h" ]; then
            printf '%s  %s\n' "$_h" "$_n.img" >> "$_out/SHA256SUMS"
            _table="$_table$_n$TAB$_bytes$TAB$_h$NL"
            _saved=$((_saved + 1))
            printf '{"event":"done","name":%s,"bytes":"%s","sha256":"%s"}\n' "$(js "$_n")" "$_bytes" "$_h"
        else
            rm -f "$_out/$_n.img"
            _failed=$((_failed + 1))
            printf '{"event":"fail","name":%s,"msg":%s}\n' "$(js "$_n")" "$(js "$_err")"
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
            printf 'set\t%s\n' "$_set"
            printf 'source\t%s\n' "/dev/block/by-name"
            echo ""
            printf 'partition\tbytes\tsha256\n'
            printf '%s' "$_table"
        } > "$_out/backup-info.txt"
        # On the disk before the folder gets its name: a finished backup is a written one.
        sync
        mv "$_out" "$DATA/Backups/$_name" || {
            echo '{"event":"error","msg":"storage"}'
            return 1
        }
    else
        rm -rf "$_out"
    fi
    _partial=
    printf '{"event":"finish","folder":%s,"saved":%s,"failed":%s}\n' "$(js "$_name")" "$_saved" "$_failed"
}

# fbs backups: the backup folders on the phone, newest first.
backups_json() {
    free_kb "$DATA/Backups"
    printf '{"root":%s,"free_kb":%s,"items":[' "$(js "$DATA/Backups")" "$N"
    _sep=
    # Folder names start with the model, so sort on the date at the end of the name.
    for _f in "$DATA"/Backups/*/; do
        [ -d "$_f" ] || continue
        _f=${_f%/}
        _f=${_f##*/}
        # "/" between the two: it is the one character a folder name cannot hold (a renamed
        # backup may have spaces).
        echo "${_f##*_}/$_f"
    done | sort -r | while IFS=/ read -r _ _n; do
        _files=0
        [ -r "$DATA/Backups/$_n/SHA256SUMS" ] && _files=$(wc -l < "$DATA/Backups/$_n/SHA256SUMS")
        _kb=$(du -sk "$DATA/Backups/$_n" 2>/dev/null | { read -r _s _; echo "$_s"; })
        num "$_kb"
        printf '%s{"name":%s,"files":%s,"kb":%s,"sums":%s,"tar":%s}' "$_sep" "$(js "$_n")" "$((_files + 0))" "$N" \
            "$([ -r "$DATA/Backups/$_n/SHA256SUMS" ] && echo true || echo false)" \
            "$([ -f "$DATA/Backups/$_n.tar" ] && echo true || echo false)"
        _sep=,
    done
    printf ']}\n'
}

# fbs delete <folder name>: removes one finished backup. Only a folder directly under Backups,
# never an unfinished .partial- one (the running backup cleans those up itself).
delete_run() {
    case $1 in
        '' | */* | .*)
            echo '{"ok":false,"msg":"usage: fbs delete <folder name>"}'
            return 2
            ;;
    esac
    _out=$DATA/Backups/$1
    if [ ! -d "$_out" ]; then
        echo '{"ok":false,"msg":"missing"}'
        return 1
    fi
    if rm -rf "$_out"; then
        # The archive made from it (fbs archive) is a copy of the same files: it goes too.
        rm -f "$_out.tar"
        printf '{"ok":true,"folder":%s}\n' "$(js "$1")"
    else
        echo '{"ok":false,"msg":"storage"}'
        return 1
    fi
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
    # A list written on Windows may end its lines with CR LF, and any list may lack the last
    # newline: both still count.
    _cr=$(printf '\r')
    # First how much there is to read (KiB on disk: du, because a size in bytes past 4 GiB
    # cannot be added up under mksh), so the WebUI can show how far the check has come.
    _vc=0
    _vk=0
    while read -r _want _file || [ -n "$_want" ]; do
        _file=${_file%"$_cr"}
        _file=${_file#\*}
        [ -n "$_file" ] || continue
        _vc=$((_vc + 1))
        _k=$(du -k "$_out/$_file" 2>/dev/null | { read -r _s _; echo "$_s"; })
        num "$_k"
        [ "$N" = null ] || _vk=$((_vk + N))
    done < "$_out/SHA256SUMS"
    printf '{"event":"plan","count":%s,"kb":%s}\n' "$_vc" "$_vk"
    while read -r _want _file || [ -n "$_want" ]; do
        _file=${_file%"$_cr"}
        _file=${_file#\*}
        [ -n "$_file" ] || continue
        _k=$(du -k "$_out/$_file" 2>/dev/null | { read -r _s _; echo "$_s"; })
        num "$_k"
        [ "$N" = null ] && N=0
        printf '{"event":"start","name":%s,"kb":%s}\n' "$(js "$_file")" "$N"
        if [ ! -r "$_out/$_file" ]; then
            _state=missing
        else
            _got=$(cd "$_out" && sha256sum "$_file")
            if [ "${_got%% *}" = "$_want" ]; then _state=ok; else _state=bad; fi
        fi
        if [ $_state = ok ]; then _ok=$((_ok + 1)); else _bad=$((_bad + 1)); fi
        printf '{"event":"file","name":%s,"state":"%s"}\n' "$(js "$_file")" "$_state"
    done < "$_out/SHA256SUMS"
    # A list with nothing in it proves nothing: not "all match".
    if [ $((_ok + _bad)) -eq 0 ]; then
        echo '{"event":"error","msg":"empty-sums"}'
        return 1
    fi
    printf '{"event":"finish","ok":%s,"bad":%s}\n' "$_ok" "$_bad"
}

# fbs archive <folder name>: one .tar of a finished backup, next to its folder, for sending
# it somewhere as a single file. Plain tar, not compressed: the images do not shrink, and
# every tar reads it. Written under a hidden name and renamed once its list of members has
# been read back and counted, so a cut-off archive never looks like a whole one.
archive_run() {
    case $1 in
        '' | */* | .*)
            echo '{"event":"error","msg":"usage: fbs archive <folder name>"}'
            return 2
            ;;
    esac
    _adir=$DATA/Backups/$1
    if [ ! -d "$_adir" ]; then
        echo '{"event":"error","msg":"missing"}'
        return 1
    fi
    _atar=$_adir.tar
    _akb=$(du -sk "$_adir" 2>/dev/null | { read -r _s _; echo "$_s"; })
    num "$_akb"
    _akb=$N
    [ "$_akb" != null ] || _akb=0
    free_kb "$DATA/Backups"
    # 16 MiB over the folder's size: tar's headers and padding, and a little spare.
    if [ "$N" != null ] && [ $((_akb + 16384)) -gt "$N" ]; then
        printf '{"event":"error","msg":"space","need_kb":%s,"free_kb":%s}\n' "$((_akb + 16384))" "$N"
        return 1
    fi
    _afiles=$(find "$_adir" -type f | wc -l)
    _afiles=$((_afiles + 0))
    _partial=$DATA/Backups/.partial-$1.tar
    JOB=
    trap '[ -z "$JOB" ] || kill "$JOB" 2>/dev/null; [ -z "$_partial" ] || rm -f "$_partial"' EXIT
    rm -f "$_partial"
    printf '{"event":"plan","file":%s,"count":%s,"kb":%s}\n' "$(js "$_atar")" "$_afiles" "$_akb"
    # "./" before the name: a folder whose name starts with a dash is not read as an option.
    tar -cf "$_partial" -C "$DATA/Backups" "./$1" 2>/dev/null &
    JOB=$!
    poll_copy "$JOB" "$_partial" "$1" ""
    wait "$JOB"
    _rc=$?
    JOB=
    if [ "$_rc" != 0 ]; then
        rm -f "$_partial"
        _partial=
        echo '{"event":"error","msg":"tar"}'
        return 1
    fi
    # Read the list back: as many files in the archive as in the folder.
    _got=$(tar -tf "$_partial" 2>/dev/null | grep -c -v '/$')
    if [ "$((_got + 0))" != "$_afiles" ] || [ "$_afiles" = 0 ]; then
        rm -f "$_partial"
        _partial=
        printf '{"event":"error","msg":"count","got":%s,"want":%s}\n' "$((_got + 0))" "$_afiles"
        return 1
    fi
    sync
    mv "$_partial" "$_atar" || {
        rm -f "$_partial"
        _partial=
        echo '{"event":"error","msg":"storage"}'
        return 1
    }
    _partial=
    _k=$(du -k "$_atar" 2>/dev/null | { read -r _s _; echo "$_s"; })
    num "$_k"
    printf '{"event":"finish","file":%s,"files":%s,"kb":%s}\n' "$(js "$_atar")" "$_afiles" "$N"
}
