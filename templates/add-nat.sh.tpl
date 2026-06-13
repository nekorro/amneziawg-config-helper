#!/bin/bash
# PostUp for $IF_NAME. Idempotent: each rule is checked (-C) before insert, so
# repeated PostUp runs (interface flaps) never accumulate duplicate rules.
# NOTE: forwarding + MASQUERADE for the VPN supernet are also persisted in
# /etc/iptables/rules.v4 by persist-forwarding.sh (reload-proof). These per-iface
# rules are a belt-and-suspenders for hosts that don't run that step.
IFACE=$(ip route show default | awk '{print $5; exit}')

ensure()     { local c="$1"; shift; iptables          -C "$c" "$@" 2>/dev/null || iptables          -I "$c" 1 "$@"; }
ensure_nat() { local c="$1"; shift; iptables -t nat -C "$c" "$@" 2>/dev/null || iptables -t nat -I "$c" 1 "$@"; }

ensure_nat POSTROUTING -s $SUBNET -o "$IFACE" -j MASQUERADE
ensure INPUT -i $IF_NAME -j ACCEPT
ensure FORWARD -i $IF_NAME -o "$IFACE" -j ACCEPT
ensure FORWARD -i "$IFACE" -o $IF_NAME -j ACCEPT
