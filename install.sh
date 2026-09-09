#!/bin/sh
set -u

MANIFEST_URL="https://raw.githubusercontent.com/K3bOra/-UltraStalker/main/update.json"
PKG="enigma2-plugin-extensions-ultrastalker"
INFO="/usr/lib/opkg/info/${PKG}.list"
WORK="/tmp/ultrastalker-install.$$"
IPK="$WORK/UltraStalker.ipk"
META="$WORK/meta.txt"

cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
mkdir -p "$WORK" || exit 1

say() { printf '%s\n' "$*"; }
fail() { say "[ERROR] $*"; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 is required."
command -v opkg >/dev/null 2>&1 || fail "opkg is required."

say "=============================================="
say "        Ultra Stalker Installer"
say "=============================================="
say "[1/4] Reading official release manifest..."

python3 - "$MANIFEST_URL" "$IPK" "$META" <<'PY'
import hashlib, json, os, re, sys
from urllib.request import Request, urlopen

manifest_url, out_path, meta_path = sys.argv[1:4]
release_prefix = "https://github.com/K3bOra/-UltraStalker/releases/download/"
official_release_tag = "v10.0.60"
asset_re = re.compile(r"^UltraStalker_V(\d+(?:\.\d+){1,3})\.ipk$")

def read_url(url, max_bytes, accept):
    if not str(url).lower().startswith("https://"):
        raise SystemExit("Only HTTPS update sources are allowed")
    req = Request(url, headers={"User-Agent":"UltraStalker-Installer", "Accept":accept, "Cache-Control":"no-cache"})
    with urlopen(req, timeout=20) as r:
        length = r.headers.get("Content-Length")
        if length and int(length) > max_bytes:
            raise SystemExit("Remote file is larger than the safety limit")
        chunks=[]; total=0
        while True:
            b=r.read(128*1024)
            if not b: break
            total += len(b)
            if total > max_bytes:
                raise SystemExit("Remote file exceeded the safety limit")
            chunks.append(b)
        return b"".join(chunks)

raw = read_url(manifest_url, 128*1024, "application/json")
data = json.loads(raw.decode("utf-8"))
if not isinstance(data, dict): raise SystemExit("Invalid update manifest")
version = str(data.get("version") or "").strip()
ipk = str(data.get("ipk") or "").strip()
sha = str(data.get("sha256") or "").strip().lower()
if not re.fullmatch(r"\d+(?:\.\d+){1,3}", version): raise SystemExit("Invalid release version")
if not re.fullmatch(r"[0-9a-f]{64}", sha): raise SystemExit("Invalid release checksum")
if not ipk.startswith(release_prefix): raise SystemExit("Package is outside the official release repository")
tail=ipk[len(release_prefix):]
parts=tail.split("/",1)
if len(parts)!=2: raise SystemExit("Invalid official release URL")
tag, asset=parts
m=asset_re.fullmatch(asset)
if not m or m.group(1)!=version or tag != official_release_tag:
    raise SystemExit("Manifest version/package filename mismatch or package is outside the official release tag")
blob = read_url(ipk, 64*1024*1024, "application/octet-stream")
actual = hashlib.sha256(blob).hexdigest()
if actual != sha: raise SystemExit("Downloaded package failed SHA256 verification")
with open(out_path,"wb") as f:
    f.write(blob); f.flush(); os.fsync(f.fileno())
with open(meta_path,"w",encoding="utf-8") as f:
    f.write(version+"\n"+sha+"\n")
print("[OK] Ultra Stalker V%s downloaded and verified" % version)
PY
[ $? -eq 0 ] || fail "Could not download or verify the official package."

VERSION="$(sed -n '1p' "$META" 2>/dev/null)"
[ -n "$VERSION" ] || fail "Release metadata is missing."

say "[2/4] Repairing legacy package ownership data if needed..."
if [ -f "$INFO" ]; then
    TMP="${INFO}.ultrastalker.$$"
    awk '{ line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if (line != "/" && line != "./" && line != "//" && line != "") print $0 }' "$INFO" > "$TMP" 2>/dev/null || true
    if [ -s "$TMP" ]; then mv -f "$TMP" "$INFO"; else rm -f "$TMP"; fi
fi
say "[OK] Package ownership data is clean."

say "[3/4] Installing Ultra Stalker V$VERSION..."
OUT="$(opkg install "$IPK" 2>&1)"
RC=$?
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'no candidates to install'; then
    OUT2="$(opkg install --force-reinstall "$IPK" 2>&1)"
    RC=$?
    printf '%s\n' "$OUT2"
fi
[ "$RC" -eq 0 ] || fail "opkg could not install Ultra Stalker V$VERSION."

say "[4/4] Ultra Stalker V$VERSION installed successfully."
say "Enigma2 restart is handled by the package installer."
exit 0
