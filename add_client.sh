#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Run via sudo"
  exit 1
fi

SERVER_NAME=$1

if [ -z "$SERVER_NAME" ]; then
  echo "Too few parameters. Needs server name to be defined."
  exit 1
fi

PATH_BASE="/etc/amnezia/amneziawg"
PATH_SERVER_CONFIG="$PATH_BASE/$SERVER_NAME.conf"

if ! [ -f "$PATH_SERVER_CONFIG" ]; then
  echo "Server $SERVER_NAME config not found."
  exit 1
fi

SERVER_CONFIG=$(cat "$PATH_SERVER_CONFIG")

CLIENT_KEY=$(awg genkey)
PRESHARED_KEY=$(awg genpsk)
CLIENT_PUB=$(echo "$CLIENT_KEY" | awg pubkey)

PEER_IPS=$(echo "$SERVER_CONFIG" | grep "AllowedIPs = ")
MAX_USED_HOST=1
while IFS= read -r line; do
  PEER_HOST=$(echo "$line" | awk '{print $3}' | cut -d "/" -f 1 | cut -d "." -f 4)
  if ((PEER_HOST > MAX_USED_HOST)); then
    MAX_USED_HOST=$PEER_HOST
  fi
done <<<"$PEER_IPS"
CLIENT_HOST=$((MAX_USED_HOST + 1))

if ((CLIENT_HOST > 254)); then
  echo "Subnet capacity reached."
  exit 1
fi

SERVER_SUBNET=$(echo "$SERVER_CONFIG" | grep "Address = " | awk '{print $3}')
SUBNET_PREFIX=${SERVER_SUBNET%.*}
CLIENT_IP="$SUBNET_PREFIX.$CLIENT_HOST"
SERVER_PUB=$(cat "$PATH_BASE"/"$SERVER_NAME".pub)
SERVER_IP_PUB=$(wget -q -O - ipinfo.io/ip)
SERVER_PORT=$(echo "$SERVER_CONFIG" | grep "ListenPort = " | awk '{print $3}')

export PRESHARED_KEY
export CLIENT_PUB
export CLIENT_IP

envsubst <./templates/peer.part.tpl >> "$PATH_SERVER_CONFIG"

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

mkdir -p ./clients
envsubst <./templates/client.conf.tpl > ./clients/"$SERVER_NAME"_client_"$CLIENT_IP".conf
awg | grep -q "^interface: $SERVER_NAME$" && printf "Restarting server $SERVER_NAME\n" && awg-quick down "$SERVER_NAME" && awg-quick up "$SERVER_NAME"

printf "\nClient config:"
printf "\n##############\n\n"
cat ./clients/"$SERVER_NAME"_client_"$CLIENT_IP".conf
printf "\n##############\n\n"
cat ./clients/"$SERVER_NAME"_client_"$CLIENT_IP".conf | qrencode -t ANSI256UTF8
