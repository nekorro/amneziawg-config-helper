#!/bin/bash
# client.sh — manage AmneziaWG client peers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH_BASE="/etc/amnezia/amneziawg"

show_help() {
  cat <<'HELP'
Usage: sudo ./client.sh --add    --server <name> [--client <name>]
       sudo ./client.sh --remove --server <name> --client <name>
       sudo ./client.sh --help

Actions:
  --add       Add a new client peer to an existing server
  --remove    Remove a client peer from server config and delete client files
  --help      Show this help

Parameters:
  --server    Server name to add/remove client from
  --client    Client name (optional for --add, auto-generated as "client_<IP>")

Examples:
  sudo ./client.sh --add --server wg0
  sudo ./client.sh --add --server wg0 --client phone
  sudo ./client.sh --remove --server wg0 --client phone
HELP
}

# --- Parse arguments ---
ACTION=""
SERVER_NAME=""
CLIENT_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --add)     ACTION="add" ;;
    --remove)  ACTION="remove" ;;
    --help|-h) show_help; exit 0 ;;
    --server)  SERVER_NAME="$2"; shift ;;
    --client)  CLIENT_NAME="$2"; shift ;;
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

if [ -z "$SERVER_NAME" ]; then
  echo "Error: --server is required"
  show_help
  exit 1
fi

PATH_SERVER_CONFIG="$PATH_BASE/$SERVER_NAME.conf"
if ! [ -f "$PATH_SERVER_CONFIG" ]; then
  echo "Server $SERVER_NAME config not found."
  exit 1
fi

CLIENTS_DIR="$SCRIPT_DIR/clients/$SERVER_NAME"

# --- Remove client ---
if [ "$ACTION" = "remove" ]; then
  if [ -z "$CLIENT_NAME" ]; then
    echo "Error: --client is required for --remove"
    exit 1
  fi

  CLIENT_CONF="$CLIENTS_DIR/${CLIENT_NAME}.conf"
  if ! [ -f "$CLIENT_CONF" ]; then
    echo "Client config $CLIENT_CONF not found."
    exit 1
  fi

  # Extract client's public key from the config
  CLIENT_PUB=$(grep "^PublicKey = " "$CLIENT_CONF" | head -1 | awk '{print $3}')
  if [ -z "$CLIENT_PUB" ]; then
    echo "Cannot find PublicKey in client config."
    exit 1
  fi

  # Find and extract the client's pubkey from its private key to match against server config
  CLIENT_PRIV=$(grep "^PrivateKey = " "$CLIENT_CONF" | awk '{print $3}')
  CLIENT_PUB_DERIVED=$(echo "$CLIENT_PRIV" | awg pubkey)

  # Remove [Peer] block from server config by matching PublicKey
  # The block starts with [Peer] and ends before next [Peer] or EOF
  awk -v pub="$CLIENT_PUB_DERIVED" '
    BEGIN { skip=0 }
    /^\[Peer\]/ {
      block = $0 "\n"
      skip = 0
      next
    }
    block != "" && /^PublicKey = / {
      if ($3 == pub) { skip = 1 }
      block = block $0 "\n"
      next
    }
    block != "" && /^[A-Za-z]/ {
      block = block $0 "\n"
      next
    }
    block != "" {
      if (!skip) { printf "%s", block }
      block = ""
      skip = 0
      print
      next
    }
    { print }
    END { if (block != "" && !skip) printf "%s", block }
  ' "$PATH_SERVER_CONFIG" > "$PATH_SERVER_CONFIG.tmp"
  mv "$PATH_SERVER_CONFIG.tmp" "$PATH_SERVER_CONFIG"

  rm -f "$CLIENT_CONF"
  printf "Client %s removed from server %s.\n" "$CLIENT_NAME" "$SERVER_NAME"

  # Restart server if running
  if awg show "$SERVER_NAME" > /dev/null 2>&1; then
    printf "Restarting server %s\n" "$SERVER_NAME"
    awg-quick down "$SERVER_NAME"
    awg-quick up "$SERVER_NAME"
  fi
  exit 0
fi

# --- Add client ---
SERVER_CONFIG=$(<"$PATH_SERVER_CONFIG")

umask 077
CLIENT_KEY=$(awg genkey)
PRESHARED_KEY=$(awg genpsk)
CLIENT_PUB=$(echo "$CLIENT_KEY" | awg pubkey)

# Find next available IP; skip peers with AllowedIPs = 0.0.0.0/0 (exit-peer in chained mode)
MAX_USED_HOST=1
while IFS= read -r line; do
  [ -z "$line" ] && continue
  IP_FIELD=$(echo "$line" | awk '{print $3}' | cut -d "/" -f 1)
  if [[ "$IP_FIELD" == "0.0.0.0" ]]; then
    continue
  fi
  PEER_HOST=$(echo "$IP_FIELD" | cut -d "." -f 4)
  if ((PEER_HOST > MAX_USED_HOST)); then
    MAX_USED_HOST=$PEER_HOST
  fi
done <<< "$(echo "$SERVER_CONFIG" | grep "AllowedIPs = ")"
CLIENT_HOST=$((MAX_USED_HOST + 1))

if ((CLIENT_HOST > 254)); then
  echo "Subnet capacity reached."
  exit 1
fi

SERVER_SUBNET=$(echo "$SERVER_CONFIG" | grep "Address = " | awk '{print $3}')
SUBNET_PREFIX=${SERVER_SUBNET%.*}
CLIENT_IP="$SUBNET_PREFIX.$CLIENT_HOST"
SERVER_PUB=$(<"$PATH_BASE/$SERVER_NAME.pub")
SERVER_IP_PUB=$(wget -q -O - --timeout=10 ipinfo.io/ip) || { echo "ERROR: could not detect public IP"; exit 1; }
SERVER_PORT=$(echo "$SERVER_CONFIG" | grep "ListenPort = " | awk '{print $3}')

# Auto-generate client name if not provided
if [ -z "$CLIENT_NAME" ]; then
  CLIENT_NAME="client_${CLIENT_IP}"
fi

export PRESHARED_KEY
export CLIENT_PUB
export CLIENT_IP

envsubst <"$SCRIPT_DIR"/templates/peer.part.tpl >>"$PATH_SERVER_CONFIG"

AWG_JC=$(echo "$SERVER_CONFIG" | grep "Jc = " | awk '{print $3}')
AWG_JMIN=$(echo "$SERVER_CONFIG" | grep "Jmin = " | awk '{print $3}')
AWG_JMAX=$(echo "$SERVER_CONFIG" | grep "Jmax = " | awk '{print $3}')
AWG_S1=$(echo "$SERVER_CONFIG" | grep "S1 = " | awk '{print $3}')
AWG_S2=$(echo "$SERVER_CONFIG" | grep "S2 = " | awk '{print $3}')
AWG_H1=$(echo "$SERVER_CONFIG" | grep "H1 = " | awk '{print $3}')
AWG_H2=$(echo "$SERVER_CONFIG" | grep "H2 = " | awk '{print $3}')
AWG_H3=$(echo "$SERVER_CONFIG" | grep "H3 = " | awk '{print $3}')
AWG_H4=$(echo "$SERVER_CONFIG" | grep "H4 = " | awk '{print $3}')

export CLIENT_KEY
export AWG_JC
export AWG_JMIN
export AWG_JMAX
export AWG_S1
export AWG_S2
export AWG_H1
export AWG_H2
export AWG_H3
export AWG_H4
export SERVER_PUB
export SERVER_IP_PUB
export SERVER_PORT
export SERVER_SUBNET

CLIENT_CONF="$CLIENTS_DIR/${CLIENT_NAME}.conf"
mkdir -p "$CLIENTS_DIR"
envsubst <"$SCRIPT_DIR"/templates/client.conf.tpl >"$CLIENT_CONF"

# Restart server if running
if awg show "$SERVER_NAME" > /dev/null 2>&1; then
  printf "Restarting server %s\n" "$SERVER_NAME"
  awg-quick down "$SERVER_NAME"
  awg-quick up "$SERVER_NAME"
fi

printf "\nClient config:\n"
printf "##############\n\n"
cat "$CLIENT_CONF"
printf "\n##############\n\n"
qrencode -t ANSI256UTF8 <"$CLIENT_CONF"
