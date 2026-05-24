#!/bin/bash
# Chained mode: forward client traffic to exit-peer, no MASQUERADE on this server
# Table=off in [Interface] prevents awg-quick from hijacking all host traffic.
# We set up routing manually: only FORWARDED packets (iif = awg interface)
# get routed back into the tunnel for the exit-peer via cryptokey routing.

# Accept incoming AWG traffic
$IPT -I INPUT 1 -i $IFACE -p udp --dport $SERVER_PORT -j ACCEPT
$IPT -I INPUT 1 -i $SERVER_NAME -j ACCEPT

# Enable forwarding between AWG peers (client <-> exit-peer on same interface)
$IPT -I FORWARD 1 -i $SERVER_NAME -o $SERVER_NAME -j ACCEPT

# Subnet route for the VPN network
ip route add $SUBNET dev $SERVER_NAME

# Policy routing: packets arriving ON the AWG interface (from VPN clients)
# get routed back through it (cryptokey routing picks the exit-peer).
# Server's own traffic (SSH, etc.) is locally originated — has no iif — unaffected.
ip route add default dev $SERVER_NAME table $SERVER_PORT
ip rule add iif $SERVER_NAME table $SERVER_PORT priority 100
