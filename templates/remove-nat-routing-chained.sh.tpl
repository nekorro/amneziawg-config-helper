#!/bin/bash
# Chained mode: remove forwarding rules

$IPT -D INPUT -i $IFACE -p udp --dport $SERVER_PORT -j ACCEPT
$IPT -D INPUT -i $SERVER_NAME -j ACCEPT
$IPT -D FORWARD -i $SERVER_NAME -o $SERVER_NAME -j ACCEPT
$IPT -D FORWARD -i $IFACE -o $SERVER_NAME -j ACCEPT
$IPT -D FORWARD -i $SERVER_NAME -o $IFACE -j ACCEPT
