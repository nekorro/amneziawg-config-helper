#!/bin/bash
IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -D POSTROUTING -s $SUBNET -o "$IFACE" -j MASQUERADE
iptables -D INPUT -i $VPN_IF -j ACCEPT
iptables -D FORWARD -i $VPN_IF -o "$IFACE" -j ACCEPT
iptables -D FORWARD -i "$IFACE" -o $VPN_IF -j ACCEPT
