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
PEER_KEY=$(awg genkey)
PRESHARED_KEY=$(awg genpsk)
PEER_PUB=$(echo "$PEER_KEY" | awg pubkey)

# Find next available IP; skip peers with AllowedIPs = 0.0.0.0/0 (exit-peer in chained mode)
MAX_USED_HOST=1
while IFS= read -r line; do
  [ -z "$line" ] && continue
  IP_FIELD=$(echo "$line" | awk '{print $3}' | cut -d "/" -f 1)
  if [[ "$IP_FIELD" == "0.0.0.0" ]]; then
    # Exit-peer in chained mode occupies .2
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

IF_SUBNET=$(echo "$IF_CONFIG" | grep "Address = " | awk '{print $3}')
SUBNET_PREFIX=${IF_SUBNET%.*}
PEER_IP="$SUBNET_PREFIX.$NEXT_HOST"
IF_PUB=$(<"$PATH_BASE/$IF_NAME.pub")
ENDPOINT_HOST=$(wget -q -O - --timeout=10 ipinfo.io/ip) || { echo "ERROR: could not detect public IP"; exit 1; }
LISTEN_PORT=$(echo "$IF_CONFIG" | grep "ListenPort = " | awk '{print $3}')

if [ -z "$PEER_NAME" ]; then
  PEER_NAME="peer_${PEER_IP}"
fi

export PRESHARED_KEY
export PEER_PUB
export PEER_IP

envsubst <"$SCRIPT_DIR"/templates/peer.part.tpl >>"$PATH_IF_CONFIG"

AWG_JC=$(echo "$IF_CONFIG" | grep "^Jc = " | awk '{print $3}')
AWG_JMIN=$(echo "$IF_CONFIG" | grep "^Jmin = " | awk '{print $3}')
AWG_JMAX=$(echo "$IF_CONFIG" | grep "^Jmax = " | awk '{print $3}')
AWG_S1=$(echo "$IF_CONFIG" | grep "^S1 = " | awk '{print $3}')
AWG_S2=$(echo "$IF_CONFIG" | grep "^S2 = " | awk '{print $3}')
AWG_S3=$(echo "$IF_CONFIG" | grep "^S3 = " | awk '{print $3}')
AWG_S4=$(echo "$IF_CONFIG" | grep "^S4 = " | awk '{print $3}')
AWG_H1=$(echo "$IF_CONFIG" | grep "^H1 = " | awk '{print $3}')
AWG_H2=$(echo "$IF_CONFIG" | grep "^H2 = " | awk '{print $3}')
AWG_H3=$(echo "$IF_CONFIG" | grep "^H3 = " | awk '{print $3}')
AWG_H4=$(echo "$IF_CONFIG" | grep "^H4 = " | awk '{print $3}')

export PEER_KEY
export AWG_JC
export AWG_JMIN
export AWG_JMAX
export AWG_S1
export AWG_S2
export AWG_S3
export AWG_S4
export AWG_H1
export AWG_H2
export AWG_H3
export AWG_H4
export IF_PUB
export ENDPOINT_HOST
export LISTEN_PORT
export IF_SUBNET

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
