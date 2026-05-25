#!/bin/bash
# peer.sh — manage AmneziaWG peers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH_BASE="/etc/amnezia/amneziawg"

show_help() {
  cat <<'HELP'
Usage:
  sudo ./peer.sh --add    --interface <name> [--peer <name>]
  sudo ./peer.sh --remove --interface <name> --peer <name>
  sudo ./peer.sh --help

Actions:
  --add       Add a new peer to an existing interface
  --remove    Remove a peer from interface config and delete peer files
  --help      Show this help

Parameters:
  --interface  Interface name to add/remove peer from
  --peer       Peer name (optional for --add, auto-generated as "peer_<IP>")

Examples:
  sudo ./peer.sh --add --interface awg0
  sudo ./peer.sh --add --interface awg0 --peer phone
  sudo ./peer.sh --remove --interface awg0 --peer phone
HELP
}

# Extract a value from the interface config
config_get() {
  echo "$IF_CONFIG" | grep "^$1 = " | awk '{print $3}'
}

# --- Parse arguments ---
ACTION=""
IF_NAME=""
PEER_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --add)       ACTION="add" ;;
    --remove)    ACTION="remove" ;;
    --help|-h)   show_help; exit 0 ;;
    --interface) IF_NAME="$2"; shift ;;
    --peer)      PEER_NAME="$2"; shift ;;
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

if [ -z "$IF_NAME" ]; then
  echo "Error: --interface is required"
  show_help
  exit 1
fi

PATH_IF_CONFIG="$PATH_BASE/$IF_NAME.conf"
if ! [ -f "$PATH_IF_CONFIG" ]; then
  echo "Interface $IF_NAME config not found."
  exit 1
fi

PEERS_DIR="$SCRIPT_DIR/clients/$IF_NAME"

# --- Remove peer ---
if [ "$ACTION" = "remove" ]; then
  if [ -z "$PEER_NAME" ]; then
    echo "Error: --peer is required for --remove"
    exit 1
  fi

  PEER_CONF="$PEERS_DIR/${PEER_NAME}.conf"
  if ! [ -f "$PEER_CONF" ]; then
    echo "Peer config $PEER_CONF not found."
    exit 1
  fi

  PEER_PRIV=$(grep "^PrivateKey = " "$PEER_CONF" | awk '{print $3}')
  PEER_PUB_DERIVED=$(echo "$PEER_PRIV" | awg pubkey)

  # Remove [Peer] block matching this PublicKey
  awk -v pub="$PEER_PUB_DERIVED" '
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
    block != "" && /^[A-Za-z#]/ {
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
  ' "$PATH_IF_CONFIG" > "$PATH_IF_CONFIG.tmp"
  mv "$PATH_IF_CONFIG.tmp" "$PATH_IF_CONFIG"

  rm -f "$PEER_CONF"
  printf "Peer %s removed from interface %s.\n" "$PEER_NAME" "$IF_NAME"

  if awg show "$IF_NAME" > /dev/null 2>&1; then
    printf "Restarting interface %s\n" "$IF_NAME"
    awg-quick down "$IF_NAME"
    awg-quick up "$IF_NAME"
  fi
  exit 0
fi

# --- Add peer ---
IF_CONFIG=$(<"$PATH_IF_CONFIG")

umask 077
PRIVATE_KEY=$(awg genkey)
PRESHARED_KEY=$(awg genpsk)
PEER_PUB=$(echo "$PRIVATE_KEY" | awg pubkey)

# Find next available IP; skip peers with AllowedIPs = 0.0.0.0/0 (exit-peer in chained mode)
MAX_USED_HOST=1
while IFS= read -r line; do
  [ -z "$line" ] && continue
  IP_FIELD=$(echo "$line" | awk '{print $3}' | cut -d "/" -f 1)
  if [[ "$IP_FIELD" == "0.0.0.0" ]]; then
    if ((MAX_USED_HOST < 2)); then MAX_USED_HOST=2; fi
    continue
  fi
  PEER_HOST=$(echo "$IP_FIELD" | cut -d "." -f 4)
  if ((PEER_HOST > MAX_USED_HOST)); then
    MAX_USED_HOST=$PEER_HOST
  fi
done <<< "$(echo "$IF_CONFIG" | grep "AllowedIPs = ")"
NEXT_HOST=$((MAX_USED_HOST + 1))

if ((NEXT_HOST > 254)); then
  echo "Subnet capacity reached."
  exit 1
fi

INTERFACE_ADDRESS=$(config_get "Address")
SUBNET_PREFIX=${INTERFACE_ADDRESS%.*}
ADDRESS="$SUBNET_PREFIX.$NEXT_HOST"
PUBLIC_KEY=$(<"$PATH_BASE/$IF_NAME.pub")
ENDPOINT_HOST=$(wget -q -O - --timeout=10 ipinfo.io/ip) || { echo "ERROR: could not detect public IP"; exit 1; }
LISTEN_PORT=$(config_get "ListenPort")
ENDPOINT="$ENDPOINT_HOST:$LISTEN_PORT"

if [ -z "$PEER_NAME" ]; then
  PEER_NAME="peer_${ADDRESS}"
fi

export PRESHARED_KEY
export PEER_PUB
export PEER_IP="$ADDRESS"

envsubst <"$SCRIPT_DIR"/templates/peer.part.tpl >>"$PATH_IF_CONFIG"

export PRIVATE_KEY
export ADDRESS
export PUBLIC_KEY
export ENDPOINT
export SUBNET="${SUBNET_PREFIX}.0/24"
export AWG_JC=$(config_get "Jc")
export AWG_JMIN=$(config_get "Jmin")
export AWG_JMAX=$(config_get "Jmax")
export AWG_S1=$(config_get "S1")
export AWG_S2=$(config_get "S2")
export AWG_S3=$(config_get "S3")
export AWG_S4=$(config_get "S4")
export AWG_H1=$(config_get "H1")
export AWG_H2=$(config_get "H2")
export AWG_H3=$(config_get "H3")
export AWG_H4=$(config_get "H4")

PEER_CONF="$PEERS_DIR/${PEER_NAME}.conf"
mkdir -p "$PEERS_DIR"
envsubst <"$SCRIPT_DIR"/templates/peer-client.conf.tpl >"$PEER_CONF"

if awg show "$IF_NAME" > /dev/null 2>&1; then
  printf "Restarting interface %s\n" "$IF_NAME"
  awg-quick down "$IF_NAME"
  awg-quick up "$IF_NAME"
fi

printf "\nPeer config:\n"
printf "##############\n\n"
cat "$PEER_CONF"
printf "\n##############\n\n"
qrencode -t ANSI256UTF8 <"$PEER_CONF"
