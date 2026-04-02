#!/bin/bash
# Custom settings applied AFTER feeds install, BEFORE make
# Runs inside openwrt/ source directory
set -euo pipefail

CONFIG_GEN="package/base-files/files/bin/config_generate"

# ── LAN IP ────────────────────────────────────────────────────────────────────
sed -i 's|192\.168\.1\.1|192.168.10.1|g' "$CONFIG_GEN"
echo ">> LAN IP: 192.168.10.1"

# ── Hostname ──────────────────────────────────────────────────────────────────
sed -i 's|ImmortalWrt|WR3000|g' "$CONFIG_GEN"

# ── Timezone ──────────────────────────────────────────────────────────────────
cat > "package/base-files/files/etc/uci-defaults/99-timezone" << 'EOF'
#!/bin/sh
uci -q batch <<EOB
set system.@system[0].timezone='EET-2EEST,M3.5.0/3,M10.5.0/4'
set system.@system[0].zonename='Europe/Kyiv'
commit system
EOB
EOF
chmod +x "package/base-files/files/etc/uci-defaults/99-timezone"

# ── Patch xray-core: strip unused protocols ───────────────────────────────────
XRAY_PATCHES="$GITHUB_WORKSPACE/patches/xray-core"
XRAY_PKG=""

# Find xray-core package directory (could be in different feeds)
for d in feeds/passwall_packages/xray-core feeds/packages/net/xray-core; do
  if [ -d "$d" ]; then
    XRAY_PKG="$d"
    break
  fi
done

if [ -n "$XRAY_PKG" ] && [ -d "$XRAY_PATCHES" ]; then
  mkdir -p "$XRAY_PKG/patches"
  cp "$XRAY_PATCHES"/*.patch "$XRAY_PKG/patches/"
  echo ">> Xray minimal patch copied to $XRAY_PKG/patches/"
  ls -la "$XRAY_PKG/patches/"
else
  echo "!! WARNING: xray-core package dir not found or no patches"
  echo "   Searched: feeds/passwall_packages/xray-core, feeds/packages/net/xray-core"
  ls feeds/passwall_packages/ 2>/dev/null || echo "   passwall_packages feed not found"
fi

echo ">> Customizations applied."
