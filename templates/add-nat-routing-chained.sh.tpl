#!/bin/bash
# Chained mode: forward peer traffic to exit-peer, no MASQUERADE on this interface.
# Table=off in [Interface] prevents awg-quick from hijacking all host traffic.
# Only FORWARDED packets (iif = awg interface) get routed back into the tunnel.

IFACE=$(ip route show default | awk '{print $5; exit}')

# Accept incoming AWG traffic
iptables -I INPUT 1 -i "$IFACE" -p udp --dport $LISTEN_PORT -j ACCEPT
iptables -I INPUT 1 -i $IF_NAME -j ACCEPT

# Enable forwarding between peers on the same interface
iptables -I FORWARD 1 -i $IF_NAME -o $IF_NAME -j ACCEPT

# Subnet route for the VPN network
ip route add $SUBNET dev $IF_NAME

# Policy routing: packets arriving on the AWG interface (from peers)
# get routed back through it (cryptokey routing picks the exit-peer).
# Locally originated traffic (SSH, etc.) has no iif — unaffected.
ip route add default dev $IF_NAME table $LISTEN_PORT
ip rule add iif $IF_NAME table $LISTEN_PORT priority 100
