#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]
  then echo "Run via sudo"
  exit 1
fi

# Allow forwarding
echo "net.ipv4.ip_forward = 1" >/etc/sysctl.d/00-amnezia.conf
# Add deb-src source
if [ ! -f /etc/apt/sources.list.d/ubuntu-deb-src.sources ]; then
  cat /etc/apt/sources.list.d/ubuntu.sources | grep -v "^#" | sed "s/^Types: deb$/Types: deb-src/" >/etc/apt/sources.list.d/ubuntu-deb-src.sources
fi
apt update -y
# Install awg
add-apt-repository -y ppa:amnezia/ppa && apt install -y amneziawg
apt install xxd
