#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  echo "Run via sudo"
  exit
fi

SERVER_NAME=$1
SERVER_SUBNET=$2
SERVER_PORT=$3

if [ -z "$SERVER_NAME" ] || [ -z "$SERVER_SUBNET" ] || [ -z "$SERVER_PORT" ]; then
  echo "Too few parameters. Needs server name, subnet and port to be defined."
  exit 1
fi

if ((${#SERVER_NAME} > 30)); then
  echo "Server name length must be less than 30."
  exit 1
fi

if ! [[ "$SERVER_SUBNET" =~ ^10\..*$ || "$SERVER_SUBNET" =~ ^192\.168\..*$ ]]; then
  echo "Server subnet must belong to local CIDR: 10.0.0.0-10.255.255.255 or 192.168.0.0-192.168.255.255"
  exit 1
fi

if ((SERVER_PORT <= 1024 || SERVER_PORT >= 32768)); then
  echo "Server port must be in range 1025-32767"
  exit 1
fi

PATH_BASE="/etc/amnezia/amneziawg"
PATH_CONFIG="$PATH_BASE/$SERVER_NAME.conf"
PATH_KEY="$PATH_BASE/$SERVER_NAME.key"
PATH_PUB="$PATH_BASE/$SERVER_NAME.pub"
PATH_HELPERS="$PATH_BASE/helpers/$SERVER_NAME"

if [ -f "$PATH_CONFIG" ]; then
  echo "Config $PATH_CONFIG already exists."
  exit 1
fi

IPT=$(which iptables)
IFACE=$(ip link | grep "state UP" | grep -v LOOPBACK | grep -v docker | awk '{print substr($2, 1, length($2)-1)}')
SERVER_ADDRESS=${SERVER_SUBNET%.*}.1
SUBNET=${SERVER_SUBNET%.*}.0/24

SERVER_KEY=$(awg genkey)
SERVER_PUB=$(echo "$SERVER_KEY" | awg pubkey)

AWG_JC=$((((RANDOM << 15) | RANDOM) % 5 + 5))
AWG_S1=$((((RANDOM << 15) | RANDOM) % 150 + 50))
AWG_S2=$((((RANDOM << 15) | RANDOM) % 150 + 50))
AWG_H1=$((((RANDOM << 15) | RANDOM) % 99999999 + 100000000))
AWG_H2=$((((RANDOM << 15) | RANDOM) % 99999999 + 200000000))
AWG_H3=$((((RANDOM << 15) | RANDOM) % 99999999 + 300000000))
AWG_H4=$((((RANDOM << 15) | RANDOM) % 99999999 + 400000000))

echo -n "$SERVER_KEY" >"$PATH_KEY"
echo -n "$SERVER_PUB" >"$PATH_PUB"

export IPT
export SERVER_NAME
export SERVER_PORT
export IFACE
export SUBNET

mkdir -p "$PATH_HELPERS"
envsubst <./templates/add-nat-routing.sh.tpl >"$PATH_HELPERS"/add-nat-routing.sh
envsubst <./templates/remove-nat-routing.sh.tpl >"$PATH_HELPERS"/remove-nat-routing.sh
chmod +x "$PATH_HELPERS"/add-nat-routing.sh
chmod +x "$PATH_HELPERS"/remove-nat-routing.sh

export SERVER_KEY
export SERVER_ADDRESS
export AWG_JC
export AWG_S1
export AWG_S2
export AWG_H1
export AWG_H2
export AWG_H3
export AWG_H4
export PATH_HELPERS

envsubst <./templates/server.conf.tpl >"$PATH_BASE/$SERVER_NAME.conf"
awg-quick up "$SERVER_NAME"
