#!/bin/bash
# Chained mode: remove forwarding and routing rules

$IPT -D INPUT -i $IFACE -p udp --dport $SERVER_PORT -j ACCEPT 2>/dev/null || true
$IPT -D INPUT -i $SERVER_NAME -j ACCEPT 2>/dev/null || true
$IPT -D FORWARD -i $SERVER_NAME -o $SERVER_NAME -j ACCEPT 2>/dev/null || true

ip rule del iif $SERVER_NAME table $SERVER_PORT priority 100 2>/dev/null || true
ip route del default dev $SERVER_NAME table $SERVER_PORT 2>/dev/null || true
ip route del $SUBNET dev $SERVER_NAME 2>/dev/null || true
