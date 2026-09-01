#!/bin/sh
# Ultra Stalker V7.1 - Public Production Installer
# Enigma2 / OpenBH - Python 3.12 / 3.13 / 3.14

set -u

PLUGIN_PKG="enigma2-plugin-extensions-ultrastalker"
IPK_NAME="UltraStalker_V7_UPDATE.ipk"
IPK_URL="https://github.com/K3bOra/-UltraStalker/releases/download/v10.0.60/${IPK_NAME}"
EXPECTED_SHA256="d7f016439c17670bbcab0405766af71cb033610a06623850507817072491c166"
TMP_IPK="/tmp/${IPK_NAME}"
OPKG_LOG="/tmp/ultrastalker-opkg-update.log"

say() { printf '%s\n' "$*"; }

fail() {
    say ""
    say "[ERROR] $*"
    rm -f "$TMP_IPK" "$OPKG_LOG" 2>/dev/null || true
    exit 1
}

say "=============================================="
say "          Ultra Stalker V7.1 Installer"
say "=============================================="

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found. This receiver is not supported."

if command -v python3 >/dev/null 2>&1; then
    PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
else
    PYVER=""
fi

case "$PYVER" in
    3.12|3.13|3.14)
        say "[OK] Python $PYVER detected."
        ;;
    *)
        fail "Unsupported Python version: ${PYVER:-not found}. Ultra Stalker requires Python 3.12, 3.13 or 3.14."
        ;;
esac

FREE_KB="$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
case "$FREE_KB" in
    ''|*[!0-9]*) ;;
    *) [ "$FREE_KB" -ge 30000 ] || fail "Not enough free space in /tmp. At least 30 MB is required." ;;
esac

say "[1/6] Checking required libraries..."

MISSING=""

if ! opkg status python3-core 2>/dev/null | grep -q '^Status:.* installed'; then
    MISSING="$MISSING python3-core"
fi

if ! python3 -c 'import sqlite3' >/dev/null 2>&1; then
    MISSING="$MISSING python3-sqlite3"
fi

if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    MISSING="$MISSING python3-pillow"
fi

if ! python3 -c 'import twisted; from twisted.web.client import Agent' >/dev/null 2>&1; then
    MISSING="$MISSING python3-twisted"
fi

if [ -n "$MISSING" ]; then
    say "      Missing:$MISSING"
    say "      Refreshing package feeds..."
    opkg update >"$OPKG_LOG" 2>&1 || \
        say "[WARN] opkg update reported an error; trying available package lists anyway."

    for dep in $MISSING; do
        say "      Installing $dep..."
        opkg install "$dep" || fail "Could not install required dependency: $dep"
    done
else
    say "[OK] Required libraries are already installed."
fi

python3 -c 'import sqlite3' >/dev/null 2>&1 || fail "Python sqlite3 is still unavailable."
python3 -c 'from PIL import Image' >/dev/null 2>&1 || fail "Python Pillow is still unavailable."
python3 -c 'import twisted; from twisted.web.client import Agent' >/dev/null 2>&1 || fail "Python Twisted is still unavailable."

say "[2/6] Downloading Ultra Stalker V7.1..."
rm -f "$TMP_IPK"

if command -v wget >/dev/null 2>&1; then
    wget -O "$TMP_IPK" "$IPK_URL" || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$IPK_URL" -o "$TMP_IPK" || fail "Download failed."
else
    fail "Neither wget nor curl is available on this receiver."
fi

[ -s "$TMP_IPK" ] || fail "Downloaded package is empty."
SIZE="$(wc -c < "$TMP_IPK" 2>/dev/null || echo 0)"
[ "$SIZE" -gt 1000000 ] || fail "Downloaded file is unexpectedly small and may not be a valid IPK."

say "[3/6] Verifying package integrity..."

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256="$(sha256sum "$TMP_IPK" | awk '{print $1}')"
elif command -v openssl >/dev/null 2>&1; then
    ACTUAL_SHA256="$(openssl dgst -sha256 "$TMP_IPK" 2>/dev/null | awk '{print $NF}')"
else
    fail "No SHA256 tool is available on this receiver."
fi

[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || \
    fail "SHA256 mismatch. Downloaded package was not installed."

say "[OK] SHA256 verified."

say "[4/6] Installing / updating Ultra Stalker..."
opkg install --force-reinstall "$TMP_IPK" || fail "Package installation failed."

if ! opkg status "$PLUGIN_PKG" 2>/dev/null | grep -q '^Status:.* installed'; then
    fail "opkg finished but Ultra Stalker is not registered as installed."
fi

say "[5/6] Cleaning temporary files..."
rm -f "$TMP_IPK" "$OPKG_LOG" 2>/dev/null || true
sync 2>/dev/null || true

say ""
say "=============================================="
say " Ultra Stalker V7.1 installed successfully."
say " Enigma2 will restart automatically."
say "=============================================="

say "[6/6] Restarting Enigma2..."
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
