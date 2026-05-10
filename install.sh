#!/bin/bash

set -euo pipefail

AWG_TOOLS_REPO="https://github.com/amnezia-vpn/amneziawg-tools.git"
AWG_MODULE_REPO="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() {
	log "ERROR: $*"
	exit 1
}

# -----------------------------------------------------------------------------
log "=== Amnezia WireGuard Install Script ==="
log "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY | cut -d= -f2)"
log "Kernel: $(uname -r)"

# -----------------------------------------------------------------------------
log "--- Обновление системы и установка зависимостей ---"
apt-get update
apt-get install -y \
	xxd \
	qrencode \
	git \
	linux-headers-$(uname -r) \
    make \
	iptables \
	iproute2 \
	2>&1
	# build-essential \
	# pkg-config \
	# libmnl-dev \
	# iproute2-doc \
	# conntrack \
	# curl \
	# wget \
	# jq \
	# net-tools \

# -----------------------------------------------------------------------------
log "--- Установка amneziawg-tools ---"

if [ -d /opt/amneziawg-tools ]; then
	log "Директория /opt/amneziawg-tools уже существует, обновляем..."
	cd /opt/amneziawg-tools
	git pull 2>&1
else
	git clone "$AWG_TOOLS_REPO" /opt/amneziawg-tools 2>&1
fi

cd /opt/amneziawg-tools/src
make clean 2>&1
make 2>&1
make install 2>&1

command -v awg || die "awg не найден после установки"
command -v awg-quick || die "awg-quick не найден после установки"
log "amneziawg-tools установлены: $(awg --version 2>/dev/null || echo 'ok')"

# -----------------------------------------------------------------------------
log "--- Установка модуля ядра amneziawg ---"

if [ -d /opt/amneziawg-linux-kernel-module ]; then
	log "Директория уже существует, обновляем..."
	cd /opt/amneziawg-linux-kernel-module
	git pull 2>&1
else
	git clone "$AWG_MODULE_REPO" /opt/amneziawg-linux-kernel-module 2>&1
fi

cd /opt/amneziawg-linux-kernel-module/src
make -C /lib/modules/$(uname -r)/build M=$(pwd) clean 2>&1
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules 2>&1
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules_install 2>&1
depmod -a

# -----------------------------------------------------------------------------
log "--- Загрузка модуля ---"

if lsmod | grep -q "^wireguard"; then
	log "Выгружаем стандартный wireguard модуль..."
	modprobe -r wireguard 2>/dev/null || true
fi

modprobe amneziawg 2>&1 || die "Не удалось загрузить модуль amneziawg"

if lsmod | grep -q amneziawg; then
	log "Модуль amneziawg загружен успешно"
else
	die "Модуль amneziawg не найден в lsmod"
fi

# -----------------------------------------------------------------------------
log "--- Настройка автозагрузки модуля ---"

echo "amneziawg" >/etc/modules-load.d/amneziawg.conf
echo "blacklist wireguard" >/etc/modprobe.d/wireguard-blacklist.conf

# -----------------------------------------------------------------------------
log "--- Настройка sysctl ---"

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
log "=== Установка завершена успешно ==="
log "awg tools: $(which awg) $(awg --version)"
log "Модуль: $(lsmod | grep amneziawg)"
