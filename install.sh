#!/bin/sh
set -u

REPO="https://github.com/K3bOra/-UltraStalker"
TAG="v10.0.60"
ASSET="UltraStalker_V7_UPDATE.ipk"
URL="$REPO/releases/download/$TAG/$ASSET"
SHA256="9650246680056e11fac0af060290213e6e6408cf300477067d446b16d3e82944"
VERSION="7.5"
IPK="/tmp/$ASSET"
PART="$IPK.part"
OPKG_OUT="/tmp/UltraStalker_install_opkg.log"
REFRESHED=0

say() { printf '%s\n' "$*"; }
fail() {
    say ""
    say "[ERROR] $*"
    rm -f "$PART" 2>/dev/null || true
    exit 1
}

refresh_feeds_once() {
    [ "$REFRESHED" -eq 1 ] && return 0
    say "      Refreshing package feeds because a required library is missing..."
    opkg update || fail "Could not refresh package feeds."
    REFRESHED=1
}

py_import_ok() {
    python3 - "$1" <<'PY' >/dev/null 2>&1
import sys
name=sys.argv[1]
if name == "sqlite3":
    import sqlite3
elif name == "pillow":
    from PIL import Image
elif name == "twisted":
    import twisted
    from twisted.web.client import Agent
else:
    raise SystemExit(1)
PY
}

install_pkg() {
    label="$1"
    pkg="$2"
    check="$3"
    if py_import_ok "$check"; then
        say "[OK] $label"
        return 0
    fi
    say "[MISSING] $label"
    refresh_feeds_once
    say "      Installing $pkg..."
    opkg install "$pkg" || fail "Could not install required dependency: $pkg"
    py_import_ok "$check" || fail "$label is still unavailable after installation."
    say "[OK] $label installed successfully."
}

verify_ipk() {
    python3 - "$IPK" "$VERSION" <<'PY'
import io, re, sys, tarfile
ipk=sys.argv[1]
expected=sys.argv[2]

def ar_members(path):
    out={}
    with open(path,'rb') as f:
        if f.read(8)!=b'!<arch>\n':
            raise SystemExit('invalid IPK header')
        while True:
            h=f.read(60)
            if not h:
                break
            if len(h)!=60 or h[58:60]!=b'`\n':
                raise SystemExit('corrupt IPK archive')
            name=h[:16].decode('ascii','replace').strip().rstrip('/')
            size=int(h[48:58].decode('ascii','replace').strip() or '0')
            data=f.read(size)
            if len(data)!=size:
                raise SystemExit('truncated IPK member')
            if size & 1:
                f.read(1)
            out[name]=data
    return out

m=ar_members(ipk)
control=m.get('control.tar.gz')
data=m.get('data.tar.gz')
if not control or not data:
    raise SystemExit('missing control/data archive')

with tarfile.open(fileobj=io.BytesIO(control),mode='r:gz') as tf:
    cm=next((x for x in tf.getmembers() if x.name.lstrip('./')=='control'),None)
    if cm is None:
        raise SystemExit('missing control metadata')
    text=tf.extractfile(cm).read().decode('utf-8','replace')
fields={}
for line in text.splitlines():
    if ':' in line and not line[:1].isspace():
        k,v=line.split(':',1)
        fields[k.strip()]=v.strip()
if fields.get('Package')!='enigma2-plugin-extensions-ultrastalker':
    raise SystemExit('unexpected package identity')
if fields.get('Version')!=expected:
    raise SystemExit('unexpected package version: '+fields.get('Version','<missing>'))

with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as tf:
    target='usr/lib/enigma2/python/Plugins/Extensions/UltraStalker/version.py'
    vm=next((x for x in tf.getmembers() if x.name.lstrip('./')==target),None)
    if vm is None:
        raise SystemExit('missing version.py')
    text=tf.extractfile(vm).read().decode('utf-8','replace')
match=re.search(r'^PLUGIN_VERSION\s*=\s*["\']([^"\']+)',text,re.M)
if not match or match.group(1).strip()!=expected:
    raise SystemExit('version.py mismatch')
print('[OK] Verified Ultra Stalker package V'+expected)
PY
}

atomic_recovery_install() {
    python3 - "$IPK" "$VERSION" <<'PY'
import io, os, re, shutil, sys, tarfile, time
ipk=sys.argv[1]
expected_version=sys.argv[2]

def ar_members(path):
    out={}
    with open(path,'rb') as f:
        if f.read(8)!=b'!<arch>\n':
            raise SystemExit('invalid IPK header')
        while True:
            h=f.read(60)
            if not h:
                break
            if len(h)!=60 or h[58:60]!=b'`\n':
                raise SystemExit('corrupt IPK header')
            name=h[:16].decode('ascii','replace').strip().rstrip('/')
            size=int(h[48:58].decode('ascii','replace').strip() or '0')
            data=f.read(size)
            if len(data)!=size:
                raise SystemExit('truncated IPK')
            if size & 1:
                f.read(1)
            out[name]=data
    return out

def rel(name):
    s=str(name or '').replace('\\','/')
    while s.startswith('./'):
        s=s[2:]
    if s.startswith('/'):
        raise SystemExit('unsafe absolute payload path')
    parts=[x for x in s.split('/') if x not in ('','.')]
    if '..' in parts:
        raise SystemExit('unsafe payload traversal')
    return '/'.join(parts)

def write_member(tf,m,dst):
    if m.isdir():
        os.makedirs(dst,exist_ok=True)
        return
    if not m.isfile():
        raise SystemExit('unsupported payload member: '+m.name)
    parent=os.path.dirname(dst)
    if parent:
        os.makedirs(parent,exist_ok=True)
    src=tf.extractfile(m)
    if src is None:
        raise SystemExit('cannot read payload member: '+m.name)
    tmp=dst+'.usnew'
    with open(tmp,'wb') as out:
        shutil.copyfileobj(src,out,256*1024)
        out.flush(); os.fsync(out.fileno())
    try:
        os.chmod(tmp,m.mode or 0o644)
    except Exception:
        pass
    os.replace(tmp,dst)

members=ar_members(ipk)
control_blob=members.get('control.tar.gz')
data_blob=members.get('data.tar.gz')
if not control_blob or not data_blob:
    raise SystemExit('IPK missing control/data archives')

with tarfile.open(fileobj=io.BytesIO(control_blob),mode='r:gz') as tf:
    cm=next((x for x in tf.getmembers() if rel(x.name)=='control'),None)
    if cm is None:
        raise SystemExit('missing control metadata')
    control_text=tf.extractfile(cm).read().decode('utf-8','replace')
fields={}
for line in control_text.splitlines():
    if ':' in line and not line[:1].isspace():
        k,v=line.split(':',1); fields[k.strip()]=v.strip()
if fields.get('Package')!='enigma2-plugin-extensions-ultrastalker':
    raise SystemExit('unexpected package identity')
if fields.get('Version','')!=expected_version:
    raise SystemExit('unexpected package version: '+fields.get('Version',''))

parent='/usr/lib/enigma2/python/Plugins/Extensions'
root=os.path.join(parent,'UltraStalker')
tag='%d_%d'%(os.getpid(),int(time.time()))
new=os.path.join(parent,'.UltraStalker_new_'+tag)
old=os.path.join(parent,'.UltraStalker_old_'+tag)
prefix='usr/lib/enigma2/python/Plugins/Extensions/UltraStalker/'
shutil.rmtree(new,ignore_errors=True)
os.makedirs(new)
try:
    with tarfile.open(fileobj=io.BytesIO(data_blob),mode='r:gz') as tf:
        entries=tf.getmembers()
        for entry in entries:
            path=rel(entry.name)
            if path.startswith(prefix):
                inner=path[len(prefix):]
                if inner:
                    write_member(tf,entry,os.path.join(new,inner))
        for required in ('plugin.py','version.py','updater.py'):
            if not os.path.isfile(os.path.join(new,required)):
                raise SystemExit('missing '+required)
        version_text=open(os.path.join(new,'version.py'),'r').read(4096)
        match=re.search(r'^PLUGIN_VERSION\s*=\s*["\']([^"\']+)',version_text,re.M)
        if not match or match.group(1).strip()!=expected_version:
            raise SystemExit('version mismatch in staged plugin')
        had_root=os.path.isdir(root)
        if had_root:
            os.rename(root,old)
        try:
            os.rename(new,root)
        except Exception:
            if had_root and os.path.isdir(old) and not os.path.exists(root):
                os.rename(old,root)
            raise
        for entry in entries:
            path=rel(entry.name)
            if path=='usr/bin/ultrastalker-deps' or path.startswith('etc/enigma2/ultrastalker/.uslib/'):
                if path and not path.endswith('/'):
                    write_member(tf,entry,'/'+path)
    shutil.rmtree(old,ignore_errors=True)
finally:
    shutil.rmtree(new,ignore_errors=True)
print('[OK] Verified atomic payload installed successfully: V'+expected_version)
PY
}

say "=============================================="
say "          Ultra Stalker V$VERSION"
say "          Final Public Installer"
say "=============================================="
say ""

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found. This receiver is not supported."

say "[1/5] Checking receiver requirements..."
if ! command -v python3 >/dev/null 2>&1; then
    say "[MISSING] python3-core"
    refresh_feeds_once
    say "      Installing python3-core..."
    opkg install python3-core || fail "Could not install python3-core."
fi
PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
case "$PYVER" in
    3.12|3.13|3.14) say "[OK] Python $PYVER" ;;
    *) fail "Unsupported Python version: ${PYVER:-not found}. Required: 3.12 / 3.13 / 3.14." ;;
esac
install_pkg "python3-sqlite3" "python3-sqlite3" "sqlite3"
install_pkg "python3-pillow" "python3-pillow" "pillow"
install_pkg "python3-twisted" "python3-twisted" "twisted"
say "[OK] All required libraries are ready."
say ""

say "[2/5] Downloading Ultra Stalker V$VERSION..."
rm -f "$IPK" "$PART" "$OPKG_OUT" 2>/dev/null || true
if command -v wget >/dev/null 2>&1; then
    wget -O "$PART" "$URL" || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$URL" -o "$PART" || fail "Download failed."
else
    fail "wget/curl was not found."
fi
[ -s "$PART" ] || fail "Downloaded file is empty."
mv "$PART" "$IPK"
say "[OK] Download completed."
say ""

say "[3/5] Verifying package integrity..."
if command -v sha256sum >/dev/null 2>&1; then
    GOT="$(sha256sum "$IPK" | awk '{print $1}')"
elif command -v busybox >/dev/null 2>&1; then
    GOT="$(busybox sha256sum "$IPK" | awk '{print $1}')"
else
    GOT="$(python3 - "$IPK" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for b in iter(lambda:f.read(1024*1024),b''):
        h.update(b)
print(h.hexdigest())
PY
)"
fi
[ "$GOT" = "$SHA256" ] || fail "SHA256 mismatch: $GOT"
say "[OK] SHA256 verified."
verify_ipk || fail "Package structure/version validation failed."
say ""

say "[4/5] Installing Ultra Stalker..."
if opkg install "$IPK" >"$OPKG_OUT" 2>&1; then
    cat "$OPKG_OUT"
    say "[OK] Ultra Stalker V$VERSION installed successfully."
    say "[5/5] Enigma2 restart has been scheduled by the package."
    exit 0
fi
cat "$OPKG_OUT" || true
say "[WARN] opkg rejected the verified local IPK; using the safe recovery path..."
atomic_recovery_install || fail "Recovery installation failed."

rm -rf /media/hdd/UltraStalker/cast 2>/dev/null || true
if [ -d /media/hdd/UltraStalker/library ]; then
    find /media/hdd/UltraStalker/library -type d -name cast -prune -exec rm -rf '{}' + 2>/dev/null || true
fi
say "[OK] Ultra Stalker V$VERSION installed successfully."
if command -v pidof >/dev/null 2>&1 && pidof enigma2 >/dev/null 2>&1; then
    say "[5/5] Restarting Enigma2 in 5 seconds..."
    sync 2>/dev/null || true
    ( sleep 5; killall -9 enigma2 >/dev/null 2>&1 || true ) >/dev/null 2>&1 &
else
    say "[5/5] Enigma2 is not currently running; automatic restart skipped."
fi
exit 0
