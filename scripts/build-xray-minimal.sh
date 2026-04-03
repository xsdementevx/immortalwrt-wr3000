#!/bin/bash
# Build minimal xray-core binary for aarch64 (VLESS + XHTTP + Reality only)
# Compresses with UPX for minimal size on flash
set -euo pipefail

echo ">> Cloning Xray-core (latest)..."
git clone --depth=1 https://github.com/XTLS/Xray-core /tmp/xray-src
cd /tmp/xray-src

XRAY_VER=$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)
echo ">> Version: $XRAY_VER"

echo ">> Patching for minimal build (VLESS + XHTTP + Reality only)..."
cat > main/distro/all/all.go << 'GOEOF'
package all

import (
	// Core (mandatory)
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"

	// Services
	_ "github.com/xtls/xray-core/app/dns"
	_ "github.com/xtls/xray-core/app/dns/fakedns"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/router"
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"

	// Protocols
	_ "github.com/xtls/xray-core/proxy/blackhole"
	_ "github.com/xtls/xray-core/proxy/dns"
	_ "github.com/xtls/xray-core/proxy/dokodemo"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/socks"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"

	// Transports
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
	_ "github.com/xtls/xray-core/transport/internet/udp"
	_ "github.com/xtls/xray-core/transport/internet/headers/http"
	_ "github.com/xtls/xray-core/transport/internet/headers/noop"

	// Config
	_ "github.com/xtls/xray-core/main/json"
	_ "github.com/xtls/xray-core/main/confloader/external"
	_ "github.com/xtls/xray-core/main/commands/all"
)
GOEOF

echo ">> Building xray for linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -ldflags="-s -w" -o xray ./main

RAW=$(stat -c%s xray)
echo ">> Raw binary: $((RAW / 1024 / 1024)) MB ($RAW bytes)"

echo ">> Installing UPX..."
apt-get update -qq && apt-get install -y upx-ucl >/dev/null 2>&1 || true

echo ">> Compressing with UPX --best --lzma..."
upx --best --lzma -o xray-upx xray || {
  echo ">> UPX failed, trying without --lzma..."
  upx --best -o xray-upx xray || {
    echo ">> UPX not available, using raw binary"
    cp xray xray-upx
  }
}

UPX=$(stat -c%s xray-upx)
echo ">> UPX binary: $((UPX / 1024 / 1024)) MB ($UPX bytes)"
echo ">> Compression ratio: raw=$RAW upx=$UPX ($((UPX * 100 / RAW))%)"

cp xray-upx "$GITHUB_WORKSPACE/xray" 2>/dev/null || cp xray-upx /tmp/xray
echo ">> Done: xray ready ($UPX bytes)"
