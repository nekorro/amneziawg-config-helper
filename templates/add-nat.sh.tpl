#!/bin/bash
IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -I POSTROUTING 1 -s $SUBNET -o "$IFACE" -j MASQUERADE
iptables -I INPUT 1 -i $VPN_IF -j ACCEPT
iptables -I FORWARD 1 -i $VPN_IF -o "$IFACE" -j ACCEPT
iptables -I FORWARD 1 -i "$IFACE" -o $VPN_IF -j ACCEPT
