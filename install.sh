#!/bin/sh
set -eu

REPO="https://github.com/K3bOra/-UltraStalker"
TAG="v10.0.60"
ASSET="UltraStalker_V7_UPDATE.ipk"
URL="$REPO/releases/download/$TAG/$ASSET"
SHA256="ca6570666a87ca8fc5d16f20f439bb5de6a9393eeee8a05deebddf3ee0d3c16e"
VERSION="7.3"
IPK="/tmp/$ASSET"
PART="$IPK.part"
OPKG_OUT="/tmp/UltraStalker_install_opkg.log"

log() { echo "[UltraStalker V7.3] $*"; }
fail() { echo "[UltraStalker V7.3] ERROR: $*" >&2; exit 1; }

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

# Normal receiver path first. The package itself contains a postinst that
# restarts Enigma2 after a successful opkg install, regardless of install UI.
if command -v opkg >/dev/null 2>&1; then
    if opkg install "$IPK" >"$OPKG_OUT" 2>&1; then
        cat "$OPKG_OUT"
        log "Installed V$VERSION by opkg"
        exit 0
    fi
    cat "$OPKG_OUT" || true
    log "opkg rejected the verified local IPK; using atomic recovery path..."
fi

command -v python3 >/dev/null 2>&1 || fail "python3 is required for recovery install"

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
            try:
                size=int(h[48:58].decode('ascii','replace').strip() or '0')
            except Exception:
                raise SystemExit('invalid IPK member size')
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
        out.flush()
        os.fsync(out.fileno())
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
    control_member=next((x for x in tf.getmembers() if rel(x.name)=='control'),None)
    if control_member is None:
        raise SystemExit('missing control metadata')
    control_text=tf.extractfile(control_member).read().decode('utf-8','replace')

fields={}
for line in control_text.splitlines():
    if ':' in line and not line[:1].isspace():
        k,v=line.split(':',1)
        fields[k.strip()]=v.strip()
if fields.get('Package')!='enigma2-plugin-extensions-ultrastalker':
    raise SystemExit('unexpected package identity')
version=fields.get('Version','')
if version!=expected_version:
    raise SystemExit('unexpected package version: '+version)

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
        if not match or match.group(1).strip()!=version:
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

        # Receiver helpers shipped outside the plugin tree.
        for entry in entries:
            path=rel(entry.name)
            if path=='usr/bin/ultrastalker-deps' or path.startswith('etc/enigma2/ultrastalker/.uslib/'):
                if path and not path.endswith('/'):
                    write_member(tf,entry,'/'+path)

    shutil.rmtree(old,ignore_errors=True)
finally:
    shutil.rmtree(new,ignore_errors=True)

print('[UltraStalker V7.3] Verified atomic payload installed successfully: V'+version)
PY

# Mirror package postinst side effects for the recovery path. Persistent HDD
# artwork is deliberately untouched.
rm -rf /media/hdd/UltraStalker/cast 2>/dev/null || true
if [ -d /media/hdd/UltraStalker/library ]; then
    find /media/hdd/UltraStalker/library -type d -name cast -prune -exec rm -rf '{}' + 2>/dev/null || true
fi

log "Recovery installation complete: V$VERSION"
restart_enigma2
exit 0
