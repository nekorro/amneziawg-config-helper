#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Allow forwarding
echo "net.ipv4.ip_forward = 1" >/etc/sysctl.d/00-amnezia.conf
# Add deb-src source
cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
cat /etc/apt/sources.list.d/ubuntu.sources.bak | grep -v "^#" | sed "s/^Types: deb$/Types: deb-src/" >>/etc/apt/sources.list.d/ubuntu.sources
#apt update -y && apt upgrade -y
# Install awg
#add-apt-repository -y ppa:amnezia/ppa && apt install -y amneziawg
#apt install xxd
