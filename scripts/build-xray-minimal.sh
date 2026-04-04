#!/bin/bash
# Build minimal xray-core binary for aarch64
# VLESS + XHTTP + Reality only — quic-go removed
set -euo pipefail

echo ">> Cloning Xray-core (latest)..."
git clone --depth=1 https://github.com/XTLS/Xray-core /tmp/xray-src
cd /tmp/xray-src

XRAY_VER=$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)
echo ">> Version: $XRAY_VER"

# ── Patch 1: minimal all.go ───────────────────────────────────────────────────
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

# ── Patch 2: stub nameserver_quic.go (removes quic-go from app/dns) ───────────
echo ">> Stubbing nameserver_quic.go (DNS-over-QUIC not needed)..."
cat > app/dns/nameserver_quic.go << 'GOEOF'
package dns

import (
	"context"
	"net/url"

	"github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/common/net"
	dns_feature "github.com/xtls/xray-core/features/dns"
)

const NextProtoDQ = "doq"

// QUICNameServer stub — DNS-over-QUIC removed to reduce binary size.
// VLESS+XHTTP+Reality does not use DoQ.
type QUICNameServer struct {
	cacheController *CacheController
	destination     *net.Destination
	clientIP        net.IP
}

func NewQUICNameServer(url *url.URL, disableCache bool, serveStale bool, serveExpiredTTL uint32, clientIP net.IP) (*QUICNameServer, error) {
	return &QUICNameServer{}, errors.New("DNS-over-QUIC not supported in this build")
}

func (s *QUICNameServer) Name() string {
	if s.destination == nil {
		return "quic://unsupported"
	}
	return "quic:" + s.destination.String()
}

func (s *QUICNameServer) IsDisableCache() bool {
	return false
}

func (s *QUICNameServer) newReqID() uint16 {
	return 0
}

func (s *QUICNameServer) getCacheController() *CacheController {
	return s.cacheController
}

func (s *QUICNameServer) sendQuery(ctx context.Context, noResponseErrCh chan<- error, fqdn string, option dns_feature.IPOption) {
	go func() {
		select {
		case noResponseErrCh <- errors.New("DNS-over-QUIC not supported"):
		case <-ctx.Done():
		}
	}()
}

func (s *QUICNameServer) QueryIP(ctx context.Context, domain string, option dns_feature.IPOption) ([]net.IP, uint32, error) {
	return nil, 0, errors.New("DNS-over-QUIC not supported in this build")
}
GOEOF

# ── Patch 3: remove HTTP/3 (quic-go) from splithttp/dialer.go ─────────────────
echo ">> Patching splithttp/dialer.go to remove HTTP/3 / quic-go dependency..."
python3 << 'PYEOF'
import re

path = 'transport/internet/splithttp/dialer.go'
with open(path) as f:
    content = f.read()

# Step 1: remove quic-go imports
content = re.sub(r'\t"github\.com/apernet/quic-go"\n', '', content)
content = re.sub(r'\t"github\.com/apernet/quic-go/http3"\n', '', content)
content = re.sub(r'\t[^\n]*/congestion"\n', '', content)
content = re.sub(r'\t[^\n]*/udphop"\n', '', content)

# Step 2: find the H3 block that actually contains quic — anchored after "var transport"
# There are TWO `if httpVersion == "3"` blocks; the first is tiny (sets dest.Network).
# The second, which contains all quic/http3 usage, appears after "var transport http.RoundTripper".
anchor = 'var transport http.RoundTripper'
anchor_idx = content.find(anchor)
if anchor_idx == -1:
    print("ERROR: anchor not found"); exit(1)

marker = 'if httpVersion == "3" {'
# Search only after the anchor
search_from = anchor_idx + len(anchor)
idx = content.find(marker, search_from)
if idx == -1:
    print("ERROR: H3 marker not found after anchor"); exit(1)

# brace_start = position of the `{` that opens the H3 body
brace_start = idx + len(marker) - 1
depth = 1
pos = brace_start + 1
while pos < len(content) and depth > 0:
    if content[pos] == '{':
        depth += 1
    elif content[pos] == '}':
        depth -= 1
    pos += 1
# content[pos-1] is the matching `}` — replace body between { and }
content = (content[:brace_start + 1] +
           '\n\t\t// HTTP/3 (quic-go) removed: not needed for VLESS+XHTTP+Reality\n\t' +
           content[pos - 1:])

print(f"H3 block stubbed OK (was at offset {idx})")

with open(path, 'w') as f:
    f.write(content)

print("dialer.go patched OK")
PYEOF

# Fix any remaining unused imports in dialer.go with goimports
go install golang.org/x/tools/cmd/goimports@latest 2>/dev/null || true
GOPATH_BIN=$(go env GOPATH)/bin
if [ -x "$GOPATH_BIN/goimports" ]; then
    echo ">> Running goimports on dialer.go..."
    "$GOPATH_BIN/goimports" -w transport/internet/splithttp/dialer.go
fi

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
