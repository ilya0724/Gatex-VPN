#!/usr/bin/env bash
# Packs the flutter Linux bundle and gatex-core into a .deb.
# usage: build-deb.sh <bundle-dir> <version> <out-dir>
set -euo pipefail
bundle=$1 version=$2 out=$3
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)

mkdir -p "$root/opt/gatex" "$root/usr/bin" "$root/DEBIAN" \
  "$root/usr/share/applications" "$root/usr/share/icons/hicolor/256x256/apps"
cp -r "$bundle"/. "$root/opt/gatex/"
ln -s /opt/gatex/gatex "$root/usr/bin/gatex"
cp "$here/gatex.desktop" "$root/usr/share/applications/"
cp "$here/../../linux/gatex.png" "$root/usr/share/icons/hicolor/256x256/apps/gatex.png"

cat > "$root/DEBIAN/control" <<CONTROL
Package: gatex
Version: $version
Section: net
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libcap2-bin, libayatana-appindicator3-1
Maintainer: GateX <support@gatexx.ru>
Homepage: https://gatexx.ru
Description: GateX VPN client
 One-tap VPN for GateX subscriptions.
CONTROL

# The core needs to create a TUN and set routes; capabilities let it do
# that without running the whole app as root.
cat > "$root/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
setcap cap_net_admin,cap_net_raw,cap_net_bind_service+ep /opt/gatex/gatex-core || true
command -v update-desktop-database >/dev/null && update-desktop-database -q || true
exit 0
POSTINST
chmod 755 "$root/DEBIAN/postinst"

mkdir -p "$out"
dpkg-deb --root-owner-group --build "$root" "$out/gatex_${version}_amd64.deb"
rm -rf "$root"
