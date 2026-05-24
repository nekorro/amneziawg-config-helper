#!/bin/bash
# Chained mode: remove forwarding and routing rules

$IPT -D INPUT -i $IFACE -p udp --dport $SERVER_PORT -j ACCEPT
$IPT -D INPUT -i $SERVER_NAME -j ACCEPT
$IPT -D FORWARD -i $SERVER_NAME -o $SERVER_NAME -j ACCEPT

ip rule del iif $SERVER_NAME table $SERVER_PORT priority 100
ip route del default dev $SERVER_NAME table $SERVER_PORT
ip route del $SUBNET dev $SERVER_NAME
