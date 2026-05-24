#!/bin/bash
# Exit node: MASQUERADE VPN traffic to the internet

IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -I POSTROUTING 1 -s $SUBNET -o "$IFACE" -j MASQUERADE
iptables -I FORWARD 1 -i $EXIT_IF_NAME -o "$IFACE" -j ACCEPT
iptables -I FORWARD 1 -i "$IFACE" -o $EXIT_IF_NAME -j ACCEPT
