#!/bin/bash
# Build minimal xray-core binary for aarch64
# VLESS + XHTTP + Reality only
set -euo pipefail

echo ">> Cloning Xray-core (latest)..."
git clone --depth=1 https://github.com/XTLS/Xray-core /tmp/xray-src
cd /tmp/xray-src

XRAY_VER=$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)
echo ">> Version: $XRAY_VER"

# ── Patch: minimal all.go ─────────────────────────────────────────────────────
# Go linker (dead code elimination) will NOT include packages that are not
# imported anywhere in the import graph. So cutting all.go is enough —
# we don't need to touch go.mod or individual transport files.
echo ">> Patching all.go to minimal protocol set..."
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

	// Config: JSON only
	_ "github.com/xtls/xray-core/main/json"
	_ "github.com/xtls/xray-core/main/confloader/external"
	_ "github.com/xtls/xray-core/main/commands/all"
)
GOEOF

# ── Build ─────────────────────────────────────────────────────────────────────
echo ">> Building xray for linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -trimpath -ldflags="-s -w -buildid=" -o xray ./main

RAW=$(stat -c%s xray)
echo ">> Raw binary: $((RAW / 1024 / 1024)) MB ($RAW bytes)"

# ── Analyse what's in binary ──────────────────────────────────────────────────
echo ">> Top packages by size:"
go tool nm xray 2>/dev/null | awk '{ print $3 }' | \
    grep -oE '^[^.]+\.[^.]+' | sort | uniq -c | sort -rn | head -20 || true

# ── Compress with UPX ────────────────────────────────────────────────────────
echo ">> Installing UPX..."
apt-get install -y upx-ucl -qq 2>/dev/null || true

if command -v upx &>/dev/null; then
    echo ">> Compressing with UPX --ultra-brute..."
    upx --ultra-brute --lzma -o xray-upx xray 2>&1 || \
    upx --best --lzma -o xray-upx xray 2>&1 || \
    cp xray xray-upx

    UPX=$(stat -c%s xray-upx)
    echo ">> UPX binary: $((UPX / 1024 / 1024)) MB ($UPX bytes)"
    echo ">> Ratio: $((UPX * 100 / RAW))% of raw"
    cp xray-upx "$GITHUB_WORKSPACE/xray"
else
    echo ">> UPX not available, using raw"
    cp xray "$GITHUB_WORKSPACE/xray"
fi

FINAL=$(stat -c%s "$GITHUB_WORKSPACE/xray")
echo ">> ================================"
echo ">> Final binary: $((FINAL / 1024)) KB ($FINAL bytes)"
echo ">> Router overlay free: ~5529600 bytes (5.4 MB)"
if [ $FINAL -le 5529600 ]; then
    echo ">> FITS IN OVERLAY!"
else
    OVER=$(( (FINAL - 5529600) / 1024 ))
    echo ">> Too large by ${OVER} KB"
fi
echo ">> ================================"
