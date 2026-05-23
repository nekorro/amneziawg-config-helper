#!/bin/bash
# add_server.sh
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run via sudo"
  exit 1
fi
if ! awg --version > /dev/null 2>&1; then
  echo "awg not installed, run ./install-prereq.sh"
  exit 1
fi

# Parse --chained flag
CHAINED=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --chained) CHAINED=1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
set -- "${POSITIONAL[@]}"

SERVER_NAME=${1:-}
SERVER_SUBNET=${2:-}
SERVER_PORT=${3:-}

if [ -z "$SERVER_NAME" ] || [ -z "$SERVER_SUBNET" ] || [ -z "$SERVER_PORT" ]; then
  echo "Usage: $0 [--chained] <server_name> <vpn_subnet> <server_port>"
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

if ss -nul | awk '{print $4}' | grep -q ":$SERVER_PORT"; then
  echo "Server port already in use, choose another port"
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

IPT=$(command -v iptables)
IFACE=$(ip route show default | awk '{print $5; exit}')
if [ -z "$IFACE" ]; then
  echo "Cannot detect default network interface"
  exit 1
fi

SERVER_ADDRESS=${SERVER_SUBNET%.*}.1
SUBNET=${SERVER_SUBNET%.*}.0/24

SERVER_KEY=$(awg genkey)
SERVER_PUB=$(echo "$SERVER_KEY" | awg pubkey)

AWG_JC=$((((RANDOM << 15) | RANDOM) % 3 + 3))
AWG_S1=$((((RANDOM << 15) | RANDOM) % 9 + 2))
AWG_S2=$((((RANDOM << 15) | RANDOM) % 9 + 2))
AWG_H1=$((((RANDOM << 15) | RANDOM) % 999999999 + 1000000000))
AWG_H2=$((((RANDOM << 15) | RANDOM) % 999999999 + 2000000000))
AWG_H3=$((((RANDOM << 15) | RANDOM) % 999999999 + 3000000000))
AWG_H4=$((((RANDOM << 15) | RANDOM) % 999999999 + 4000000000))

umask 077
echo -n "$SERVER_KEY" >"$PATH_KEY"
echo -n "$SERVER_PUB" >"$PATH_PUB"

export IPT
export SERVER_NAME
export SERVER_PORT
export IFACE
export SUBNET

mkdir -p "$PATH_HELPERS"

if [ "$CHAINED" -eq 1 ]; then
  EXIT_PEER_IP="${SERVER_SUBNET%.*}.2"
  export EXIT_PEER_IP
  envsubst <./templates/add-nat-routing-chained.sh.tpl >"$PATH_HELPERS"/add-nat-routing.sh
  envsubst <./templates/remove-nat-routing-chained.sh.tpl >"$PATH_HELPERS"/remove-nat-routing.sh
else
  envsubst <./templates/add-nat-routing.sh.tpl >"$PATH_HELPERS"/add-nat-routing.sh
  envsubst <./templates/remove-nat-routing.sh.tpl >"$PATH_HELPERS"/remove-nat-routing.sh
fi
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

envsubst <./templates/server.conf.tpl >"$PATH_CONFIG"

# If chained, generate exit-peer and append [Peer] block to server config
if [ "$CHAINED" -eq 1 ]; then
  EXIT_KEY=$(awg genkey)
  EXIT_PUB=$(echo "$EXIT_KEY" | awg pubkey)
  EXIT_PSK=$(awg genpsk)

  export EXIT_PSK
  export EXIT_PUB
  export EXIT_PEER_IP

  # Append exit-peer to server config
  envsubst <./templates/peer-exit.part.tpl >>"$PATH_CONFIG"

  # Generate exit-peer client config
  SERVER_IP_PUB=$(wget -q -O - --timeout=10 ipinfo.io/ip) || { echo "WARNING: could not detect public IP, set Endpoint manually"; SERVER_IP_PUB="YOUR_SERVER_IP"; }
  export EXIT_KEY
  export SERVER_PUB
  export SERVER_IP_PUB
  export SERVER_PORT

  mkdir -p ./clients
  envsubst <./templates/client-exit.conf.tpl >"./clients/${SERVER_NAME}_exit_node.conf"

  printf "\nExit-peer config saved to ./clients/%s_exit_node.conf\n" "$SERVER_NAME"
  printf "Exit-peer IP: %s (must connect before clients can reach internet)\n" "$EXIT_PEER_IP"
fi

printf "\nStarting server %s\n" "$SERVER_NAME"
awg-quick up "$SERVER_NAME"
