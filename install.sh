#!/bin/sh
set -eu

REPO="https://github.com/K3bOra/-UltraStalker"
TAG="v7.4"
ASSET="UltraStalker_V7.4.ipk"
URL="$REPO/releases/download/$TAG/$ASSET"
SHA256="84b09c914f37c94153656e9159bddf460cafb72e5510450f68b6e84a566ed31b"
VERSION="7.4"
IPK="/tmp/$ASSET"
PART="$IPK.part"
OPKG_OUT="/tmp/UltraStalker_install_opkg.log"

log() { echo "[UltraStalker V7.4] $*"; }
fail() { echo "[UltraStalker V7.4] ERROR: $*" >&2; exit 1; }

restart_enigma2() {
    if command -v pidof >/dev/null 2>&1 && pidof enigma2 >/dev/null 2>&1; then
        log "Restarting Enigma2..."
        ( sleep 3; killall -9 enigma2 >/dev/null 2>&1 || true ) >/dev/null 2>&1 &
    fi
}

rm -f "$IPK" "$PART" "$OPKG_OUT"
log "Downloading $ASSET from release $TAG..."
if command -v wget >/dev/null 2>&1; then
    wget -O "$PART" "$URL" || fail "download failed"
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$URL" -o "$PART" || fail "download failed"
else
    fail "wget/curl not found"
fi
[ -s "$PART" ] || fail "downloaded file is empty"
mv "$PART" "$IPK"

if command -v sha256sum >/dev/null 2>&1; then
    GOT="$(sha256sum "$IPK" | awk '{print $1}')"
elif command -v busybox >/dev/null 2>&1; then
    GOT="$(busybox sha256sum "$IPK" | awk '{print $1}')"
elif command -v python3 >/dev/null 2>&1; then
    GOT="$(python3 - "$IPK" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for b in iter(lambda:f.read(1024*1024),b''):
        h.update(b)
print(h.hexdigest())
PY
)"
else
    fail "no SHA256 verifier found"
fi
[ "$GOT" = "$SHA256" ] || fail "SHA256 mismatch: $GOT"
log "SHA256 OK"

if command -v opkg >/dev/null 2>&1; then
    if opkg install "$IPK" >"$OPKG_OUT" 2>&1; then
        cat "$OPKG_OUT"
        log "Installed V$VERSION by opkg"
        exit 0
    fi
    cat "$OPKG_OUT" || true
    fail "opkg install failed"
fi

fail "opkg not found"
