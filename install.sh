#!/bin/sh
set -eu
PKG="enigma2-plugin-extensions-ultrastalker"
VERSION="8.2"
TAG="v10.0.60"
ASSET="UltraStalker_V7_UPDATE.ipk"
EXPECTED_SHA256="4e0349adacbecbe7c9cb5edc638621f5f8e8b02be17f5be40d1c4249b8648145"
URL="https://github.com/K3bOra/-UltraStalker/releases/download/v10.0.60/UltraStalker_V7_UPDATE.ipk"
TMP="/tmp/$ASSET"
LIST="/usr/lib/opkg/info/$PKG.list"

echo "Ultra Stalker V$VERSION installer"
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

opkg install "$TMP"
rm -f "$TMP"
echo "Ultra Stalker V$VERSION installed successfully."
