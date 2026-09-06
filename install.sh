#!/bin/sh
set -eu
PKG="enigma2-plugin-extensions-ultrastalker"
VERSION="8.2"
TAG="v10.0.60"
ASSET="UltraStalker_V7_UPDATE.ipk"
EXPECTED_SHA256="9af449d217da4e2ce847c19e8bd6526ab3bc2cb168f678c04b77cef784639adb"
URL="https://github.com/K3bOra/-UltraStalker/releases/download/v10.0.60/UltraStalker_V7_UPDATE.ipk"
TMP="/tmp/$ASSET"
LIST="/usr/lib/opkg/info/$PKG.list"

echo "Ultra Stalker V$VERSION installer"
# Repair only malformed legacy root ownership entries before opkg solver runs.
if [ -f "$LIST" ]; then
    cp -f "$LIST" "$LIST.ultrastalker-backup" 2>/dev/null || true
    awk '$0 != "/" && $0 != "./" && $0 != "" {print}' "$LIST" > "$LIST.ultrastalker-clean"
    mv -f "$LIST.ultrastalker-clean" "$LIST"
fi
rm -f "$TMP"
if command -v wget >/dev/null 2>&1; then
    wget -O "$TMP" "$URL"
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$URL" -o "$TMP"
else
    echo "ERROR: wget/curl not found"; exit 1
fi
ACTUAL="$(sha256sum "$TMP" | awk '{print $1}')"
if [ "$ACTUAL" != "$EXPECTED_SHA256" ]; then
    echo "ERROR: SHA256 mismatch"; rm -f "$TMP"; exit 1
fi
set +e
OUTPUT="$(opkg install "$TMP" 2>&1)"
RC=$?
set -e
printf '%s
' "$OUTPUT"
if [ $RC -ne 0 ] && printf '%s' "$OUTPUT" | grep -qi 'No candidates to install'; then
    echo "Retrying verified package with --force-reinstall..."
    opkg install --force-reinstall "$TMP"
elif [ $RC -ne 0 ]; then
    rm -f "$TMP"; exit $RC
fi
rm -f "$TMP"
echo "Ultra Stalker V$VERSION installed successfully. Restart Enigma2 to load the new version."
