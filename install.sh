#!/bin/sh
# Ultra Stalker - Public Production Installer
# Target: Enigma2 / OpenBH Python 3.13 or 3.14

set -u

PLUGIN_PKG="enigma2-plugin-extensions-ultrastalker"
IPK_NAME="UltraStalker_FINAL_Public_all.ipk"
# CHANGE THIS after uploading the IPK to your GitHub Release:
IPK_URL="https://github.com/K3bOra/-UltraStalker/releases/latest/download/${IPK_NAME}"
TMP_IPK="/tmp/${IPK_NAME}"
DEPS="python3-core python3-sqlite3 python3-pillow"

say() { printf '%s\n' "$*"; }
fail() { say ""; say "[ERROR] $*"; rm -f "$TMP_IPK" 2>/dev/null || true; exit 1; }

say "=============================================="
say "          Ultra Stalker Installer"
say "          Public Production Build"
say "=============================================="

[ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "Please run this installer as root."
command -v opkg >/dev/null 2>&1 || fail "opkg was not found. This receiver is not supported."

# Validate the receiver Python generation before changing anything.
if command -v python3 >/dev/null 2>&1; then
    PYVER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
else
    PYVER=""
fi

case "$PYVER" in
    3.13|3.14)
        say "[OK] Python $PYVER detected."
        ;;
    *)
        fail "Unsupported Python version: ${PYVER:-not found}. Ultra Stalker requires Python 3.13 or 3.14."
        ;;
esac

# Check /tmp space. Package is ~9 MB; leave comfortable room for opkg extraction.
FREE_KB="$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
case "$FREE_KB" in
    ''|*[!0-9]*) ;;
    *) [ "$FREE_KB" -ge 30000 ] || fail "Not enough free space in /tmp. At least 30 MB is required." ;;
esac

say "[1/4] Checking dependencies..."
MISSING=""
for dep in $DEPS; do
    if ! opkg status "$dep" 2>/dev/null | grep -q '^Status:.* installed'; then
        MISSING="$MISSING $dep"
    fi
done

if [ -n "$MISSING" ]; then
    say "      Missing:$MISSING"
    say "      Refreshing package feeds..."
    opkg update >/tmp/ultrastalker-opkg-update.log 2>&1 || \
        say "[WARN] opkg update reported an error; trying available package lists anyway."

    for dep in $MISSING; do
        say "      Installing $dep..."
        opkg install "$dep" || fail "Could not install required dependency: $dep"
    done
else
    say "[OK] Required dependencies are already installed."
fi

say "[2/4] Downloading Ultra Stalker..."
rm -f "$TMP_IPK"
if command -v wget >/dev/null 2>&1; then
    wget -O "$TMP_IPK" "$IPK_URL" || fail "Download failed."
elif command -v curl >/dev/null 2>&1; then
    curl -fL "$IPK_URL" -o "$TMP_IPK" || fail "Download failed."
else
    fail "Neither wget nor curl is available on this receiver."
fi

[ -s "$TMP_IPK" ] || fail "Downloaded package is empty."
SIZE="$(wc -c < "$TMP_IPK" 2>/dev/null || echo 0)"
[ "$SIZE" -gt 1000000 ] || fail "Downloaded file is unexpectedly small and may not be a valid IPK."

say "[3/4] Installing / updating Ultra Stalker..."
# Do not remove the existing plugin first. This avoids deleting user data/cache/settings.
opkg install --force-reinstall "$TMP_IPK" || fail "Package installation failed."

if ! opkg status "$PLUGIN_PKG" 2>/dev/null | grep -q '^Status:.* installed'; then
    fail "opkg finished but Ultra Stalker is not registered as installed."
fi

say "[4/4] Cleaning temporary files..."
rm -f "$TMP_IPK" /tmp/ultrastalker-opkg-update.log 2>/dev/null || true
sync 2>/dev/null || true

say ""
say "=============================================="
say " Ultra Stalker installed successfully."
say " Restart Enigma2 GUI before opening the plugin."
say "=============================================="
exit 0
