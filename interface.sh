#!/bin/bash
# interface.sh — manage AmneziaWG interfaces
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH_BASE="/etc/amnezia/amneziawg"

show_help() {
  cat <<'HELP'
Usage:
  sudo ./interface.sh --add      --name <name> --subnet <subnet> --port <port> [--chained]
  sudo ./interface.sh --add-exit --name <name> --private-key <key> --address <ip>
                                 --subnet <subnet> --endpoint <host:port>
                                 --peer-pub <key> --psk <key>
                                 --jc <n> --jmin <n> --jmax <n>
                                 --s1 <n> --s2 <n> --s3 <n> --s4 <n>
                                 --h1 <n> --h2 <n> --h3 <n> --h4 <n>
  sudo ./interface.sh --reload-routes --name <name>
  sudo ./interface.sh --remove   --name <name>
  sudo ./interface.sh --help

Actions:
  --add       Create a new AWG interface (generates keys, config, NAT, starts it)
  --add-exit  Create an exit-node interface from parameters (no key generation)
  --reload-routes  Reload exit routes from routes directory without restarting
  --remove    Stop and remove interface (config, keys, helpers, peer configs)
  --help      Show this help

Parameters (--add):
  --name      Interface name (max 30 chars)
  --subnet    VPN subnet base (e.g. 10.8.1.0); must be 10.x.x.x or 192.168.x.x
  --port      UDP listen port (1025-32767)
  --chained   Forward all traffic to exit-peer .2 by default.
              Place CIDR lists (*.txt) in the routes directory to route
              matching IPs directly via this host (.1) instead of exit node.
              Routes dir: /etc/amnezia/amneziawg/routes/<name>/

Parameters (--add-exit):
  --name        Interface name
  --private-key Private key for the exit-node
  --address     Exit-node IP address (e.g. 10.8.1.2)
  --subnet      VPN subnet (e.g. 10.8.1.0/24)
  --endpoint    Relay endpoint (host:port)
  --peer-pub    Relay's public key
  --psk         Preshared key
  --jc, --jmin, --jmax, --s1..s4, --h1..h4  AWG obfuscation parameters

Parameters (--remove):
  --name      Interface name to remove

Examples:
  sudo ./interface.sh --add --name awg0 --subnet 10.8.1.0 --port 12345
  sudo ./interface.sh --add --name awg1 --subnet 10.8.2.0 --port 12346 --chained
  sudo ./interface.sh --reload-routes --name awg1
  sudo ./interface.sh --remove --name awg0
HELP
}

# --- Parse arguments ---
ACTION=""
IF_NAME=""
SUBNET_BASE=""
LISTEN_PORT=""
CHAINED=0
NO_S3S4=0
PRIVATE_KEY=""
IF_ADDRESS=""
ENDPOINT=""
PEER_PUB=""
PSK=""
AWG_JC="" AWG_JMIN="" AWG_JMAX=""
AWG_S1="" AWG_S2="" AWG_S3="" AWG_S4=""
AWG_H1="" AWG_H2="" AWG_H3="" AWG_H4=""

while [ $# -gt 0 ]; do
  case "$1" in
    --add)         ACTION="add" ;;
    --add-exit)    ACTION="add-exit" ;;
    --remove)      ACTION="remove" ;;
    --reload-routes) ACTION="reload-routes" ;;
    --help|-h)     show_help; exit 0 ;;
    --name)        IF_NAME="$2"; shift ;;
    --subnet)      SUBNET_BASE="$2"; shift ;;
    --port)        LISTEN_PORT="$2"; shift ;;
    --chained)     CHAINED=1 ;;
    --no-s3s4)     NO_S3S4=1 ;;
    --private-key) PRIVATE_KEY="$2"; shift ;;
    --address)     IF_ADDRESS="$2"; shift ;;
    --endpoint)    ENDPOINT="$2"; shift ;;
    --peer-pub)    PEER_PUB="$2"; shift ;;
    --psk)         PSK="$2"; shift ;;
    --jc)          AWG_JC="$2"; shift ;;
    --jmin)        AWG_JMIN="$2"; shift ;;
    --jmax)        AWG_JMAX="$2"; shift ;;
    --s1)          AWG_S1="$2"; shift ;;
    --s2)          AWG_S2="$2"; shift ;;
    --s3)          AWG_S3="$2"; shift ;;
    --s4)          AWG_S4="$2"; shift ;;
    --h1)          AWG_H1="$2"; shift ;;
    --h2)          AWG_H2="$2"; shift ;;
    --h3)          AWG_H3="$2"; shift ;;
    --h4)          AWG_H4="$2"; shift ;;
    *) echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
  shift
done

if [ -z "$ACTION" ]; then
  echo "Error: specify --add, --add-exit, --reload-routes, or --remove"
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

# --- Reload routes ---
if [ "$ACTION" = "reload-routes" ]; then
  if [ -z "$IF_NAME" ]; then
    echo "Error: --name is required"
    exit 1
  fi

  if ! awg show "$IF_NAME" > /dev/null 2>&1; then
    echo "Interface $IF_NAME is not running."
    exit 1
  fi

  ROUTES_DIR="$PATH_BASE/routes/$IF_NAME/local"
  IPSET_NAME="${IF_NAME}_direct"

  # Collect CIDRs from routes directory
  CIDRS=""
  if [ -d "$ROUTES_DIR" ]; then
    for f in "$ROUTES_DIR"/*.txt; do
      [ -f "$f" ] || continue
      while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*//' | tr -d ' ')
        [ -z "$line" ] && continue
        if [[ "$line" != */* ]]; then
          line="$line/32"
        fi
        CIDRS="$CIDRS $line"
      done < "$f"
    done
  fi

  if [ -n "$CIDRS" ]; then
    if ipset list "$IPSET_NAME" > /dev/null 2>&1; then
      # Already in split mode — flush and reload ipset
      ipset flush "$IPSET_NAME"
    else
      # Switching from full-chain to split — need full restart
      echo "Interface is in full-chain mode. Restart to switch to split mode:"
      printf "  awg-quick down %s && awg-quick up %s\n" "$IF_NAME" "$IF_NAME"
      exit 1
    fi
    for cidr in $CIDRS; do
      ipset add "$IPSET_NAME" "$cidr" -exist
    done
    printf "Reloaded %d routes for interface %s\n" "$(echo $CIDRS | wc -w)" "$IF_NAME"
  else
    if ipset list "$IPSET_NAME" > /dev/null 2>&1; then
      echo "Routes directory is empty. Restart to switch to full-chain mode:"
      printf "  awg-quick down %s && awg-quick up %s\n" "$IF_NAME" "$IF_NAME"
      exit 1
    else
      echo "No routes to reload (already in full-chain mode)."
    fi
  fi
  exit 0
fi

# --- Remove interface ---
if [ "$ACTION" = "remove" ]; then
  if [ -z "$IF_NAME" ]; then
    echo "Error: --name is required"
    exit 1
  fi

  PATH_CONFIG="$PATH_BASE/$IF_NAME.conf"
  if ! [ -f "$PATH_CONFIG" ]; then
    echo "Interface $IF_NAME config not found."
    exit 1
  fi

  if awg show "$IF_NAME" > /dev/null 2>&1; then
    printf "Stopping interface %s\n" "$IF_NAME"
    awg-quick down "$IF_NAME"
  fi

  rm -f "$PATH_CONFIG"
  rm -f "$PATH_BASE/$IF_NAME.key"
  rm -f "$PATH_BASE/$IF_NAME.pub"
  rm -rf "$PATH_BASE/helpers/$IF_NAME"
  rm -rf "$PATH_BASE/routes/$IF_NAME"
  rm -rf "$SCRIPT_DIR/clients/$IF_NAME"

  printf "Interface %s removed.\n" "$IF_NAME"
  exit 0
fi

# --- Add exit-node interface ---
if [ "$ACTION" = "add-exit" ]; then
  if [ -z "$IF_NAME" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$IF_ADDRESS" ] || \
     [ -z "$SUBNET_BASE" ] || [ -z "$ENDPOINT" ] || [ -z "$PEER_PUB" ] || \
     [ -z "$PSK" ] || [ -z "$AWG_JC" ] || [ -z "$AWG_S1" ] || [ -z "$AWG_S2" ] || \
     [ -z "$AWG_H1" ] || [ -z "$AWG_H2" ] || [ -z "$AWG_H3" ] || [ -z "$AWG_H4" ]; then
    echo "Error: all parameters are required for --add-exit (see --help)"
    exit 1
  fi

  if ((${#IF_NAME} > 15)); then
    echo "Interface name must be 15 characters or less (Linux limit)."
    exit 1
  fi

  PATH_CONFIG="$PATH_BASE/$IF_NAME.conf"
  PATH_HELPERS="$PATH_BASE/helpers/$IF_NAME"

  if [ -f "$PATH_CONFIG" ]; then
    echo "Config $PATH_CONFIG already exists."
    exit 1
  fi

  # Derive subnet from SUBNET_BASE (strip CIDR if present)
  SUBNET_CLEAN="${SUBNET_BASE%/*}"
  SUBNET="${SUBNET_CLEAN%.*}.0/24"

  : "${AWG_JMIN:=40}"
  : "${AWG_JMAX:=70}"

  umask 077
  mkdir -p "$PATH_HELPERS"

  export IF_NAME
  export SUBNET
  envsubst '$IF_NAME $SUBNET' <"$SCRIPT_DIR"/templates/add-nat.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst '$IF_NAME $SUBNET' <"$SCRIPT_DIR"/templates/remove-nat.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
  chmod +x "$PATH_HELPERS"/add-nat.sh "$PATH_HELPERS"/remove-nat.sh

  S3S4_LINES=""
  if [ -n "$AWG_S3" ] && [ -n "$AWG_S4" ]; then
    S3S4_LINES="S3 = $AWG_S3
S4 = $AWG_S4"
  fi

  cat >"$PATH_CONFIG" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $IF_ADDRESS/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
${S3S4_LINES:+$S3S4_LINES
}H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
PostUp = $PATH_HELPERS/add-nat.sh
PostDown = $PATH_HELPERS/remove-nat.sh

[Peer]
PresharedKey = $PSK
PublicKey = $PEER_PUB
Endpoint = $ENDPOINT
PersistentKeepalive = 25
AllowedIPs = $SUBNET
EOF

  printf "Exit-node interface %s configured.\n" "$IF_NAME"
  printf "Starting interface %s\n" "$IF_NAME"
  awg-quick up "$IF_NAME"
  exit 0
fi

# --- Add interface ---
if [ -z "$IF_NAME" ] || [ -z "$SUBNET_BASE" ] || [ -z "$LISTEN_PORT" ]; then
  echo "Error: --name, --subnet, and --port are required for --add"
  show_help
  exit 1
fi

if ((${#IF_NAME} > 15)); then
  echo "Interface name must be 15 characters or less (Linux limit)."
  exit 1
fi

if ! [[ "$SUBNET_BASE" =~ ^10\..*$ || "$SUBNET_BASE" =~ ^192\.168\..*$ ]]; then
  echo "Subnet must belong to local CIDR: 10.0.0.0-10.255.255.255 or 192.168.0.0-192.168.255.255"
  exit 1
fi

if ((LISTEN_PORT <= 1024 || LISTEN_PORT >= 32768)); then
  echo "Listen port must be in range 1025-32767"
  exit 1
fi

if ss -nul | awk '{print $4}' | grep -q ":$LISTEN_PORT"; then
  echo "Port already in use, choose another port"
  exit 1
fi

PATH_CONFIG="$PATH_BASE/$IF_NAME.conf"
PATH_KEY="$PATH_BASE/$IF_NAME.key"
PATH_PUB="$PATH_BASE/$IF_NAME.pub"
PATH_HELPERS="$PATH_BASE/helpers/$IF_NAME"

if [ -f "$PATH_CONFIG" ]; then
  echo "Config $PATH_CONFIG already exists."
  exit 1
fi

IF_ADDRESS=${SUBNET_BASE%.*}.1
SUBNET=${SUBNET_BASE%.*}.0/24

PRIVATE_KEY=$(awg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | awg pubkey)

: "${AWG_JC:=$((((RANDOM << 15) | RANDOM) % 3 + 3))}"
: "${AWG_S1:=$((((RANDOM << 15) | RANDOM) % 9 + 2))}"
: "${AWG_S2:=$((((RANDOM << 15) | RANDOM) % 9 + 2))}"
if [ "$NO_S3S4" -eq 0 ]; then
  : "${AWG_S3:=$((((RANDOM << 15) | RANDOM) % 9 + 2))}"
  : "${AWG_S4:=$((((RANDOM << 15) | RANDOM) % 9 + 2))}"
fi
: "${AWG_H1:=$((((RANDOM << 15) | RANDOM) % 294967295 + 1000000000))}"
: "${AWG_H2:=$((((RANDOM << 15) | RANDOM) % 294967295 + 2000000000))}"
: "${AWG_H3:=$((((RANDOM << 15) | RANDOM) % 294967295 + 3000000000))}"
: "${AWG_H4:=$((((RANDOM << 15) | RANDOM) % 294967295 + 4000000000))}"

umask 077
echo -n "$PRIVATE_KEY" >"$PATH_KEY"
echo -n "$PUBLIC_KEY" >"$PATH_PUB"

export IF_NAME
export LISTEN_PORT
export SUBNET

mkdir -p "$PATH_HELPERS"

if [ "$CHAINED" -eq 1 ]; then
  EXIT_PEER_IP="${SUBNET_BASE%.*}.2"
  export EXIT_PEER_IP
  ROUTES_DIR="$PATH_BASE/routes/$IF_NAME/local"
  export ROUTES_DIR
  mkdir -p "$ROUTES_DIR"
  envsubst '$IF_NAME $LISTEN_PORT $SUBNET $ROUTES_DIR' <"$SCRIPT_DIR"/templates/add-nat-chained.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst '$IF_NAME $LISTEN_PORT $SUBNET $ROUTES_DIR' <"$SCRIPT_DIR"/templates/remove-nat-chained.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
else
  envsubst '$IF_NAME $SUBNET' <"$SCRIPT_DIR"/templates/add-nat.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst '$IF_NAME $SUBNET' <"$SCRIPT_DIR"/templates/remove-nat.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
  echo 'iptables -I INPUT 1 -i "$IFACE" -p udp --dport '"$LISTEN_PORT"' -j ACCEPT' >>"$PATH_HELPERS"/add-nat.sh
  echo 'iptables -D INPUT -i "$IFACE" -p udp --dport '"$LISTEN_PORT"' -j ACCEPT 2>/dev/null || true' >>"$PATH_HELPERS"/remove-nat.sh
fi
chmod +x "$PATH_HELPERS"/add-nat.sh
chmod +x "$PATH_HELPERS"/remove-nat.sh

export PRIVATE_KEY
export IF_ADDRESS
export AWG_JC
export AWG_S1
export AWG_S2
export AWG_S3
export AWG_S4
export AWG_H1
export AWG_H2
export AWG_H3
export AWG_H4
export PATH_HELPERS

envsubst <"$SCRIPT_DIR"/templates/interface.conf.tpl >"$PATH_CONFIG"
# Remove S3/S4 lines if empty (unsupported by older AWG builds)
sed -i '/^S[34] = $/d' "$PATH_CONFIG"

if [ "$CHAINED" -eq 1 ]; then
  sed -i '/^\[Interface\]/a Table = off' "$PATH_CONFIG"

  EXIT_KEY=$(awg genkey)
  EXIT_PUB=$(echo "$EXIT_KEY" | awg pubkey)
  EXIT_PSK=$(awg genpsk)

  export EXIT_PSK
  export EXIT_PUB
  export EXIT_PEER_IP

  envsubst <"$SCRIPT_DIR"/templates/peer-exit.part.tpl >>"$PATH_CONFIG"

  ENDPOINT_HOST=$(wget -q -O - --timeout=10 ipinfo.io/ip) || { echo "WARNING: could not detect public IP, set --endpoint manually"; ENDPOINT_HOST="YOUR_HOST_IP"; }

  EXIT_IF_NAME="${IF_NAME}-exit"

  EXIT_NODE_DIR="$SCRIPT_DIR/clients/${IF_NAME}/exit_node"
  mkdir -p "$EXIT_NODE_DIR"

  printf "\n"
  printf "=== Chained mode setup ===\n"
  printf "Exit-peer IP: %s\n" "$EXIT_PEER_IP"
  printf "Exit-node files saved to %s/\n\n" "$EXIT_NODE_DIR"
  printf "On the exit node host, clone this repo and run:\n\n"
  printf "  sudo ./interface.sh --add-exit \\\\\n"
  printf "    --name %s \\\\\n" "$EXIT_IF_NAME"
  printf "    --private-key %s \\\\\n" "$EXIT_KEY"
  printf "    --address %s \\\\\n" "$EXIT_PEER_IP"
  printf "    --subnet %s \\\\\n" "$SUBNET"
  printf "    --endpoint %s:%s \\\\\n" "$ENDPOINT_HOST" "$LISTEN_PORT"
  printf "    --peer-pub %s \\\\\n" "$PUBLIC_KEY"
  printf "    --psk %s \\\\\n" "$EXIT_PSK"
  printf "    --jc %s --jmin 40 --jmax 70 \\\\\n" "$AWG_JC"
  if [ -n "$AWG_S3" ] && [ -n "$AWG_S4" ]; then
    printf "    --s1 %s --s2 %s --s3 %s --s4 %s \\\\\n" "$AWG_S1" "$AWG_S2" "$AWG_S3" "$AWG_S4"
  else
    printf "    --s1 %s --s2 %s \\\\\n" "$AWG_S1" "$AWG_S2"
  fi
  printf "    --h1 %s --h2 %s --h3 %s --h4 %s\n" "$AWG_H1" "$AWG_H2" "$AWG_H3" "$AWG_H4"
  printf "\n=== Routing ===\n"
  printf "Routes directory: %s\n" "$ROUTES_DIR"
  printf "  All traffic goes through exit node (.2) by default.\n"
  printf "  Place *.txt files with CIDRs to route those IPs directly via this host (.1).\n"
  printf "  Format: one CIDR per line, # for comments\n"
  printf "  Example presets in repo: routes/youtube.txt, routes/discord.txt\n"
  printf "  Copy presets: cp routes/youtube.txt %s/\n" "$ROUTES_DIR"
  printf "  Apply: sudo ./interface.sh --reload-routes --name %s\n" "$IF_NAME"
  printf "  Or restart: awg-quick down %s && awg-quick up %s\n" "$IF_NAME" "$IF_NAME"

  # Also save the command to a file for convenience
  cat >"${EXIT_NODE_DIR}/setup-exit-node.sh" <<SETUP_EOF
#!/bin/bash
# Run this script on the exit node host (from the repo directory)
sudo ./interface.sh --add-exit \\
  --name $EXIT_IF_NAME \\
  --private-key $EXIT_KEY \\
  --address $EXIT_PEER_IP \\
  --subnet $SUBNET \\
  --endpoint $ENDPOINT_HOST:$LISTEN_PORT \\
  --peer-pub $PUBLIC_KEY \\
  --psk $EXIT_PSK \\
  --jc $AWG_JC --jmin 40 --jmax 70 \\
  --s1 $AWG_S1 --s2 $AWG_S2$([ -n "$AWG_S3" ] && echo " --s3 $AWG_S3")$([ -n "$AWG_S4" ] && echo " --s4 $AWG_S4") \\
  --h1 $AWG_H1 --h2 $AWG_H2 --h3 $AWG_H3 --h4 $AWG_H4
SETUP_EOF
  chmod +x "${EXIT_NODE_DIR}/setup-exit-node.sh"
fi

printf "\nStarting interface %s\n" "$IF_NAME"
awg-quick up "$IF_NAME"
