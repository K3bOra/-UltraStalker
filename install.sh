#!/bin/sh
set -e

REPO="https://github.com/K3bOra/-UltraStalker"
TAG="v10.0.60"
IPK_URL="$REPO/releases/download/$TAG/UltraStalker_V7_UPDATE.ipk"
EXPECTED_SHA256="312172be2fc66bb190230977b3a6686ac0f0e21bbb12e0bcdc502febf657fad3"
TMP_IPK="/tmp/UltraStalker_V7_UPDATE.ipk"

cleanup() {
    rm -f "$TMP_IPK" "$TMP_IPK.part"
}
trap cleanup EXIT INT TERM

log() {
    echo "[UltraStalker] $1"
}

fail() {
    echo "[UltraStalker] ERROR: $1" >&2
    exit 1
}

require_python() {
    command -v python3 >/dev/null 2>&1 || fail "python3 not found"
    pyver=$(python3 -c 'import sys; print("%d.%d" % (sys.version_info[0], sys.version_info[1]))' 2>/dev/null || true)
    case "$pyver" in
        3.12|3.13|3.14) ;;
        *) fail "Unsupported Python version: ${pyver:-unknown}. Required: 3.12 / 3.13 / 3.14" ;;
    esac
    log "Detected Python $pyver"
}

download_ipk() {
    log "Downloading update package..."
    if command -v wget >/dev/null 2>&1; then
        wget -O "$TMP_IPK.part" "$IPK_URL" || fail "wget download failed"
    elif command -v curl >/dev/null 2>&1; then
        curl -L "$IPK_URL" -o "$TMP_IPK.part" || fail "curl download failed"
    else
        fail "Neither wget nor curl is available"
    fi
    [ -s "$TMP_IPK.part" ] || fail "Downloaded file is empty"
    mv "$TMP_IPK.part" "$TMP_IPK"
}

calc_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v busybox >/dev/null 2>&1; then
        busybox sha256sum "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        fail "No SHA256 tool found"
    fi
}

verify_sha256() {
    log "Verifying SHA256..."
    actual=$(calc_sha256 "$TMP_IPK")
    [ "$actual" = "$EXPECTED_SHA256" ] || fail "SHA256 mismatch. Expected $EXPECTED_SHA256 but got $actual"
    log "SHA256 OK"
}

install_ipk() {
    command -v opkg >/dev/null 2>&1 || fail "opkg not found"
    log "Installing package..."
    if opkg install --force-reinstall "$TMP_IPK"; then
        log "Install completed successfully"
        return 0
    fi
    log "Retrying with plain opkg install..."
    opkg install "$TMP_IPK" || fail "opkg install failed"
    log "Install completed successfully"
}

require_python
download_ipk
verify_sha256
install_ipk
log "Done. You can restart Enigma2 if needed."
