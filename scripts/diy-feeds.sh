#!/bin/bash
# Add passwall2 feeds and apply xray-core minimal patch
# Runs inside openwrt/ source directory
set -euo pipefail

echo ">> Adding passwall feeds..."
echo 'src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main' >> feeds.conf.default
echo 'src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git;main' >> feeds.conf.default

echo ">> feeds.conf.default:"
cat feeds.conf.default
