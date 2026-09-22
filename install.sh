#!/bin/sh
set -eu

MANIFEST_URL="https://raw.githubusercontent.com/K3bOra/-UltraStalker/main/update.json"
OFFICIAL_IPK_URL="https://github.com/K3bOra/-UltraStalker/releases/download/v10.0.60/UltraStalker_V7_UPDATE.ipk"
TMP_MANIFEST="/tmp/UltraStalker_update_manifest.$$"
TMP_IPK="/tmp/UltraStalker_online_install.$$.ipk"
TMP_META="/tmp/UltraStalker_update_meta.$$"

cleanup() {
    rm -f "$TMP_MANIFEST" "$TMP_IPK" "$TMP_META" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

fetch() {
    url="$1"
    out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$url"
        return $?
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 15 --max-time 300 -o "$out" "$url"
        return $?
    fi
    python3 - "$url" "$out" <<'PY'
import sys, urllib.request
url, out = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={"User-Agent":"UltraStalker-Installer/9"})
with urllib.request.urlopen(req, timeout=30) as r, open(out, "wb") as f:
    while True:
        b = r.read(131072)
        if not b:
            break
        f.write(b)
PY
}

echo "[Ultra Stalker] Reading online release manifest..."
fetch "$MANIFEST_URL" "$TMP_MANIFEST" || {
    echo "ERROR: Could not download update.json"
    exit 1
}

python3 - "$TMP_MANIFEST" "$OFFICIAL_IPK_URL" > "$TMP_META" <<'PY'
import json, re, sys
p, official = sys.argv[1], sys.argv[2]
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
version = str(d.get("version") or "").strip()
ipk = str(d.get("ipk") or "").strip()
sha = str(d.get("sha256") or "").strip().lower()
if not re.fullmatch(r"\d+(?:\.\d+){1,3}", version):
    raise SystemExit("ERROR: Invalid online version")
if ipk != official:
    raise SystemExit("ERROR: Manifest package URL is not the approved Ultra Stalker asset")
if not re.fullmatch(r"[0-9a-f]{64}", sha):
    raise SystemExit("ERROR: Invalid SHA256 in update.json")
print(version)
print(ipk)
print(sha)
PY

VERSION=$(sed -n '1p' "$TMP_META")
IPK_URL=$(sed -n '2p' "$TMP_META")
EXPECTED_SHA=$(sed -n '3p' "$TMP_META")

[ -n "$VERSION" ] && [ -n "$IPK_URL" ] && [ -n "$EXPECTED_SHA" ] || {
    echo "ERROR: Could not read update metadata"
    exit 1
}

echo "[Ultra Stalker] Downloading Final/Online version $VERSION..."
fetch "$IPK_URL" "$TMP_IPK" || {
    echo "ERROR: Package download failed"
    exit 1
}

python3 - "$TMP_IPK" "$EXPECTED_SHA" <<'PY'
import hashlib, os, sys
p, expected = sys.argv[1], sys.argv[2].lower()
size = os.path.getsize(p) if os.path.isfile(p) else 0
if size < 1024:
    raise SystemExit("ERROR: Downloaded package is empty or truncated")
if size > 64 * 1024 * 1024:
    raise SystemExit("ERROR: Downloaded package is unexpectedly large")
h = hashlib.sha256()
with open(p, "rb") as f:
    for block in iter(lambda: f.read(1024 * 1024), b""):
        h.update(block)
actual = h.hexdigest().lower()
if actual != expected:
    raise SystemExit("ERROR: SHA256 verification failed\nExpected: %s\nActual:   %s" % (expected, actual))
print("[Ultra Stalker] SHA256 verified: %s" % actual)
PY

# Repair only the invalid root ownership entries produced by some very old builds.
python3 - <<'PY'
import os
p = "/usr/lib/opkg/info/enigma2-plugin-extensions-ultrastalker.list"
try:
    if os.path.isfile(p):
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        cleaned = [x for x in lines if x.strip() not in ("", "/", "./")]
        if cleaned != lines:
            t = p + ".ultrastalker-clean"
            with open(t, "w", encoding="utf-8") as f:
                f.writelines(cleaned)
                f.flush()
                os.fsync(f.fileno())
            os.replace(t, p)
except Exception:
    pass
PY

echo "[Ultra Stalker] Installing $VERSION..."
set +e
OUTPUT=$(opkg install "$TMP_IPK" 2>&1)
CODE=$?
set -e
printf '%s\n' "$OUTPUT"

if [ "$CODE" -ne 0 ]; then
    if printf '%s' "$OUTPUT" | grep -qi "no candidates to install"; then
        echo "[Ultra Stalker] Retrying as a verified force-reinstall..."
        opkg install --force-reinstall "$TMP_IPK"
    else
        echo "ERROR: opkg installation failed"
        exit "$CODE"
    fi
fi

sync 2>/dev/null || true
echo "[Ultra Stalker] Installation complete: $VERSION"
echo "Restart Enigma2 to load the new version."
