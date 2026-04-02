#!/bin/bash
# Add passwall2 feeds and apply xray-core minimal patch
# Runs inside openwrt/ source directory
set -euo pipefail

echo ">> Adding passwall feeds..."
echo 'src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main' >> feeds.conf.default
echo 'src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git;main' >> feeds.conf.default

# Verify feeds can be cloned (fail early with useful error)
echo ">> Testing passwall2 repo accessibility..."
git ls-remote --exit-code https://github.com/xiaorouji/openwrt-passwall2.git main || {
  echo ">> xiaorouji/openwrt-passwall2 not accessible, trying Openwrt-Passwall org..."
  sed -i 's|xiaorouji/openwrt-passwall2|Openwrt-Passwall/openwrt-passwall2|' feeds.conf.default
}
git ls-remote --exit-code https://github.com/xiaorouji/openwrt-passwall-packages.git main || {
  echo ">> xiaorouji/openwrt-passwall-packages not accessible, trying Openwrt-Passwall org..."
  sed -i 's|xiaorouji/openwrt-passwall-packages|Openwrt-Passwall/openwrt-passwall-packages|' feeds.conf.default
}

echo ">> feeds.conf.default:"
cat feeds.conf.default
