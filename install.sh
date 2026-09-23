#!/bin/sh
# Ultra Stalker Final V9.1 - Public Online Installer
# Enigma2 / Python 3.12, 3.13, 3.14, 3.15

set -u

PLUGIN_PKG="enigma2-plugin-extensions-ultrastalker"
TARGET_VERSION="9.1.0"
IPK_NAME="UltraStalker_Final_V9.1_UPDATE.ipk"
PRIMARY_URL="https://github.com/K3bOra/-UltraStalker/releases/download/v9.1.0/${IPK_NAME}"
LEGACY_NAME="UltraStalker_V7_UPDATE.ipk"
FALLBACK_URL="https://github.com/K3bOra/-UltraStalker/releases/download/v10.0.60/${LEGACY_NAME}"
EXPECTED_SHA256="3c5ca4374f2b757d0417448ef0e4f016c57394e9faa592dd58273a21b1026868"
TMP_IPK="/tmp/UltraStalker_Final_V9.1.ipk"
TMP_PART="${TMP_IPK}.part"

say() { printf '%s\n' "$*"; }
cleanup() { rm -f "$TMP_IPK" "$TMP_PART" 2>/dev/null || true; }
fail() { say ""; say "[ERROR] $*"; cleanup; exit 1; }
trap cleanup EXIT INT TERM

fetch_url() {
    url="$1"
    rm -f "$TMP_PART" 2>/dev/null || true
    if command -v wget >/dev/null 2>&1; then
        if wget -O "$TMP_PART" "$url"; then
            [ -s "$TMP_PART" ] && return 0
        fi
        rm -f "$TMP_PART" 2>/dev/null || true
    fi
    if command -v curl >/dev/null 2>&1; then
        if curl -fL "$url" -o "$TMP_PART"; then
            [ -s "$TMP_PART" ] && return 0
        fi
        rm -f "$TMP_PART" 2>/dev/null || true
    fi
    return 1
}

calc_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v busybox >/dev/null 2>&1 && busybox sha256sum "$1" >/dev/null 2>&1; then
        busybox sha256sum "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        return 1
    fi
}

say "=============================================="
say "        Ultra Stalker Final V9.1"
say "              Online Installer"
say "=============================================="

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found on this receiver."

if command -v python3 >/dev/null 2>&1; then
    PYBIN=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)' >/dev/null 2>&1; then
    PYBIN=python
else
    fail "Python 3 was not found."
fi

PYVER="$($PYBIN -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
case "$PYVER" in
    3.12|3.13|3.14|3.15) say "[OK] Python $PYVER" ;;
    *) fail "Unsupported Python version: ${PYVER:-unknown}. Required: 3.12 / 3.13 / 3.14 / 3.15." ;;
esac

FREE_KB="$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
case "$FREE_KB" in
    ''|*[!0-9]*) ;;
    *) [ "$FREE_KB" -ge 30000 ] || fail "At least 30 MB free space in /tmp is required." ;;
esac

say "[1/4] Downloading Ultra Stalker V9.1..."
if fetch_url "$PRIMARY_URL"; then
    say "[OK] Downloaded official V9.1 package."
elif fetch_url "$FALLBACK_URL"; then
    say "[OK] Downloaded legacy-compatible V9.1 bridge package."
else
    fail "Download failed from both official package locations."
fi
mv -f "$TMP_PART" "$TMP_IPK"

SIZE="$(wc -c < "$TMP_IPK" 2>/dev/null || echo 0)"
case "$SIZE" in
    ''|*[!0-9]*) fail "Could not validate downloaded package size." ;;
    *) [ "$SIZE" -gt 1000000 ] || fail "Downloaded file is too small to be a valid Ultra Stalker package." ;;
esac

say "[2/4] Verifying SHA256..."
ACTUAL_SHA256="$(calc_sha256 "$TMP_IPK" 2>/dev/null || true)"
[ -n "$ACTUAL_SHA256" ] || fail "No SHA256 verification tool is available."
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "SHA256 mismatch. Package was not installed."
say "[OK] Package integrity verified."

say "[3/4] Installing / updating Ultra Stalker..."
if ! opkg install --force-reinstall "$TMP_IPK"; then
    say "[WARN] --force-reinstall failed; retrying with normal opkg install..."
    opkg install "$TMP_IPK" || fail "Package installation failed."
fi

STATUS="$(opkg status "$PLUGIN_PKG" 2>/dev/null || true)"
printf '%s\n' "$STATUS" | grep -q '^Status:.* installed' || fail "Ultra Stalker is not registered as installed."
INSTALLED_VERSION="$(printf '%s\n' "$STATUS" | awk -F': ' '/^Version:/ {print $2; exit}')"
[ "$INSTALLED_VERSION" = "$TARGET_VERSION" ] || fail "Unexpected installed version: ${INSTALLED_VERSION:-unknown}; expected $TARGET_VERSION."

say "[4/4] Installation verified."
say ""
say "=============================================="
say " Ultra Stalker Final V9.1 installed correctly."
say " Dependency repair and GUI restart, if needed,"
say " are handled automatically by the package."
say "=============================================="
sync 2>/dev/null || true
exit 0
