#!/bin/sh
set -eu

REPO="https://github.com/K3bOra/-UltraStalker"
TAG="v10.0.60"
ASSET="UltraStalker_V7.1.6.ipk"
IPK_URL="$REPO/releases/download/$TAG/$ASSET"
EXPECTED_SHA256="fb974095dd24ca2f41d20b78e5280aafa9aebe1732a4ae77be842c78c9cf84d2"
TMP_IPK="/tmp/$ASSET"
TMP_PART="$TMP_IPK.part"

log() { echo "[UltraStalker] $*"; }
fail() { echo "[UltraStalker] ERROR: $*" >&2; exit 1; }
cleanup() { rm -f "$TMP_PART"; }
trap cleanup EXIT INT TERM

command -v python3 >/dev/null 2>&1 || fail "python3 not found"
PYVER="$(python3 -c 'import sys; print("%d.%d" % (sys.version_info[0], sys.version_info[1]))' 2>/dev/null || true)"
case "$PYVER" in
    3.12|3.13|3.14) ;;
    *) fail "Unsupported Python version: ${PYVER:-unknown}. Required: 3.12 / 3.13 / 3.14" ;;
esac
log "Python $PYVER"

rm -f "$TMP_IPK" "$TMP_PART"
log "Downloading $ASSET..."
if command -v wget >/dev/null 2>&1; then
    wget -O "$TMP_PART" "$IPK_URL" || fail "Download failed"
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$IPK_URL" -o "$TMP_PART" || fail "Download failed"
else
    fail "Neither wget nor curl is available"
fi

[ -s "$TMP_PART" ] || fail "Downloaded package is empty"
mv "$TMP_PART" "$TMP_IPK"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256="$(sha256sum "$TMP_IPK" | awk '{print $1}')"
elif command -v busybox >/dev/null 2>&1; then
    ACTUAL_SHA256="$(busybox sha256sum "$TMP_IPK" | awk '{print $1}')"
elif command -v openssl >/dev/null 2>&1; then
    ACTUAL_SHA256="$(openssl dgst -sha256 "$TMP_IPK" | awk '{print $NF}')"
else
    fail "No SHA256 tool found"
fi

[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "SHA256 mismatch: got $ACTUAL_SHA256"
log "SHA256 OK"

command -v opkg >/dev/null 2>&1 || fail "opkg not found"
log "Installing $ASSET..."
opkg install --force-reinstall "$TMP_IPK" || opkg install "$TMP_IPK" || fail "opkg install failed"
log "Installed successfully"
