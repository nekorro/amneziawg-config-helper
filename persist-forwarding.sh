#!/bin/bash
# persist-forwarding.sh — persist VPN forwarding + NAT for ONE subnet into rules.v4.
#
# Why this exists:
#   Cloud images (e.g. Oracle Cloud) ship /etc/iptables/rules.v4 with a blanket
#       -A FORWARD -j REJECT --reject-with icmp-host-prohibited
#   and NO *nat table. The AmneziaWG PostUp helpers add MASQUERADE + FORWARD
#   ACCEPT rules at runtime only. Any `netfilter-persistent reload`, package
#   upgrade, or reboot wipes/reorders those runtime rules and leaves forwarding
#   REJECTed — so the tunnel is up and handshakes are fine, but no internet flows
#   through the VPN. Handshakes survive because they hit INPUT (ESTABLISHED
#   accept), not FORWARD.
#
# Fix: bake this interface's subnet forwarding policy directly into rules.v4,
#   ABOVE the FORWARD REJECT, plus a *nat MASQUERADE — deterministic, reload-proof.
#
# Idempotent. No-op on hosts without /etc/iptables/rules.v4 (e.g. non-netfilter
# -persistent nodes, where FORWARD policy is ACCEPT anyway).
#
# Usage:
#   sudo ./persist-forwarding.sh --add    <subnet/cidr> [egress_iface]
#   sudo ./persist-forwarding.sh --remove <subnet/cidr> [egress_iface]
set -euo pipefail

ACTION="${1:-}"
SUBNET="${2:-}"
EGRESS="${3:-$(ip route show default | awk '{print $5; exit}')}"
R=/etc/iptables/rules.v4

if [ "$EUID" -ne 0 ]; then echo "Run via sudo"; exit 1; fi
case "$ACTION" in --add|--remove) ;; *) echo "Usage: $0 --add|--remove <subnet> [egress]"; exit 1;; esac
if [ -z "$SUBNET" ]; then echo "subnet required"; exit 1; fi
if [ ! -f "$R" ]; then
  echo "$R not present (netfilter-persistent not in use) — nothing to persist. Skipping."
  exit 0
fi
if [ "$ACTION" = "--add" ] && [ -z "$EGRESS" ]; then echo "Could not determine egress interface"; exit 1; fi

cp "$R" "$R.bak-persist-forwarding"

# Insert a *filter FORWARD rule just before the first FORWARD REJECT (fallback:
# before the first COMMIT, i.e. end of the filter table). Idempotent via grep -F.
add_forward_rule() {
  local rule="$1"
  grep -qF -- "$rule" "$R" && return 0
  awk -v rule="$rule" '
    !ins && /^-A FORWARD -j REJECT/ { print rule; ins=1 }
    { print }
    END { if (!ins) exit 3 }
  ' "$R" > "$R.tmp" 2>/dev/null
  if [ $? -eq 3 ]; then
    # no FORWARD REJECT — insert before the first COMMIT (filter table)
    awk -v rule="$rule" '
      !ins && /^COMMIT/ { print rule; ins=1 }
      { print }
    ' "$R" > "$R.tmp"
  fi
  mv "$R.tmp" "$R"
}

# Ensure a *nat table exists, then add the MASQUERADE before its COMMIT.
add_nat_rule() {
  local rule="$1"
  grep -qF -- "$rule" "$R" && return 0
  if ! grep -q '^\*nat' "$R"; then
    cat >> "$R" <<NAT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
NAT
  fi
  awk -v rule="$rule" '
    /^\*nat/ { innat=1 }
    innat && /^COMMIT/ { print rule; innat=0 }
    { print }
  ' "$R" > "$R.tmp" && mv "$R.tmp" "$R"
}

# Drop any line matching a fixed prefix (used for --remove).
drop_lines() {
  local prefix="$1"
  grep -vF -- "$prefix" "$R" > "$R.tmp" && mv "$R.tmp" "$R"
}

if [ "$ACTION" = "--add" ]; then
  add_forward_rule "-A FORWARD -s $SUBNET -j ACCEPT"
  add_forward_rule "-A FORWARD -d $SUBNET -j ACCEPT"
  add_nat_rule     "-A POSTROUTING -s $SUBNET -o $EGRESS -j MASQUERADE"
else
  drop_lines "-A FORWARD -s $SUBNET -j ACCEPT"
  drop_lines "-A FORWARD -d $SUBNET -j ACCEPT"
  # remove the MASQUERADE for this subnet regardless of which egress was recorded
  grep -v -- "-A POSTROUTING -s $SUBNET -o .* -j MASQUERADE" "$R" > "$R.tmp" && mv "$R.tmp" "$R"
fi

if ! iptables-restore --test < "$R"; then
  echo "Generated rules.v4 failed validation — restoring backup."
  cp "$R.bak-persist-forwarding" "$R"
  exit 1
fi
iptables-restore < "$R"
echo "$ACTION persisted for subnet=$SUBNET egress=$EGRESS (backup: $R.bak-persist-forwarding)"
