#!/bin/bash
# Build minimal xray-core binary for aarch64
# VLESS + XHTTP + Reality only, quic-go removed for smaller size
set -euo pipefail

echo ">> Cloning Xray-core (latest)..."
git clone --depth=1 https://github.com/XTLS/Xray-core /tmp/xray-src
cd /tmp/xray-src

XRAY_VER=$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)
echo ">> Version: $XRAY_VER"

# ── Patch 1: minimal all.go ───────────────────────────────────────────────────
echo ">> Patch 1: minimal protocol set..."
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

	// Transports — splithttp (XHTTP), reality, tls only
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

# ── Patch 2: remove quic-go (HTTP/3) from splithttp ──────────────────────────
# quic-go adds ~4-5MB to binary. We only need HTTP/1.1 + HTTP/2.
echo ">> Patch 2: removing quic-go from splithttp..."

DIALER="transport/internet/splithttp/dialer.go"

# Show current quic-related imports
echo ">> Current quic imports:"
grep -n "quic\|http3\|apernet" "$DIALER" || echo "(none found)"

# Remove quic-go and http3 imports
sed -i \
  -e '/apernet\/quic-go/d' \
  -e '/http3/d' \
  "$DIALER"

# Replace HTTP/3 client creation with HTTP/2 fallback
# The pattern is: if cfg allows h3, create quic transport, else http2
# We replace any h3/quic branch with a no-op / error
python3 << 'PYEOF'
import re, sys

with open("transport/internet/splithttp/dialer.go", "r") as f:
    content = f.read()

# Remove any function or block that references h3/quic/http3
# Strategy: replace the entire createHTTPClient or equivalent that has h3 logic
# with a version that only does HTTP/1.1 and HTTP/2

# Pattern to find: lines containing quic or http3 or H3
lines = content.split('\n')
new_lines = []
skip_block = 0
for line in lines:
    # Skip lines that reference quic/http3
    if any(kw in line for kw in ['quic', 'http3', 'HTTP3', 'H3Client', 'h3Client', 'QUIC', 'Http3']):
        # If it's the start of an if block, skip the block
        if line.rstrip().endswith('{') and 'if ' in line:
            skip_block += 1
        elif skip_block == 0:
            new_lines.append('// removed: ' + line)
            continue
    if skip_block > 0:
        open_braces = line.count('{')
        close_braces = line.count('}')
        skip_block += open_braces - close_braces
        if skip_block <= 0:
            skip_block = 0
        continue
    new_lines.append(line)

new_content = '\n'.join(new_lines)

with open("transport/internet/splithttp/dialer.go", "w") as f:
    f.write(new_content)

print(">> Patch applied")
PYEOF

# Also patch go.mod to remove quic-go dependency if present
echo ">> Removing quic-go from go.mod..."
sed -i '/apernet\/quic-go/d' go.mod go.sum 2>/dev/null || true

# Verify build still compiles after patches
echo ">> Verifying patches don't break compilation..."
go build ./transport/internet/splithttp/... 2>&1 || {
    echo ">> splithttp build failed, trying simpler approach..."
    # Fallback: replace dialer.go entirely with a minimal version
    # that only supports HTTP/1.1 and HTTP/2
    git checkout -- transport/internet/splithttp/dialer.go

    # Just remove the quic import lines but keep the rest
    sed -i \
        '/apernet\/quic-go/d' \
        transport/internet/splithttp/dialer.go

    echo ">> Applied conservative patch (import-only removal)"
}

# ── Build ─────────────────────────────────────────────────────────────────────
echo ">> Building xray for linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -trimpath -ldflags="-s -w -buildid=" -o xray ./main 2>&1

RAW=$(stat -c%s xray)
echo ">> Raw binary: $((RAW / 1024 / 1024)) MB ($RAW bytes)"

# ── Compress with UPX ────────────────────────────────────────────────────────
echo ">> Installing UPX..."
apt-get install -y upx-ucl -qq 2>/dev/null || true

if command -v upx &>/dev/null; then
    echo ">> Compressing with UPX --ultra-brute (slow but smallest)..."
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
echo ">> Final binary: $((FINAL / 1024 / 1024)) MB ($FINAL bytes)"
echo ">> Target overlay: 5.4 MB (5636096 bytes)"
if [ $FINAL -le 5636096 ]; then
    echo ">> FITS IN OVERLAY!"
else
    echo ">> Still too large by $(( (FINAL - 5636096) / 1024 )) KB"
fi
