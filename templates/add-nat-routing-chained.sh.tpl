#!/bin/bash
# Chained mode: forward client traffic to exit-peer .2, no MASQUERADE on this server

# Accept incoming AWG traffic
$IPT -I INPUT 1 -i $IFACE -p udp --dport $SERVER_PORT -j ACCEPT
$IPT -I INPUT 1 -i $SERVER_NAME -j ACCEPT

# Enable forwarding between AWG peers (client <-> exit-peer)
$IPT -I FORWARD 1 -i $SERVER_NAME -o $SERVER_NAME -j ACCEPT

# Accept incoming on external iface for exit-peer (if exit-peer does MASQUERADE and replies come back)
$IPT -I FORWARD 1 -i $IFACE -o $SERVER_NAME -j ACCEPT
$IPT -I FORWARD 1 -i $SERVER_NAME -o $IFACE -j ACCEPT

# Route all client traffic (except exit-peer itself) to exit-peer via DNAT is not needed:
# AWG routing handles it — exit-peer has AllowedIPs=0.0.0.0/0 in server config,
# so kernel routes non-local packets to exit-peer through the AWG tunnel.
# Exit-peer must NAT/MASQUERADE on its end to forward to internet.
