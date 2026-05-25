#!/bin/bash
# Chained mode PostDown — cleans up both split and full-chain rules.

IFACE=$(ip route show default | awk '{print $5; exit}')
IPSET_NAME="${IF_NAME}_exit"

iptables -D INPUT -i "$IFACE" -p udp --dport $LISTEN_PORT -j ACCEPT 2>/dev/null || true
iptables -D INPUT -i $IF_NAME -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $IF_NAME -o $IF_NAME -j ACCEPT 2>/dev/null || true

# Split-chained cleanup (no-op if not in split mode)
iptables -t mangle -D PREROUTING -i $IF_NAME -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 0x1 2>/dev/null || true
iptables -t nat -D POSTROUTING -s $SUBNET -o "$IFACE" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i $IF_NAME -o "$IFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$IFACE" -o $IF_NAME -j ACCEPT 2>/dev/null || true
ipset destroy "$IPSET_NAME" 2>/dev/null || true

# Shared cleanup
ip rule del fwmark 0x1 table $LISTEN_PORT priority 100 2>/dev/null || true
ip rule del iif $IF_NAME table $LISTEN_PORT priority 100 2>/dev/null || true
ip route del default dev $IF_NAME table $LISTEN_PORT 2>/dev/null || true
ip route del $SUBNET dev $IF_NAME 2>/dev/null || true
