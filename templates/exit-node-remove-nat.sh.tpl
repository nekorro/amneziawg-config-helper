#!/bin/bash
# Exit node: remove MASQUERADE rules

IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -D POSTROUTING -s $SUBNET -o "$IFACE" -j MASQUERADE
iptables -D FORWARD -i $EXIT_IF_NAME -o "$IFACE" -j ACCEPT
iptables -D FORWARD -i "$IFACE" -o $EXIT_IF_NAME -j ACCEPT
