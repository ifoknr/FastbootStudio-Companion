# Logs. The WebUI polls these once a second instead of holding a "dmesg -w" open: nothing is
# left running when the WebUI closes, and there is no pipe buffering to delay lines.

# fbs log kernel [lines]          the newest lines of the kernel ring buffer
# fbs log app [lines | 'time']    logcat; a time ('MM-DD hh:mm:ss.mmm') gives every line since then
log_cmd() {
    case $1 in
        kernel)
            _n=${2:-300}
            case $_n in '' | *[!0-9]*) _n=300 ;; esac
            dmesg 2>/dev/null | tail -n "$_n"
            ;;
        app)
            _since=${2:-300}
            case $_since in
                *[!0-9\ :.-]*) _since=300 ;;
            esac
            logcat -d -v threadtime -t "$_since" 2>/dev/null
            ;;
        *)
            echo "usage: fbs log kernel [lines] | app [lines|'MM-DD hh:mm:ss.mmm']" >&2
            return 2
            ;;
    esac
}

# The previous boot's kernel log, for the black box card. Two header lines, then the log:
#   #reason=<sys.boot.reason>
#   #source=<file it came from, or none>
# dmesg-ramoops is only written on a panic or oops, so it goes first.
last_text() {
    _src=
    for _f in "$R"/sys/fs/pstore/dmesg-ramoops-* "$R"/sys/fs/pstore/console-ramoops-0 \
        "$R"/sys/fs/pstore/console-ramoops "$R"/proc/last_kmsg; do
        if [ -r "$_f" ]; then
            _src=$_f
            break
        fi
    done
    _reason=$(prop sys.boot.reason)
    [ -n "$_reason" ] || _reason=$(prop ro.boot.bootreason)
    echo "#reason=$_reason"
    echo "#source=${_src#"$R"}"
    [ -n "$_src" ] && tail -n "${1:-150}" "$_src"
    return 0
}
