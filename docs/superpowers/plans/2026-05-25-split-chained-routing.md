# Split-Chained Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable selective routing in chained mode — specific IPs exit via exit node (.2), everything else MASQUERADEs on the intermediate node (.1), controlled by files in a routes directory.

**Architecture:** The PostUp helper script dynamically reads `*.txt` files from `/etc/amnezia/amneziawg/routes/<if_name>/`. If CIDRs are found, it creates an ipset, marks matching packets via iptables mangle, and routes them to the exit peer via policy routing — while MASQUERADEing everything else. If the directory is empty, it falls back to the current full-chain behavior (all traffic to exit peer).

**Tech Stack:** Bash, iptables, ipset, ip rule/route, envsubst

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `templates/add-nat-chained.sh.tpl` | Unified PostUp: reads routes dir, decides split vs full-chain |
| Create | `templates/remove-nat-chained.sh.tpl` | Unified PostDown: cleans up ipset, iptables, routes |
| Delete | `templates/add-nat-routing-chained.sh.tpl` | Replaced by unified template |
| Delete | `templates/remove-nat-routing-chained.sh.tpl` | Replaced by unified template |
| Modify | `interface.sh:274-284` | Create routes dir, use new templates, update printed instructions |
| Modify | `interface.sh:114-139` | Clean up routes dir on --remove |
| Modify | `install.sh:22-31` | Add ipset to apt-get install list |
| Create | `routes/example.txt` | Documented template with format explanation |
| Create | `routes/youtube.txt` | YouTube/Google Video IP ranges |
| Create | `routes/discord.txt` | Discord IP ranges |
| Create | `routes/cloudflare.txt` | Cloudflare IP ranges |

---

### Task 1: Add ipset to install.sh

**Files:**
- Modify: `install.sh:22-31`

- [ ] **Step 1: Add ipset to the apt-get install list**

In `install.sh`, add `ipset` to the package list. Change line 30 from:

```bash
apt-get install -y \
    gcc \
	xxd \
	qrencode \
	git \
	linux-headers-$(uname -r) \
    make \
	iptables \
	iproute2 \
	2>&1
```

to:

```bash
apt-get install -y \
    gcc \
	xxd \
	qrencode \
	git \
	linux-headers-$(uname -r) \
    make \
	iptables \
	ipset \
	iproute2 \
	2>&1
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat: add ipset to install dependencies"
```

---

### Task 2: Create unified PostUp chained template

**Files:**
- Create: `templates/add-nat-chained.sh.tpl`

- [ ] **Step 1: Create the unified PostUp template**

Create `templates/add-nat-chained.sh.tpl` with the following content. Variables `$IF_NAME`, `$LISTEN_PORT`, `$SUBNET`, `$ROUTES_DIR` are substituted by envsubst at generation time. `$IFACE` is detected at runtime.

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add templates/add-nat-chained.sh.tpl
git commit -m "feat: unified chained PostUp template with split/full logic"
```

---

### Task 3: Create unified PostDown chained template

**Files:**
- Create: `templates/remove-nat-chained.sh.tpl`

- [ ] **Step 1: Create the unified PostDown template**

Create `templates/remove-nat-chained.sh.tpl`:

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add templates/remove-nat-chained.sh.tpl
git commit -m "feat: unified chained PostDown template"
```

---

### Task 4: Update interface.sh chained path

**Files:**
- Modify: `interface.sh:274-284` (NAT helper generation)
- Modify: `interface.sh:114-139` (--remove cleanup)
- Modify: `interface.sh:303-358` (chained setup output)

- [ ] **Step 1: Update NAT helper generation to use new templates**

In `interface.sh`, replace lines 274-278:

```bash
if [ "$CHAINED" -eq 1 ]; then
  EXIT_PEER_IP="${SUBNET_BASE%.*}.2"
  export EXIT_PEER_IP
  envsubst '$IF_NAME $LISTEN_PORT $SUBNET' <"$SCRIPT_DIR"/templates/add-nat-routing-chained.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst '$IF_NAME $LISTEN_PORT $SUBNET' <"$SCRIPT_DIR"/templates/remove-nat-routing-chained.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
```

with:

```bash
if [ "$CHAINED" -eq 1 ]; then
  EXIT_PEER_IP="${SUBNET_BASE%.*}.2"
  export EXIT_PEER_IP
  ROUTES_DIR="$PATH_BASE/routes/$IF_NAME"
  export ROUTES_DIR
  mkdir -p "$ROUTES_DIR"
  envsubst '$IF_NAME $LISTEN_PORT $SUBNET $ROUTES_DIR' <"$SCRIPT_DIR"/templates/add-nat-chained.sh.tpl >"$PATH_HELPERS"/add-nat.sh
  envsubst '$IF_NAME $LISTEN_PORT $SUBNET $ROUTES_DIR' <"$SCRIPT_DIR"/templates/remove-nat-chained.sh.tpl >"$PATH_HELPERS"/remove-nat.sh
```

- [ ] **Step 2: Add routes directory cleanup to --remove action**

In the `--remove` section (around line 135), add cleanup of the routes directory. After the line `rm -rf "$PATH_BASE/helpers/$IF_NAME"`, add:

```bash
  rm -rf "$PATH_BASE/routes/$IF_NAME"
```

- [ ] **Step 3: Update the chained setup instructions printed after creation**

In the chained output section (around lines 323-339), replace the existing printf block with one that also explains the routes directory:

```bash
  printf "\n"
  printf "=== Chained mode setup ===\n"
  printf "Exit-peer IP: %s\n" "$EXIT_PEER_IP"
  printf "Exit-node files saved to %s/\n\n" "$EXIT_NODE_DIR"
  printf "On the exit node host, clone this repo and run:\n\n"
  printf "  sudo ./interface.sh --add-exit \\\\\n"
  printf "    --name %s \\\\\n" "$EXIT_IF_NAME"
  printf "    --private-key %s \\\\\n" "$EXIT_KEY"
  printf "    --address %s \\\\\n" "$EXIT_PEER_IP"
  printf "    --subnet %s \\\\\n" "$SUBNET"
  printf "    --endpoint %s:%s \\\\\n" "$ENDPOINT_HOST" "$LISTEN_PORT"
  printf "    --peer-pub %s \\\\\n" "$PUBLIC_KEY"
  printf "    --psk %s \\\\\n" "$EXIT_PSK"
  printf "    --jc %s --jmin 40 --jmax 70 \\\\\n" "$AWG_JC"
  printf "    --s1 %s --s2 %s --s3 %s --s4 %s \\\\\n" "$AWG_S1" "$AWG_S2" "$AWG_S3" "$AWG_S4"
  printf "    --h1 %s --h2 %s --h3 %s --h4 %s\n" "$AWG_H1" "$AWG_H2" "$AWG_H3" "$AWG_H4"
  printf "\n=== Routing ===\n"
  printf "Routes directory: %s\n" "$ROUTES_DIR"
  printf "  Empty (default)  → all traffic exits via exit node (.2)\n"
  printf "  With *.txt files → matching IPs exit via exit node, rest via this host (.1)\n"
  printf "  Format: one CIDR per line, # for comments\n"
  printf "  Example presets in repo: routes/youtube.txt, routes/discord.txt\n"
  printf "  Copy presets: cp routes/youtube.txt %s/\n" "$ROUTES_DIR"
  printf "  Apply changes: awg-quick down %s && awg-quick up %s\n" "$IF_NAME" "$IF_NAME"
```

- [ ] **Step 4: Commit**

```bash
git add interface.sh
git commit -m "feat: interface.sh uses unified chained templates, creates routes dir"
```

---

### Task 5: Delete old chained templates

**Files:**
- Delete: `templates/add-nat-routing-chained.sh.tpl`
- Delete: `templates/remove-nat-routing-chained.sh.tpl`

- [ ] **Step 1: Delete the old templates**

```bash
rm templates/add-nat-routing-chained.sh.tpl templates/remove-nat-routing-chained.sh.tpl
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: delete old chained templates replaced by unified versions"
```

---

### Task 6: Create route preset files

**Files:**
- Create: `routes/example.txt`
- Create: `routes/youtube.txt`
- Create: `routes/discord.txt`
- Create: `routes/cloudflare.txt`

- [ ] **Step 1: Create example.txt with format documentation**

Create `routes/example.txt`:

```
# Route preset file for AmneziaWG split-chained mode
#
# Place *.txt files in /etc/amnezia/amneziawg/routes/<interface_name>/
# to route matching destinations through the exit node.
# All other traffic exits via MASQUERADE on the intermediate host.
#
# Format:
#   - One CIDR per line (e.g. 203.0.113.0/24)
#   - Single IPs are treated as /32 (e.g. 8.8.8.8)
#   - Lines starting with # are comments
#   - Blank lines are ignored
#
# Apply changes by restarting the interface:
#   awg-quick down <name> && awg-quick up <name>
#
# Example:
# 203.0.113.0/24
# 198.51.100.0/24
# 8.8.8.8
```

- [ ] **Step 2: Create youtube.txt**

Create `routes/youtube.txt`:

```
# YouTube / Google Video
# Source: Google AS15169 major prefixes
142.250.0.0/15
172.217.0.0/16
216.58.192.0/19
172.253.0.0/16
74.125.0.0/16
173.194.0.0/16
209.85.128.0/17
108.177.0.0/17
64.233.160.0/19
```

- [ ] **Step 3: Create discord.txt**

Create `routes/discord.txt`:

```
# Discord
# Source: Discord AS62041
162.159.128.0/17
66.22.196.0/22
35.214.0.0/16
```

- [ ] **Step 4: Create cloudflare.txt**

Create `routes/cloudflare.txt`:

```
# Cloudflare CDN
# Source: https://www.cloudflare.com/ips/
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
104.16.0.0/13
104.24.0.0/14
108.162.192.0/18
131.0.72.0/22
141.101.64.0/18
162.158.0.0/15
172.64.0.0/13
173.245.48.0/20
188.114.96.0/20
190.93.240.0/20
197.234.240.0/22
198.41.128.0/17
```

- [ ] **Step 5: Commit**

```bash
git add routes/
git commit -m "feat: add route preset files for split-chained mode"
```

---

### Task 7: Update help text and README

**Files:**
- Modify: `interface.sh:8-50` (show_help function)
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update interface.sh help text**

In the `show_help()` function, update the `--chained` description from:

```
  --chained   Forward traffic to exit-peer .2 instead of MASQUERADE
```

to:

```
  --chained   Forward traffic to exit-peer .2. By default all traffic goes
              to exit node. Place CIDR lists (*.txt) in the routes directory
              to selectively route only matching IPs via exit node;
              the rest exits via MASQUERADE on this host.
              Routes dir: /etc/amnezia/amneziawg/routes/<name>/
```

- [ ] **Step 2: Update README.md chained mode section**

Add a new subsection "Split-chained (selective routing)" after the existing "How it works" section in README.md. Add the following after the "Peers have no internet access until the exit node connects." line:

```markdown
### Split-chained (selective routing)

By default, chained mode routes all traffic through the exit node. To route only specific destinations through the exit node and exit everything else on the intermediate host:

1. Place `*.txt` files with CIDRs into the routes directory:

```bash
# Copy a preset
sudo cp routes/youtube.txt /etc/amnezia/amneziawg/routes/awg0/

# Or create your own
sudo tee /etc/amnezia/amneziawg/routes/awg0/custom.txt <<EOF
# Custom routes via exit node
203.0.113.0/24
198.51.100.0/24
EOF
```

2. Restart the interface:

```bash
sudo awg-quick down awg0 && sudo awg-quick up awg0
```

To switch back to full-chain (all traffic via exit node), remove all files from the routes directory and restart.

Preset route files for common services are shipped in the `routes/` directory of this repo.
```

- [ ] **Step 3: Update CLAUDE.md**

In the templates list in CLAUDE.md, replace the two chained template entries:

```
  - `add-nat-routing-chained.sh.tpl` / `remove-nat-routing-chained.sh.tpl` — Chained mode forwarding rules
```

with:

```
  - `add-nat-chained.sh.tpl` / `remove-nat-chained.sh.tpl` — Chained mode: dynamic split/full routing via ipset
```

Add to Key Details:

```
- Chained routes dir: `/etc/amnezia/amneziawg/routes/<if_name>/` — empty = full-chain, with *.txt CIDRs = split-chain
- Split-chained uses ipset + iptables MARK + fwmark policy routing
```

- [ ] **Step 4: Commit**

```bash
git add interface.sh README.md CLAUDE.md
git commit -m "docs: update help, README, CLAUDE.md for split-chained routing"
```

---

### Task 8: Final verification

- [ ] **Step 1: Verify all template references are consistent**

Run:
```bash
grep -r 'add-nat-routing-chained\|remove-nat-routing-chained' *.sh templates/
```
Expected: no output (old template names should be gone).

Run:
```bash
grep -r 'add-nat-chained\|remove-nat-chained' *.sh templates/
```
Expected: references in `interface.sh` only.

- [ ] **Step 2: Verify file listing matches spec**

Run:
```bash
ls templates/*.tpl
```
Expected:
```
templates/add-nat-chained.sh.tpl
templates/add-nat.sh.tpl
templates/interface.conf.tpl
templates/peer-client.conf.tpl
templates/peer-exit.part.tpl
templates/peer.part.tpl
templates/remove-nat-chained.sh.tpl
templates/remove-nat.sh.tpl
```

Run:
```bash
ls routes/
```
Expected:
```
cloudflare.txt
discord.txt
example.txt
youtube.txt
```

- [ ] **Step 3: Verify envsubst variable list includes ROUTES_DIR**

Run:
```bash
grep 'envsubst.*add-nat-chained' interface.sh
```
Expected: `envsubst '$IF_NAME $LISTEN_PORT $SUBNET $ROUTES_DIR'`

- [ ] **Step 4: Push**

```bash
git push origin split
```
