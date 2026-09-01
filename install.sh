#!/bin/sh
# Ultra Stalker V7.1 - Public Production Installer
# Enigma2 / OpenBH - Python 3.12 / 3.13 / 3.14

set -u

PLUGIN_PKG="enigma2-plugin-extensions-ultrastalker"
IPK_NAME="UltraStalker_V7_UPDATE.ipk"
IPK_URL="https://github.com/K3bOra/-UltraStalker/releases/download/v7.1/${IPK_NAME}"
EXPECTED_SHA256="d7f016439c17670bbcab0405766af71cb033610a06623850507817072491c166"
TMP_IPK="/tmp/${IPK_NAME}"
OPKG_LOG="/tmp/ultrastalker-opkg-update.log"

say() { printf '%s\n' "$*"; }
cleanup() { rm -f "$TMP_IPK" "$TMP_IPK.part" "$OPKG_LOG" 2>/dev/null || true; }
fail() { say ""; say "[ERROR] $*"; cleanup; exit 1; }

say "=============================================="
say "          Ultra Stalker V7.1 Installer"
say "=============================================="

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found. This receiver is not supported."
command -v python3 >/dev/null 2>&1 || fail "python3 was not found."

PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
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
if ! opkg status python3-core 2>/dev/null | grep -q '^Status:.* installed'; then MISSING="$MISSING python3-core"; fi
if ! python3 -c 'import sqlite3' >/dev/null 2>&1; then MISSING="$MISSING python3-sqlite3"; fi
if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then MISSING="$MISSING python3-pillow"; fi
if ! python3 -c 'import twisted; from twisted.web.client import Agent' >/dev/null 2>&1; then MISSING="$MISSING python3-twisted"; fi

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

say "[2/6] Downloading Ultra Stalker V7.1..."
cleanup
if command -v wget >/dev/null 2>&1; then
    wget -O "$TMP_IPK.part" "$IPK_URL" || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$IPK_URL" -o "$TMP_IPK.part" || fail "Download failed."
else
    fail "Neither wget nor curl is available on this receiver."
fi

[ -s "$TMP_IPK.part" ] || fail "Downloaded package is empty."
SIZE="$(wc -c < "$TMP_IPK.part" 2>/dev/null || echo 0)"
[ "$SIZE" -gt 1000000 ] || fail "Downloaded file is unexpectedly small."

say "[3/6] Verifying SHA256..."
ACTUAL_SHA256="$(python3 - "$TMP_IPK.part" <<'PY'
import hashlib, sys
h=hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for b in iter(lambda:f.read(1024*1024), b''):
        h.update(b)
print(h.hexdigest())
PY
)"
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "SHA256 verification failed. The release asset does not match V7.1."
mv -f "$TMP_IPK.part" "$TMP_IPK"
say "[OK] Package checksum verified."

say "[4/6] Installing / updating Ultra Stalker..."
# Do not remove the existing package first. This preserves user settings and persistent HDD artwork/cache.
opkg install --force-reinstall "$TMP_IPK" || fail "Package installation failed."

if ! opkg status "$PLUGIN_PKG" 2>/dev/null | grep -q '^Status:.* installed'; then
    fail "opkg finished but Ultra Stalker is not registered as installed."
fi

INSTALLED_VERSION="$(opkg status "$PLUGIN_PKG" 2>/dev/null | awk -F': ' '/^Version:/{print $2; exit}')"
[ "$INSTALLED_VERSION" = "7.1" ] || fail "Installed package version is ${INSTALLED_VERSION:-unknown}, expected 7.1."

say "[5/6] Cleaning temporary files..."
cleanup
sync 2>/dev/null || true

say "[6/6] Restarting Enigma2..."
say "=============================================="
say " Ultra Stalker V7.1 installed successfully."
say "=============================================="
sync 2>/dev/null || true
sleep 2
if command -v killall >/dev/null 2>&1; then
    killall -9 enigma2 >/dev/null 2>&1 || true
else
    init 4 >/dev/null 2>&1 || true
    sleep 2
    init 3 >/dev/null 2>&1 || true
fi
exit 0
