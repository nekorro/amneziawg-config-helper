#!/bin/bash
# install.sh — Install/update AmneziaWG tools and kernel module on Debian/Ubuntu.
# Idempotent: safe to re-run (pulls latest sources, rebuilds, reloads module).

set -euo pipefail

AWG_TOOLS_REPO="https://github.com/amnezia-vpn/amneziawg-tools.git"
AWG_MODULE_REPO="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git"
AWG_TOOLS_DIR="/opt/amneziawg-tools"
AWG_MODULE_DIR="/opt/amneziawg-linux-kernel-module"
KERNEL=$(uname -r)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

clone_or_pull() {
  local repo="$1" dir="$2"
  if [ -d "$dir" ]; then
    log "Updating $dir..."
    cd "$dir"
    git pull 2>&1
  else
    log "Cloning $repo..."
    git clone "$repo" "$dir" 2>&1
  fi
}

# -----------------------------------------------------------------------------
log "=== AmneziaWG Install Script ==="
log "OS: $(lsb_release -ds 2>/dev/null || grep PRETTY /etc/os-release | cut -d= -f2)"
log "Kernel: $KERNEL"

if [ "$EUID" -ne 0 ]; then
  die "Run via sudo"
fi

# -----------------------------------------------------------------------------
log "--- Installing dependencies ---"
apt-get update
apt-get install -y \
  gcc \
  make \
  git \
  xxd \
  qrencode \
  iptables \
  ipset \
  iproute2 \
  linux-headers-"$KERNEL" \
  2>&1

# -----------------------------------------------------------------------------
log "--- Installing amneziawg-tools ---"
clone_or_pull "$AWG_TOOLS_REPO" "$AWG_TOOLS_DIR"
cd "$AWG_TOOLS_DIR/src"
make clean 2>&1
make 2>&1
make install 2>&1

command -v awg || die "awg not found after install"
command -v awg-quick || die "awg-quick not found after install"
log "amneziawg-tools installed: $(awg --version 2>/dev/null || echo 'ok')"

# -----------------------------------------------------------------------------
log "--- Building kernel module ---"

# Remove old DKMS-installed module if present (it takes priority over manual builds)
DKMS_MODULE="/lib/modules/$KERNEL/updates/dkms/amneziawg.ko"
for ext in "" ".zst" ".xz" ".gz"; do
  if [ -f "${DKMS_MODULE}${ext}" ]; then
    log "Removing old DKMS module: ${DKMS_MODULE}${ext}"
    rm -f "${DKMS_MODULE}${ext}"
  fi
done
if command -v dkms > /dev/null 2>&1 && dkms status amneziawg 2>/dev/null | grep -q .; then
  log "Removing amneziawg from DKMS..."
  dkms remove amneziawg --all 2>/dev/null || true
fi

clone_or_pull "$AWG_MODULE_REPO" "$AWG_MODULE_DIR"
cd "$AWG_MODULE_DIR/src"
make -C "/lib/modules/$KERNEL/build" M="$(pwd)" clean 2>&1
make -C "/lib/modules/$KERNEL/build" M="$(pwd)" modules 2>&1
make -C "/lib/modules/$KERNEL/build" M="$(pwd)" modules_install 2>&1
depmod -a

# -----------------------------------------------------------------------------
log "--- Loading module ---"

# Unload old modules before loading the new one
if lsmod | grep -q "^amneziawg"; then
  log "Reloading amneziawg module..."
  modprobe -r amneziawg 2>/dev/null || true
fi
if lsmod | grep -q "^wireguard"; then
  log "Unloading standard wireguard module..."
  modprobe -r wireguard 2>/dev/null || true
fi

modprobe amneziawg 2>&1 || die "Failed to load amneziawg module"
lsmod | grep -q amneziawg || die "amneziawg module not found in lsmod"
log "Module loaded successfully"

# -----------------------------------------------------------------------------
log "--- Configuring autoload ---"
echo "amneziawg" >/etc/modules-load.d/amneziawg.conf
echo "blacklist wireguard" >/etc/modprobe.d/wireguard-blacklist.conf

# -----------------------------------------------------------------------------
log "--- Configuring sysctl ---"
cat >/etc/sysctl.d/99-awg.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216

net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
sysctl -p /etc/sysctl.d/99-awg.conf 2>&1

# -----------------------------------------------------------------------------
log "=== Installation complete ==="
log "awg: $(command -v awg) $(awg --version 2>/dev/null || true)"
log "Module: $(modinfo -F version amneziawg 2>/dev/null || echo 'loaded')"
