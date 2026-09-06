#!/bin/sh
# Ultra Stalker V8.3 - Public Production Installer
# Enigma2 / OpenBH - Python 3.12 / 3.13 / 3.14
set -u

VERSION="8.3"
TAG="v10.0.60"
ASSET="UltraStalker_V7_UPDATE.ipk"
PACKAGE="enigma2-plugin-extensions-ultrastalker"
EXPECTED_SHA256="943e409db5385f5a3a046b9320d8ecbbd5ef4bbca8e105aca7a889879f0cfe31"
URL="https://github.com/K3bOra/-UltraStalker/releases/download/${TAG}/${ASSET}"
IPK="/tmp/${ASSET}"
PART="${IPK}.part"
LOG="/tmp/ultrastalker_install.log"
INFO="/usr/lib/opkg/info/${PACKAGE}.list"
REFRESHED=0

: > "$LOG"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
cleanup() { rm -f "$IPK" "$PART" 2>/dev/null || true; }
fail() { say ""; say "[ERROR] $*"; cleanup; exit 1; }

py_ok() {
    python3 - "$1" <<'PY' >/dev/null 2>&1
import sys
name=sys.argv[1]
if name == "sqlite":
    import sqlite3
    c=sqlite3.connect(":memory:")
    c.execute("create table t(x integer)")
    c.execute("insert into t values (1)")
    assert c.execute("select x from t").fetchone()[0] == 1
    c.close()
elif name == "pillow":
    from PIL import Image
    assert Image.new("RGB",(2,2)).size == (2,2)
elif name == "twisted":
    import twisted
    from twisted.web.client import Agent
elif name == "ssl":
    import ssl
    ssl.create_default_context()
else:
    raise SystemExit(1)
PY
}

refresh_feeds_once() {
    [ "$REFRESHED" -eq 1 ] && return 0
    REFRESHED=1
    say "      Refreshing package feeds..."
    opkg update >>"$LOG" 2>&1 || say "[WARN] opkg update reported an error; cached metadata will still be tried."
}

resolve_runtime() {
    kind="$1"; label="$2"; shift 2
    if py_ok "$kind"; then say "[OK] $label"; return 0; fi
    refresh_feeds_once
    for p in "$@"; do
        [ -n "$p" ] || continue
        say "      Trying $p..."
        if opkg install "$p" >>"$LOG" 2>&1 && py_ok "$kind"; then
            say "[OK] $label"
            return 0
        fi
    done
    return 1
}

calc_sha256() {
    f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v busybox >/dev/null 2>&1 && busybox sha256sum "$f" >/dev/null 2>&1; then
        busybox sha256sum "$f" | awk '{print $1}'
    else
        python3 - "$f" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],"rb") as f:
    for b in iter(lambda:f.read(1024*1024),b""):
        h.update(b)
print(h.hexdigest())
PY
    fi
}

repair_legacy_list() {
    [ -f "$INFO" ] || return 0
    TMP="${INFO}.ultrastalker-clean.$$"
    awk '$0 != "/" && $0 != "./" && NF { print }' "$INFO" > "$TMP" 2>/dev/null || return 0
    if [ -s "$TMP" ]; then
        cp -f "$INFO" "${INFO}.ultrastalker-backup" 2>/dev/null || true
        mv -f "$TMP" "$INFO"
    else
        rm -f "$TMP"
    fi
}

say "=============================================="
say "          Ultra Stalker V$VERSION"
say "          Final Public Installer"
say "=============================================="
say ""

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found."
command -v python3 >/dev/null 2>&1 || fail "python3 was not found."

PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
case "$PYVER" in
    3.12|3.13|3.14) say "[OK] Python $PYVER detected." ;;
    *) fail "Unsupported Python version: ${PYVER:-not found}. Required: 3.12 / 3.13 / 3.14." ;;
esac

py_ok ssl && say "[OK] Python SSL runtime" || say "[WARN] Python SSL runtime check failed."

say ""
say "[1/5] Checking required Python runtimes..."
FAIL=0
resolve_runtime sqlite "Python SQLite runtime" python3-sqlite3 python3-sqlite python3-modules || FAIL=1
resolve_runtime pillow "Python Pillow runtime" python3-pillow python3-pil python3-pillow-core || FAIL=1
resolve_runtime twisted "Python Twisted runtime" python3-twisted python3-twisted-core twisted || FAIL=1
[ "$FAIL" -eq 0 ] && py_ok sqlite && py_ok pillow && py_ok twisted || fail "Required Python runtimes remain unavailable."

say ""
say "[2/5] Repairing legacy package state..."
repair_legacy_list
say "[OK] Package state ready."

say ""
say "[3/5] Downloading and verifying official V$VERSION..."
cleanup
if command -v wget >/dev/null 2>&1; then
    wget -O "$PART" "$URL" >>"$LOG" 2>&1 || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$URL" -o "$PART" >>"$LOG" 2>&1 || fail "Download failed."
else
    fail "Neither wget nor curl is available."
fi
[ -s "$PART" ] || fail "Downloaded package is empty."
mv -f "$PART" "$IPK"

GOT="$(calc_sha256 "$IPK" 2>/dev/null || true)"
[ -n "$GOT" ] || fail "No SHA256 verifier is available."
[ "$GOT" = "$EXPECTED_SHA256" ] || fail "SHA256 mismatch. Expected $EXPECTED_SHA256 but got $GOT"
say "[OK] SHA256 verified: $GOT"

say ""
say "[4/5] Installing Ultra Stalker V$VERSION..."
if ! opkg install "$IPK" >>"$LOG" 2>&1; then
    if grep -qi "no candidates to install" "$LOG"; then
        say "      Retrying verified package with --force-reinstall..."
        opkg install --force-reinstall "$IPK" >>"$LOG" 2>&1 || fail "Package installation failed. See $LOG"
    else
        fail "Package installation failed. See $LOG"
    fi
fi

INSTALLED="$(opkg status "$PACKAGE" 2>/dev/null | awk -F': ' '/^Version:/{print $2; exit}')"
[ "$INSTALLED" = "$VERSION" ] || fail "Installed package version is ${INSTALLED:-unknown}; expected $VERSION."
say "[OK] Installed package version: $INSTALLED"

say ""
say "[5/5] Cleaning temporary package..."
cleanup
sync 2>/dev/null || true
say "[OK] Ultra Stalker V$VERSION installed successfully."
say "      Enigma2 restart is handled automatically by the package."
exit 0
