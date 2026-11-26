# The only commands that do something to the phone: reboot, and the support bundle (which
# writes to <DATA>/Reports and nowhere else).

# fbs reboot bootloader|fastboot|recovery|edl
reboot_to() {
    case $1 in
        bootloader | fastboot | recovery) ;;
        edl)
            # Only Qualcomm phones have EDL; elsewhere "reboot edl" is a plain reboot at best.
            if [ "$(soc_vendor)" != qualcomm ]; then
                echo '{"ok":false,"msg":"edl-qualcomm-only"}'
                return 1
            fi
            ;;
        *)
            echo '{"ok":false,"msg":"usage: fbs reboot bootloader|fastboot|recovery|edl"}'
            return 2
            ;;
    esac
    echo '{"ok":true}'
    reboot "$1"
}

# fbs open <https url>: hands a link to Android, so a Telegram link opens Telegram and the rest
# the browser. The WebUI's own WebView would keep it inside the root manager.
open_url() {
    case $1 in
        https://*) ;;
        *)
            echo '{"ok":false,"msg":"usage: fbs open https://..."}'
            return 2
            ;;
    esac
    case $1 in
        *[[:space:]\"\'\`\\]*)
            echo '{"ok":false,"msg":"bad-url"}'
            return 2
            ;;
    esac
    if am start -a android.intent.action.VIEW -d "$1" >/dev/null 2>&1; then
        echo '{"ok":true}'
    else
        echo '{"ok":false,"msg":"am"}'
        return 1
    fi
}

# Masks what identifies the phone or its owner: 15-digit numbers (IMEI), the serial and MAC
# addresses. Edits the files in place.
redact_files() {
    _serial=$(prop ro.serialno)
    case $_serial in
        '' | *[!A-Za-z0-9]*) _serial=_no_serial_to_mask_ ;;
    esac
    for _f in "$@"; do
        sed -i -E \
            -e 's/[0-9]{15}/[imei]/g' \
            -e "s/$_serial/[serial]/g" \
            -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/[mac]/g' \
            "$_f"
    done
}

# fbs bundle [plain]: logs, device info and the partition table in one .tar.gz for a bug
# report. Redacted unless "plain" is given.
bundle_run() {
    # Its own variable names: sh has no locals, and parts_json and super_json use _dir.
    _bts=$(date +%Y%m%d-%H%M%S)
    _bname=companion-report_$_bts
    _bdir=$DATA/Reports/$_bname
    mkdir -p "$_bdir" || {
        echo '{"ok":false,"msg":"storage"}'
        return 1
    }
    info_json > "$_bdir/device.json"
    parts_json > "$_bdir/partitions.json"
    super_json > "$_bdir/super.json"
    last_text 400 > "$_bdir/last-boot.txt"
    dmesg > "$_bdir/dmesg.txt" 2>/dev/null
    logcat -d -v threadtime -t 5000 > "$_bdir/logcat.txt" 2>/dev/null
    getprop > "$_bdir/props.txt" 2>/dev/null
    _bred=false
    if [ "$1" != plain ]; then
        redact_files "$_bdir"/*
        _bred=true
    fi
    if tar -czf "$_bdir.tar.gz" -C "$DATA/Reports" "$_bname" 2>/dev/null; then
        rm -rf "$_bdir"
        printf '{"ok":true,"file":%s,"redacted":%s}\n' "$(js "$_bdir.tar.gz")" "$_bred"
    elif rm -f "$_bdir.tar.gz" && tar -cf "$_bdir.tar" -C "$DATA/Reports" "$_bname" 2>/dev/null; then
        # A tar without gzip built in: still one file, only not compressed.
        rm -rf "$_bdir"
        printf '{"ok":true,"file":%s,"redacted":%s}\n' "$(js "$_bdir.tar")" "$_bred"
    else
        rm -f "$_bdir.tar"
        rm -f "$_bdir.tar.gz"
        printf '{"ok":true,"file":%s,"redacted":%s}\n' "$(js "$_bdir")" "$_bred"
    fi
}

# fbs share <file>: opens Android's share sheet for an archive or a support bundle under <DATA>.
#
# A receiving app cannot read a file:// path under /sdcard on Android 11 and later (scoped
# storage), so the file is handed over as the content:// address MediaStore has for it, with
# read permission granted for that one address. MediaStore is told to index the file first.
# When no such address can be had, or am refuses, the answer is {"ok":false,...} with the path:
# the WebUI then shows where the file is, and never says it was shared. {"ok":true} means the
# share sheet was asked for, not that anything was sent.
share_run() {
    _sf=$1
    case $_sf in
        "$DATA"/*) ;;
        *)
            echo '{"ok":false,"msg":"usage: fbs share <file under the FastbootStudio folder>"}'
            return 2
            ;;
    esac
    case $_sf in
        */../* | */.. | *\'*)
            echo '{"ok":false,"msg":"bad-path"}'
            return 2
            ;;
    esac
    if [ ! -f "$_sf" ]; then
        echo '{"ok":false,"msg":"missing"}'
        return 1
    fi
    # The path as MediaStore keeps it: /storage/emulated/0/..., not the /sdcard link.
    _real=$(readlink -f "$_sf" 2>/dev/null)
    case $_real in /storage/*) ;; *) _real=$_sf ;; esac
    case $_real in /sdcard/*) _real=/storage/emulated/0/${_real#/sdcard/} ;; esac
    case $_sf in
        *.tar.gz | *.tgz) _mime=application/gzip ;;
        *.tar) _mime=application/x-tar ;;
        *) _mime=application/octet-stream ;;
    esac
    content call --uri content://media --method scan_file --arg "$_real" > /dev/null 2>&1
    _id=$(content query --uri content://media/external/file --projection _id --where "_data='$_real'" 2>/dev/null |
        sed -n 's/.*_id=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    if [ -z "$_id" ]; then
        printf '{"ok":false,"msg":"no-uri","file":%s}\n' "$(js "$_sf")"
        return 1
    fi
    _uri=content://media/external/file/$_id
    if _o=$(am start -a android.intent.action.SEND -t "$_mime" --eu android.intent.extra.STREAM "$_uri" \
        --grant-read-uri-permission 2>&1) && case $_o in *Error* | *Exception*) false ;; *) true ;; esac; then
        printf '{"ok":true,"file":%s,"uri":%s}\n' "$(js "$_sf")" "$(js "$_uri")"
    else
        printf '{"ok":false,"msg":"am","file":%s}\n' "$(js "$_sf")"
        return 1
    fi
}
