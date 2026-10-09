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
    else
        rm -f "$_bdir.tar.gz"
        printf '{"ok":true,"file":%s,"redacted":%s}\n' "$(js "$_bdir")" "$_bred"
    fi
}
