#!/bin/bash
# server.sh — manage AmneziaWG server instances
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH_BASE="/etc/amnezia/amneziawg"

show_help() {
  cat <<'HELP'
Usage: sudo ./server.sh --add    --name <name> --subnet <subnet> --port <port> [--chained]
       sudo ./server.sh --remove --name <name>
       sudo ./server.sh --help

Actions:
  --add       Create a new AWG server (generates keys, config, NAT rules, starts it)
  --remove    Stop and remove server (config, keys, helpers, client configs)
  --help      Show this help

Parameters (--add):
  --name      Server/interface name (max 30 chars)
  --subnet    VPN subnet (e.g. 10.8.1.0); must be 10.x.x.x or 192.168.x.x
  --port      Listen port (1025-32767)
  --chained   Forward client traffic to exit-peer .2 instead of MASQUERADE

Parameters (--remove):
  --name      Server name to remove

Examples:
  sudo ./server.sh --add --name wg0 --subnet 10.8.1.0 --port 12345
  sudo ./server.sh --add --name wg1 --subnet 10.8.2.0 --port 12346 --chained
  sudo ./server.sh --remove --name wg0
HELP
}

# --- Parse arguments ---
ACTION=""
SERVER_NAME=""
SERVER_SUBNET=""
SERVER_PORT=""
CHAINED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --add)     ACTION="add" ;;
    --remove)  ACTION="remove" ;;
    --help|-h) show_help; exit 0 ;;
    --name)    SERVER_NAME="$2"; shift ;;
    --subnet)  SERVER_SUBNET="$2"; shift ;;
    --port)    SERVER_PORT="$2"; shift ;;
    --chained) CHAINED=1 ;;
    *) echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
  shift
done

if [ -z "$ACTION" ]; then
  echo "Error: specify --add or --remove"
  show_help
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo "Run via sudo"
  exit 1
fi
if ! awg --version > /dev/null 2>&1; then
  echo "awg not installed, run ./install.sh"
  exit 1
fi

# --- Remove server ---
if [ "$ACTION" = "remove" ]; then
  if [ -z "$SERVER_NAME" ]; then
    echo "Error: --name is required"
    exit 1
  fi

  PATH_CONFIG="$PATH_BASE/$SERVER_NAME.conf"
  if ! [ -f "$PATH_CONFIG" ]; then
    echo "Server $SERVER_NAME config not found."
    exit 1
  fi

  # Stop server if running
  if awg show "$SERVER_NAME" > /dev/null 2>&1; then
    printf "Stopping server %s\n" "$SERVER_NAME"
    awg-quick down "$SERVER_NAME"
  fi

  # Remove config, keys, helpers
  rm -f "$PATH_CONFIG"
  rm -f "$PATH_BASE/$SERVER_NAME.key"
  rm -f "$PATH_BASE/$SERVER_NAME.pub"
  rm -rf "$PATH_BASE/helpers/$SERVER_NAME"

  # Remove client configs
  rm -rf "$SCRIPT_DIR/clients/$SERVER_NAME"

  printf "Server %s removed.\n" "$SERVER_NAME"
  exit 0
fi

# --- Add server ---
if [ -z "$SERVER_NAME" ] || [ -z "$SERVER_SUBNET" ] || [ -z "$SERVER_PORT" ]; then
  echo "Error: --name, --subnet, and --port are required for --add"
  show_help
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

PATH_CONFIG="$PATH_BASE/$SERVER_NAME.conf"
PATH_KEY="$PATH_BASE/$SERVER_NAME.key"
PATH_PUB="$PATH_BASE/$SERVER_NAME.pub"
PATH_HELPERS="$PATH_BASE/helpers/$SERVER_NAME"

if [ -f "$PATH_CONFIG" ]; then
  echo "Config $PATH_CONFIG already exists."
  exit 1
fi

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
AWG_H1=$((((RANDOM << 15) | RANDOM) % 294967295 + 1000000000))
AWG_H2=$((((RANDOM << 15) | RANDOM) % 294967295 + 2000000000))
AWG_H3=$((((RANDOM << 15) | RANDOM) % 294967295 + 3000000000))
AWG_H4=$((((RANDOM << 15) | RANDOM) % 294967295 + 4000000000))

umask 077
echo -n "$SERVER_KEY" >"$PATH_KEY"
echo -n "$SERVER_PUB" >"$PATH_PUB"

export SERVER_NAME
export SERVER_PORT
export SUBNET

mkdir -p "$PATH_HELPERS"

if [ "$CHAINED" -eq 1 ]; then
  EXIT_PEER_IP="${SERVER_SUBNET%.*}.2"
  export IPT=$(command -v iptables)
  export IFACE
  export EXIT_PEER_IP
  envsubst <"$SCRIPT_DIR"/templates/add-nat-routing-chained.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst <"$SCRIPT_DIR"/templates/remove-nat-routing-chained.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
else
  export VPN_IF="$SERVER_NAME"
  envsubst '$VPN_IF $SUBNET' <"$SCRIPT_DIR"/templates/add-nat.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst '$VPN_IF $SUBNET' <"$SCRIPT_DIR"/templates/remove-nat.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
  echo 'iptables -I INPUT 1 -i "$IFACE" -p udp --dport '"$SERVER_PORT"' -j ACCEPT' >>"$PATH_HELPERS"/add-nat.sh
  echo 'iptables -D INPUT -i "$IFACE" -p udp --dport '"$SERVER_PORT"' -j ACCEPT' >>"$PATH_HELPERS"/remove-nat.sh
fi
chmod +x "$PATH_HELPERS"/add-nat.sh
chmod +x "$PATH_HELPERS"/remove-nat.sh

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

envsubst <"$SCRIPT_DIR"/templates/server.conf.tpl >"$PATH_CONFIG"

if [ "$CHAINED" -eq 1 ]; then
  sed -i '/^\[Interface\]/a Table = off' "$PATH_CONFIG"

  EXIT_KEY=$(awg genkey)
  EXIT_PUB=$(echo "$EXIT_KEY" | awg pubkey)
  EXIT_PSK=$(awg genpsk)

  export EXIT_PSK
  export EXIT_PUB
  export EXIT_PEER_IP

  envsubst <"$SCRIPT_DIR"/templates/peer-exit.part.tpl >>"$PATH_CONFIG"

  SERVER_IP_PUB=$(wget -q -O - --timeout=10 ipinfo.io/ip) || { echo "WARNING: could not detect public IP, set Endpoint manually"; SERVER_IP_PUB="YOUR_SERVER_IP"; }
  export EXIT_KEY
  export SERVER_PUB
  export SERVER_IP_PUB
  export SERVER_PORT

  EXIT_NODE_DIR="$SCRIPT_DIR/clients/${SERVER_NAME}/exit_node"
  EXIT_IF_NAME="${SERVER_NAME}-exit"
  HELPERS_PATH="/etc/amnezia/amneziawg/helpers/${EXIT_IF_NAME}"
  export EXIT_IF_NAME
  export HELPERS_PATH
  export VPN_IF="$EXIT_IF_NAME"

  mkdir -p "$EXIT_NODE_DIR"
  envsubst <"$SCRIPT_DIR"/templates/client-exit.conf.tpl >"${EXIT_NODE_DIR}/${EXIT_IF_NAME}.conf"
  envsubst '$VPN_IF $SUBNET' <"$SCRIPT_DIR"/templates/add-nat.sh.tpl >"${EXIT_NODE_DIR}/add-nat.sh"
  envsubst '$VPN_IF $SUBNET' <"$SCRIPT_DIR"/templates/remove-nat.sh.tpl >"${EXIT_NODE_DIR}/remove-nat.sh"
  chmod +x "${EXIT_NODE_DIR}/add-nat.sh" "${EXIT_NODE_DIR}/remove-nat.sh"

  printf "\nExit-node files saved to %s/\n" "$EXIT_NODE_DIR"
  printf "  config:  %s.conf\n" "$EXIT_IF_NAME"
  printf "  helpers: add-nat.sh, remove-nat.sh\n"
  printf "Exit-peer IP: %s (must connect before clients can reach internet)\n" "$EXIT_PEER_IP"
  printf "\nOn the exit node:\n"
  printf "  1. Install amneziawg\n"
  printf "  2. Copy %s.conf to /etc/amnezia/amneziawg/\n" "$EXIT_IF_NAME"
  printf "  3. mkdir -p %s && copy add-nat.sh, remove-nat.sh there\n" "$HELPERS_PATH"
  printf "  4. awg-quick up %s\n" "$EXIT_IF_NAME"
fi

printf "\nStarting server %s\n" "$SERVER_NAME"
awg-quick up "$SERVER_NAME"
