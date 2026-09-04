#!/bin/sh
# Ultra Stalker V7.6 Final - Public Production Installer
# Enigma2 / OpenBH - Python 3.12 / 3.13 / 3.14

set -u

PLUGIN_PKG="enigma2-plugin-extensions-ultrastalker"
VERSION="7.6"
TAG="v10.0.60"
IPK_NAME="UltraStalker_V7_UPDATE.ipk"
IPK_URL="https://github.com/K3bOra/-UltraStalker/releases/download/${TAG}/${IPK_NAME}"
EXPECTED_SHA256="fe13e6249342380c9dba61b0d53e3ed9b2344219456593dde31cb57272738849"
TMP_IPK="/tmp/${IPK_NAME}"
PART_IPK="${TMP_IPK}.part"
OPKG_LOG="/tmp/ultrastalker-opkg-update.log"
PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/UltraStalker"
INFO_LIST="/usr/lib/opkg/info/${PLUGIN_PKG}.list"

say() { printf '%s\n' "$*"; }
cleanup() { rm -f "$TMP_IPK" "$PART_IPK" "$OPKG_LOG" 2>/dev/null || true; }
fail() { say ""; say "[ERROR] $*"; cleanup; exit 1; }
trap cleanup EXIT INT TERM

calc_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v busybox >/dev/null 2>&1; then
        busybox sha256sum "$1" | awk '{print $1}'
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$1" <<'PY'
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for block in iter(lambda: f.read(1024 * 1024), b''):
        h.update(block)
print(h.hexdigest())
PY
    else
        return 1
    fi
}

say "=============================================="
say "          Ultra Stalker V7.6 Final"
say "=============================================="
say ""

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found. This receiver is not supported."

if command -v python3 >/dev/null 2>&1; then
    PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
else
    PYVER=""
fi
case "$PYVER" in
    3.12|3.13|3.14) say "[OK] Python $PYVER detected." ;;
    *) fail "Unsupported Python version: ${PYVER:-not found}. Ultra Stalker requires Python 3.12, 3.13 or 3.14." ;;
esac

FREE_KB="$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
case "$FREE_KB" in
    ''|*[!0-9]*) ;;
    *) [ "$FREE_KB" -ge 30000 ] || fail "Not enough free space in /tmp. At least 30 MB is required." ;;
esac

say "[1/6] Checking required libraries..."
MISSING=""
opkg status python3-core 2>/dev/null | grep -q '^Status:.* installed' || MISSING="$MISSING python3-core"
python3 -c 'import sqlite3' >/dev/null 2>&1 || MISSING="$MISSING python3-sqlite3"
python3 -c 'from PIL import Image' >/dev/null 2>&1 || MISSING="$MISSING python3-pillow"
python3 -c 'import twisted; from twisted.web.client import Agent' >/dev/null 2>&1 || MISSING="$MISSING python3-twisted"
if [ -n "$MISSING" ]; then
    say "      Missing:$MISSING"
    opkg update >"$OPKG_LOG" 2>&1 || say "[WARN] opkg update reported an error; trying available package lists anyway."
    for dep in $MISSING; do
        say "      Installing $dep..."
        opkg install "$dep" || fail "Could not install required dependency: $dep"
    done
else
    say "[OK] Required libraries are already installed."
fi
python3 -c 'import sqlite3' >/dev/null 2>&1 || fail "Python sqlite3 is unavailable."
python3 -c 'from PIL import Image' >/dev/null 2>&1 || fail "Python Pillow is unavailable."
python3 -c 'import twisted; from twisted.web.client import Agent' >/dev/null 2>&1 || fail "Python Twisted is unavailable."

say "[2/6] Downloading verified V7.6 package..."
rm -f "$TMP_IPK" "$PART_IPK" "$OPKG_LOG" 2>/dev/null || true
if command -v wget >/dev/null 2>&1; then
    wget -O "$PART_IPK" "$IPK_URL" || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$IPK_URL" -o "$PART_IPK" || fail "Download failed."
else
    fail "Neither wget nor curl is available on this receiver."
fi
[ -s "$PART_IPK" ] || fail "Downloaded package is empty."
SIZE="$(wc -c < "$PART_IPK" 2>/dev/null || echo 0)"
[ "$SIZE" -gt 1000000 ] || fail "Downloaded file is unexpectedly small and may not be a valid IPK."
mv -f "$PART_IPK" "$TMP_IPK"

say "[3/6] Verifying SHA256..."
GOT_SHA256="$(calc_sha256 "$TMP_IPK" 2>/dev/null || true)"
[ -n "$GOT_SHA256" ] || fail "No SHA256 verifier is available."
[ "$GOT_SHA256" = "$EXPECTED_SHA256" ] || fail "SHA256 mismatch. Expected $EXPECTED_SHA256 but got $GOT_SHA256"
say "[OK] SHA256 verified."

say "[4/6] Preparing safe upgrade..."
# Repair only a malformed legacy root entry in the old opkg ownership list.
# User settings and persistent artwork/cache are intentionally untouched.
if [ -f "$INFO_LIST" ]; then
    FIXED="${INFO_LIST}.ultrastalker.$$"
    awk '$0 != "/" && $0 != "./" && NF { print }' "$INFO_LIST" > "$FIXED" 2>/dev/null || true
    if [ -s "$FIXED" ]; then mv -f "$FIXED" "$INFO_LIST"; else rm -f "$FIXED"; fi
fi
rm -f \
 "$PLUGIN_DIR/frontpanel_bridge.pyc" \
 "$PLUGIN_DIR/ui_persistence_runtime.py" "$PLUGIN_DIR/ui_persistence_runtime.pyc" \
 "$PLUGIN_DIR/ui_navigation_runtime.py" "$PLUGIN_DIR/ui_navigation_runtime.pyc" \
 "$PLUGIN_DIR/ui_image_runtime.py" "$PLUGIN_DIR/ui_image_runtime.pyc" 2>/dev/null || true
if [ -d "$PLUGIN_DIR/__pycache__" ]; then
    rm -f "$PLUGIN_DIR/__pycache__/frontpanel_bridge."*.pyc \
          "$PLUGIN_DIR/__pycache__/ui_persistence_runtime."*.pyc \
          "$PLUGIN_DIR/__pycache__/ui_navigation_runtime."*.pyc \
          "$PLUGIN_DIR/__pycache__/ui_image_runtime."*.pyc 2>/dev/null || true
fi
say "[OK] Upgrade path prepared without touching persistent HDD artwork."

say "[5/6] Installing Ultra Stalker V7.6..."
if ! opkg install --force-reinstall "$TMP_IPK" >"$OPKG_LOG" 2>&1; then
    cat "$OPKG_LOG" 2>/dev/null || true
    fail "Package installation failed. Existing user data was not intentionally removed."
fi
cat "$OPKG_LOG" 2>/dev/null || true

STATUS="$(opkg status "$PLUGIN_PKG" 2>/dev/null || true)"
printf '%s\n' "$STATUS" | grep -q '^Status:.* installed' || fail "opkg finished but Ultra Stalker is not registered as installed."
INSTALLED_VERSION="$(printf '%s\n' "$STATUS" | awk -F': ' '/^Version:/ {print $2; exit}')"
[ "$INSTALLED_VERSION" = "$VERSION" ] || fail "Installed package version is ${INSTALLED_VERSION:-unknown}, expected $VERSION."
say "[OK] Ultra Stalker V$VERSION is registered correctly."

say "[6/6] Cleaning temporary files..."
cleanup
trap - EXIT INT TERM
sync 2>/dev/null || true
say ""
say "=============================================="
say " Ultra Stalker V7.6 installed successfully."
say " Enigma2 restart is handled by the package."
say "=============================================="
exit 0
