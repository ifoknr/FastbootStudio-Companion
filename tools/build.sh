#!/bin/sh
# Builds the installable module zip into dist/ (or the folder given) and checks that every
# place that names the version agrees.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/dist}

VER=$(sed -n 's/^version=//p' "$ROOT/module/module.prop")
CODE=$(sed -n 's/^versionCode=//p' "$ROOT/module/module.prop")
FBS=v$(sed -n 's/^FBS_VERSION=//p' "$ROOT/module/bin/fbs")
CHANNEL=$(sed -n 's/^FBS_CHANNEL=//p' "$ROOT/module/bin/fbs")
NAME=$(sed -n 's/^name=//p' "$ROOT/module/module.prop")
UJ_VER=$(jq -r .version "$ROOT/update.json")
UJ_CODE=$(jq -r .versionCode "$ROOT/update.json")
UJ_ZIP=$(jq -r .zipUrl "$ROOT/update.json")

bad=0
[ "$FBS" = "$VER" ] || { echo "bin/fbs says $FBS, module.prop says $VER" >&2; bad=1; }
[ "$UJ_VER" = "$VER" ] || { echo "update.json says $UJ_VER, module.prop says $VER" >&2; bad=1; }
[ "$UJ_CODE" = "$CODE" ] || { echo "update.json versionCode $UJ_CODE, module.prop $CODE" >&2; bad=1; }
case $UJ_ZIP in
    */download/$VER/FastbootStudio-Companion-$VER.zip) ;;
    *) echo "update.json zipUrl does not point at $VER: $UJ_ZIP" >&2; bad=1 ;;
esac
case $CHANNEL:$NAME in
    "beta:"*" (Beta)" | "stable:"*) ;;
    *) echo "bin/fbs channel is '$CHANNEL' but module.prop name is '$NAME'" >&2; bad=1 ;;
esac
case $CHANNEL:$NAME in
    "stable:"*"(Beta)"*) echo "a stable build cannot be named Beta: $NAME" >&2; bad=1 ;;
esac
grep -q "^## $VER\$" "$ROOT/CHANGELOG.md" || { echo "CHANGELOG.md has no '## $VER' section" >&2; bad=1; }
[ $bad = 0 ] || exit 1

mkdir -p "$OUT"
# Absolute, because zip runs from inside module/.
OUT=$(cd "$OUT" && pwd)
ZIP=$OUT/FastbootStudio-Companion-$VER.zip
rm -f "$ZIP"
# demo.js is only for previews in a browser; on a phone the root manager's bridge is used.
(cd "$ROOT/module" && zip -qr -X "$ZIP" . -x 'webroot/demo.js')
echo "$ZIP"
