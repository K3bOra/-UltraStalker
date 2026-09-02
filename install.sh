#!/bin/sh
set -eu

REPO="https://github.com/K3bOra/-UltraStalker"
TAG="v10.0.60"
ASSET="UltraStalker_V7.2.5.ipk"
URL="$REPO/releases/download/$TAG/$ASSET"
SHA256="36966bc0610d19c82907446540829a3adfbb0bb608f997f78ffe773c94ea30ca"
IPK="/tmp/$ASSET"
PART="$IPK.part"

log() { echo "[UltraStalker Recovery] $*"; }
fail() { echo "[UltraStalker Recovery] ERROR: $*" >&2; exit 1; }

rm -f "$IPK" "$PART"
log "Downloading $ASSET..."
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
else
    GOT="$(python3 - "$IPK" <<'PY'
import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
print(h.hexdigest())
PY
)"
fi
[ "$GOT" = "$SHA256" ] || fail "SHA256 mismatch: $GOT"
log "SHA256 OK"

# Try the image's package manager first. Some receivers work perfectly here.
OPKG_OUT="/tmp/UltraStalker_recovery_opkg.log"
if command -v opkg >/dev/null 2>&1; then
    if opkg install --force-reinstall "$IPK" >"$OPKG_OUT" 2>&1; then
        cat "$OPKG_OUT"
        log "Installed by opkg"
        exit 0
    fi
    cat "$OPKG_OUT" || true
    log "opkg rejected the local IPK; using verified payload recovery..."
fi

python3 - "$IPK" <<'PY'
import io, os, re, shutil, subprocess, sys, tarfile, time
ipk=sys.argv[1]

def ar_members(path):
    out={}
    with open(path,'rb') as f:
        if f.read(8)!=b'!<arch>\n': raise SystemExit('invalid IPK header')
        while True:
            h=f.read(60)
            if not h: break
            if len(h)!=60 or h[58:60]!=b'`\n': raise SystemExit('corrupt IPK header')
            name=h[:16].decode('ascii','replace').strip().rstrip('/')
            size=int(h[48:58].decode('ascii','replace').strip() or '0')
            data=f.read(size)
            if len(data)!=size: raise SystemExit('truncated IPK')
            if size & 1: f.read(1)
            out[name]=data
    return out

def rel(name):
    s=str(name or '').replace('\\','/')
    while s.startswith('./'): s=s[2:]
    if s.startswith('/'): raise SystemExit('unsafe absolute payload path')
    p=[x for x in s.split('/') if x not in ('','.')]
    if '..' in p: raise SystemExit('unsafe payload traversal')
    return '/'.join(p)

def write_member(tf,m,dst):
    if m.isdir():
        os.makedirs(dst,exist_ok=True); return
    if not m.isfile(): raise SystemExit('unsupported payload member: '+m.name)
    os.makedirs(os.path.dirname(dst),exist_ok=True)
    src=tf.extractfile(m)
    if src is None: raise SystemExit('cannot read payload member: '+m.name)
    tmp=dst+'.usnew'
    with open(tmp,'wb') as o:
        shutil.copyfileobj(src,o,256*1024); o.flush(); os.fsync(o.fileno())
    try: os.chmod(tmp,m.mode or 0o644)
    except Exception: pass
    os.replace(tmp,dst)

m=ar_members(ipk)
cb=m.get('control.tar.gz'); db=m.get('data.tar.gz')
if not cb or not db: raise SystemExit('IPK missing control/data archives')
with tarfile.open(fileobj=io.BytesIO(cb),mode='r:gz') as tf:
    c=next((x for x in tf.getmembers() if rel(x.name)=='control'),None)
    if c is None: raise SystemExit('missing control metadata')
    txt=tf.extractfile(c).read().decode('utf-8','replace')
fields={}
for line in txt.splitlines():
    if ':' in line and not line[:1].isspace():
        k,v=line.split(':',1); fields[k.strip()]=v.strip()
if fields.get('Package')!='enigma2-plugin-extensions-ultrastalker':
    raise SystemExit('unexpected package identity')
ver=fields.get('Version','')
if ver!='7.2.5': raise SystemExit('unexpected package version: '+ver)

parent='/usr/lib/enigma2/python/Plugins/Extensions'
root=os.path.join(parent,'UltraStalker')
tag='%d_%d'%(os.getpid(),int(time.time()))
new=os.path.join(parent,'.UltraStalker_new_'+tag)
old=os.path.join(parent,'.UltraStalker_old_'+tag)
prefix='usr/lib/enigma2/python/Plugins/Extensions/UltraStalker/'
shutil.rmtree(new,ignore_errors=True); os.makedirs(new)
try:
    with tarfile.open(fileobj=io.BytesIO(db),mode='r:gz') as tf:
        mem=tf.getmembers()
        for x in mem:
            r=rel(x.name)
            if r.startswith(prefix):
                inner=r[len(prefix):]
                if inner: write_member(tf,x,os.path.join(new,inner))
        for req in ('plugin.py','version.py','updater.py'):
            if not os.path.isfile(os.path.join(new,req)): raise SystemExit('missing '+req)
        vt=open(os.path.join(new,'version.py'),'r').read(4096)
        mm=re.search(r'^PLUGIN_VERSION\s*=\s*["\']([^"\']+)',vt,re.M)
        if not mm or mm.group(1).strip()!=ver: raise SystemExit('version mismatch in staged plugin')
        had=os.path.isdir(root)
        if had: os.rename(root,old)
        try: os.rename(new,root)
        except Exception:
            if had and os.path.isdir(old) and not os.path.exists(root): os.rename(old,root)
            raise
        for x in mem:
            r=rel(x.name)
            if r=='usr/bin/ultrastalker-deps' or r.startswith('etc/enigma2/ultrastalker/.uslib/'):
                if not r.endswith('/'): write_member(tf,x,'/'+r)
    shutil.rmtree(old,ignore_errors=True)
finally:
    shutil.rmtree(new,ignore_errors=True)
print('[UltraStalker Recovery] Verified payload installed successfully: V'+ver)
PY

log "Done. Restart Enigma2 to load V7.2.5."
