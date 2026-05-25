#!/bin/bash
# Chained mode: remove forwarding and routing rules

IFACE=$(ip route show default | awk '{print $5; exit}')

iptables -D INPUT -i "$IFACE" -p udp --dport $LISTEN_PORT -j ACCEPT 2>/dev/null || true
iptables -D INPUT -i $IF_NAME -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $IF_NAME -o $IF_NAME -j ACCEPT 2>/dev/null || true

ip rule del iif $IF_NAME table $LISTEN_PORT priority 100 2>/dev/null || true
ip route del default dev $IF_NAME table $LISTEN_PORT 2>/dev/null || true
ip route del $SUBNET dev $IF_NAME 2>/dev/null || true
