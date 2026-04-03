#!/bin/bash
# Build minimal xray-core binary for aarch64 (VLESS + XHTTP + Reality only)
# Output: xray.xz (compressed binary, ~4-5 MB)
set -euo pipefail

XRAY_VERSION="${1:-latest}"

echo ">> Cloning Xray-core..."
if [ "$XRAY_VERSION" = "latest" ]; then
  git clone --depth=1 https://github.com/XTLS/Xray-core /tmp/xray-src
else
  git clone --depth=1 --branch "v${XRAY_VERSION}" https://github.com/XTLS/Xray-core /tmp/xray-src
fi
cd /tmp/xray-src

echo ">> Patching for minimal build (VLESS + XHTTP + Reality only)..."
cat > main/distro/all/all.go << 'GOEOF'
package all

import (
	// Core (mandatory)
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"

	// Services (minimal set)
	_ "github.com/xtls/xray-core/app/dns"
	_ "github.com/xtls/xray-core/app/dns/fakedns"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/policy"
	_ "github.com/xtls/xray-core/app/router"
	_ "github.com/xtls/xray-core/transport/internet/tagged/taggedimpl"

	// Protocols (only what we need)
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

	// Config format (JSON only)
	_ "github.com/xtls/xray-core/main/json"
	_ "github.com/xtls/xray-core/main/confloader/external"
	_ "github.com/xtls/xray-core/main/commands/all"
)
GOEOF

echo ">> Building xray for linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -ldflags="-s -w" -o xray ./main

RAWSIZE=$(stat -c%s xray)
echo ">> Raw binary size: $((RAWSIZE / 1024 / 1024)) MB ($RAWSIZE bytes)"

echo ">> Compressing with xz -9..."
xz -9 --keep xray

XZSIZE=$(stat -c%s xray.xz)
echo ">> Compressed size: $((XZSIZE / 1024 / 1024)) MB ($XZSIZE bytes)"

cp xray.xz "$GITHUB_WORKSPACE/xray.xz" 2>/dev/null || cp xray.xz /tmp/xray.xz
echo ">> Done: xray.xz ready"
