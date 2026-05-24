#!/bin/bash
IFACE=$(ip route show default | awk '{print $5; exit}')
iptables -t nat -D POSTROUTING -s $SUBNET -o "$IFACE" -j MASQUERADE 2>/dev/null || true
iptables -D INPUT -i $IF_NAME -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $IF_NAME -o "$IFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$IFACE" -o $IF_NAME -j ACCEPT 2>/dev/null || true
