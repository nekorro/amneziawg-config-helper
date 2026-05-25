#!/bin/bash
# Chained mode PostUp — unified split/full-chain logic.
# If routes dir has *.txt files with CIDRs: split mode (ipset + MARK + MASQUERADE).
# If routes dir is empty: full-chain mode (all traffic to exit peer).

IFACE=$(ip route show default | awk '{print $5; exit}')
IPSET_NAME="${IF_NAME}_exit"

# Collect CIDRs from all *.txt files in routes directory
CIDRS=""
if [ -d "$ROUTES_DIR" ]; then
  for f in "$ROUTES_DIR"/*.txt; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      line=$(echo "$line" | sed 's/#.*//' | tr -d ' ')
      [ -z "$line" ] && continue
      # Append /32 to bare IPs
      if [[ "$line" != */* ]]; then
        line="$line/32"
      fi
      CIDRS="$CIDRS $line"
    done < "$f"
  done
fi

# Accept incoming AWG traffic
iptables -I INPUT 1 -i "$IFACE" -p udp --dport $LISTEN_PORT -j ACCEPT
iptables -I INPUT 1 -i $IF_NAME -j ACCEPT

# Enable forwarding between peers on the same interface
iptables -I FORWARD 1 -i $IF_NAME -o $IF_NAME -j ACCEPT

# VPN subnet route
ip route add $SUBNET dev $IF_NAME

if [ -n "$CIDRS" ]; then
  # === Split-chained mode ===

  # Create ipset and load CIDRs
  ipset create "$IPSET_NAME" hash:net -exist
  for cidr in $CIDRS; do
    ipset add "$IPSET_NAME" "$cidr" -exist
  done

  # Mark packets destined for exit-peer routes
  iptables -t mangle -A PREROUTING -i $IF_NAME -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 0x1

  # Policy routing: marked packets go to exit peer via AWG interface
  ip route add default dev $IF_NAME table $LISTEN_PORT
  ip rule add fwmark 0x1 table $LISTEN_PORT priority 100

  # MASQUERADE non-exit traffic (falls through to main table → phys iface)
  iptables -t nat -I POSTROUTING 1 -s $SUBNET -o "$IFACE" -j MASQUERADE
  iptables -I FORWARD 1 -i $IF_NAME -o "$IFACE" -j ACCEPT
  iptables -I FORWARD 1 -i "$IFACE" -o $IF_NAME -j ACCEPT
else
  # === Full-chained mode (current behavior) ===

  # All forwarded traffic goes to exit peer
  ip route add default dev $IF_NAME table $LISTEN_PORT
  ip rule add iif $IF_NAME table $LISTEN_PORT priority 100
fi
