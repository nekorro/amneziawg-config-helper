#!/bin/bash
IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -I POSTROUTING 1 -s $SUBNET -o "$IFACE" -j MASQUERADE
iptables -I INPUT 1 -i $IF_NAME -j ACCEPT
iptables -I FORWARD 1 -i $IF_NAME -o "$IFACE" -j ACCEPT
iptables -I FORWARD 1 -i "$IFACE" -o $IF_NAME -j ACCEPT
