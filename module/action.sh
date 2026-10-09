#!/system/bin/sh
# The Action button: a text report in the root manager's console.
MODDIR=${0%/*}
sh "$MODDIR/bin/fbs" report
