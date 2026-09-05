#!/bin/sh
# Ultra Stalker V7.9 Final - Public Production Installer
# Enigma2 / Python 3.12, 3.13, 3.14
set -u

VERSION="7.9"
TAG="v10.0.60"
ASSET="UltraStalker_V7_UPDATE.ipk"
PACKAGE="enigma2-plugin-extensions-ultrastalker"
EXPECTED_SHA256="40240028b4967b91a5e5ae3f330fd0e7bccac8f17a70d7d68a3d6171a4c836cf"
URL="https://github.com/K3bOra/-UltraStalker/releases/download/${TAG}/${ASSET}"
IPK="/tmp/${ASSET}"
PART="${IPK}.part"
LOG="/tmp/ultrastalker_install.log"
REFRESHED=0
FEED_OK=unknown

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
    c.execute("create table us_test(x integer)")
    c.execute("insert into us_test values (1)")
    assert c.execute("select x from us_test").fetchone()[0] == 1
    c.close()
elif name == "pillow":
    from PIL import Image
    im=Image.new("RGB",(2,2))
    assert im.size == (2,2)
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
    if opkg update >>"$LOG" 2>&1; then
        FEED_OK=yes
        say "      Feed refresh: OK"
    else
        FEED_OK=no
        say "      Feed refresh: FAILED; cached package metadata will still be checked."
    fi
    return 0
}

pkg_advertised() {
    p="$1"
    opkg list-installed "$p" 2>/dev/null | grep -q "^$p " && return 0
    opkg list "$p" 2>/dev/null | grep -q "^$p " && return 0
    return 1
}

discover_pkg() {
    kind="$1"
    opkg list 2>/dev/null | awk -v kind="$kind" '
        {
            p=$1; l=tolower(p)
            if (kind=="sqlite" && l ~ /^python3-/ && l ~ /sqlite/) {print p; exit}
            if (kind=="pillow" && l ~ /^python3-/ && (l ~ /pillow/ || l ~ /-pil($|-)/)) {print p; exit}
            if (kind=="twisted" && ((l ~ /^python3-/ && l ~ /twisted/) || l=="twisted")) {print p; exit}
        }
    '
}

resolve_runtime() {
    kind="$1"; label="$2"; canonical="$3"; shift 3
    if py_ok "$kind"; then
        say "[OK] $label"
        return 0
    fi

    say "[MISSING] $label"
    refresh_feeds_once
    tried=""
    for p in "$canonical" "$@"; do
        pkg_advertised "$p" || continue
        case " $tried " in *" $p "*) continue;; esac
        tried="$tried $p"
        say "      Trying package: $p"
        if opkg install "$p" >>"$LOG" 2>&1 && py_ok "$kind"; then
            if [ "$p" != "$canonical" ]; then
                say "      Package-name mismatch resolved with: $p"
            elif [ "$FEED_OK" = "no" ]; then
                say "      Feed failure tolerated using cached metadata."
            fi
            say "[OK] $label"
            return 0
        fi
    done

    d="$(discover_pkg "$kind")"
    if [ -n "$d" ]; then
        case " $tried " in
            *" $d "*) : ;;
            *)
                say "      Discovered package: $d"
                if opkg install "$d" >>"$LOG" 2>&1 && py_ok "$kind"; then
                    say "      Package-name mismatch resolved with discovered package: $d"
                    say "[OK] $label"
                    return 0
                fi
                ;;
        esac
    fi

    if [ "$FEED_OK" = "no" ]; then
        say "      Classification: FEED FAILURE / no usable cached candidate."
    else
        say "      Classification: DEPENDENCY GENUINELY UNAVAILABLE."
    fi
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
with open(sys.argv[1],'rb') as f:
    for b in iter(lambda:f.read(1024*1024),b''):
        h.update(b)
print(h.hexdigest())
PY
    fi
}

say "=============================================="
say "          Ultra Stalker V$VERSION"
say "          Final Public Installer"
say "=============================================="
say ""

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found. This receiver is not supported."
command -v python3 >/dev/null 2>&1 || fail "python3 was not found."

PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
case "$PYVER" in
    3.12|3.13|3.14) say "[OK] Python $PYVER detected." ;;
    *) fail "Unsupported Python version: ${PYVER:-not found}. Required: 3.12 / 3.13 / 3.14." ;;
esac

if py_ok ssl; then
    say "[OK] Python SSL runtime"
else
    say "[WARN] Python SSL runtime check failed; HTTPS download may fail."
fi

say ""
say "[1/5] Checking required Python runtimes..."
FAIL=0
resolve_runtime sqlite "Python SQLite runtime" python3-sqlite3 python3-sqlite python3-modules || FAIL=1
resolve_runtime pillow "Python Pillow runtime" python3-pillow python3-pil python3-pillow-core || FAIL=1
resolve_runtime twisted "Python Twisted runtime" python3-twisted python3-twisted-core twisted || FAIL=1
[ "$FAIL" -eq 0 ] && py_ok sqlite && py_ok pillow && py_ok twisted || fail "One or more required Python runtimes remain unavailable. See $LOG"

say ""
say "[2/5] Downloading official V$VERSION package..."
cleanup
if command -v wget >/dev/null 2>&1; then
    wget -O "$PART" "$URL" >>"$LOG" 2>&1 || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$URL" -o "$PART" >>"$LOG" 2>&1 || fail "Download failed."
else
    fail "Neither wget nor curl is available."
fi
[ -s "$PART" ] || fail "Downloaded package is empty."
SIZE="$(wc -c < "$PART" 2>/dev/null || echo 0)"
case "$SIZE" in ''|*[!0-9]*) fail "Could not verify downloaded package size." ;; esac
[ "$SIZE" -gt 1000000 ] || fail "Downloaded package is unexpectedly small."
mv -f "$PART" "$IPK"
say "[OK] Download complete: $SIZE bytes"

say ""
say "[3/5] Verifying SHA256..."
GOT="$(calc_sha256 "$IPK" 2>/dev/null || true)"
[ -n "$GOT" ] || fail "No SHA256 verifier is available."
[ "$GOT" = "$EXPECTED_SHA256" ] || fail "SHA256 mismatch. Expected $EXPECTED_SHA256 but got $GOT"
say "[OK] SHA256 verified: $GOT"

say ""
say "[4/5] Installing Ultra Stalker V$VERSION..."
opkg install "$IPK" >>"$LOG" 2>&1 || fail "Package installation failed. See $LOG"
INSTALLED="$(opkg status "$PACKAGE" 2>/dev/null | awk -F': ' '/^Version:/{print $2; exit}')"
[ "$INSTALLED" = "$VERSION" ] || fail "Installed version is ${INSTALLED:-unknown}; expected $VERSION."
say "[OK] Installed package version: $INSTALLED"

say ""
say "[5/5] Cleaning temporary package..."
cleanup
sync 2>/dev/null || true
say "[OK] Ultra Stalker V$VERSION installation completed successfully."
say "      Enigma2 restart is handled by the package post-install step."
exit 0
