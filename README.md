# ImmortalWrt auto-build for Cudy WR3000 v1

GitHub Actions workflow that builds a custom ImmortalWrt firmware for the
**Cudy WR3000 v1 (MT7981B, AX3000)** router with **PassWall2 + Xray-core**.

## Quick start

1. Fork this repository on GitHub.
2. Go to **Settings → Actions → General** and set workflow permissions to
   "Read and write".
3. Go to **Actions → Build ImmortalWrt for Cudy WR3000 v1 → Run workflow**.
4. After ~90 minutes the firmware appears under **Releases** (or **Artifacts**).

## What is built

| Component | Details |
|-----------|---------|
| Base | ImmortalWrt `openwrt-24.10` branch |
| Target | `mediatek/filogic` |
| Device profile | `cudy_wr3000-v1` |
| PassWall2 | `xiaorouji/openwrt-passwall2` (main) |
| xray-core | via `xiaorouji/openwrt-passwall-packages` (main) |
| LuCI theme | Bootstrap |
| LAN IP | `192.168.10.1` (configurable in `scripts/diy-custom.sh`) |
| Timezone default | Europe/Kyiv |

## File layout

```
.github/workflows/build.yml   — GitHub Actions pipeline
config/cudy-wr3000-v1.config  — Package selection (.config)
scripts/diy-feeds.sh          — Adds passwall feeds before feed update
scripts/diy-custom.sh         — LAN IP, hostname, timezone, misc patches
```

## Customization

### Change LAN IP or hostname
Edit `scripts/diy-custom.sh`:
```bash
LAN_IP="192.168.10.1"
HOSTNAME="WR3000"
```

### Add xray-core to the image (baked in)
The default config installs xray-core via opkg after flashing to save the
15 MB image budget. To bake it in, uncomment in `config/cudy-wr3000-v1.config`:
```
CONFIG_PACKAGE_xray-core=y
```
Note: xray-core binary is ~8–12 MB compressed; this will push the image close
to the 15424 KB limit. Remove `wireguard-*` packages to compensate.

### Add USB storage support
Uncomment the USB block in `config/cudy-wr3000-v1.config`.

### Interactive menuconfig (SSH into the runner)
Trigger the workflow with **ssh: true** — you will get a tmate link in the
Actions log to connect and run `make menuconfig` interactively. The result is
committed back to the repo automatically.

## xray-core: install via opkg after flashing

```sh
opkg update
# Add passwall feed (moetayuko prebuilt mirror for aarch64_cortex-a53)
echo "src/gz passwall https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-24.10/aarch64_cortex-a53/passwall_packages" \
  >> /etc/opkg/customfeeds.conf
echo "src/gz passwall2 https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-24.10/aarch64_cortex-a53/passwall2" \
  >> /etc/opkg/customfeeds.conf
opkg update
opkg install xray-core luci-app-passwall2
```

## Notes

- Build time on GitHub-hosted runners (ubuntu-22.04): ~60–120 minutes.
- Image limit is **15424 KB** (~15 MB). Monitor with `make -j1 V=s` locally.
- The schedule trigger runs on the **1st of each month** at 03:00 UTC.
- Old releases are pruned automatically (keeps last 5).
