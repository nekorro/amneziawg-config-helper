# Split-Chained Routing Design

## Summary

Extend the `--chained` mode to support selective routing: specific destination IPs exit via the exit node (.2), everything else exits via MASQUERADE on the intermediate node (.1). Controlled entirely by files in a routes directory — no new CLI arguments.

## Modes

| Mode | Condition | Traffic flow |
|---|---|---|
| Standard | No `--chained` | Peer → .1 → MASQUERADE → Internet |
| Full-chained | `--chained`, routes dir empty | Peer → .1 → .2 → Internet |
| Split-chained | `--chained`, routes dir has CIDRs | Matching IPs → .2; rest → MASQUERADE on .1 |

Full-chained and split-chained are not separate modes — the PostUp helper decides dynamically based on whether the routes directory contains CIDRs.

## Routes Directory

Path: `/etc/amnezia/amneziawg/routes/<if_name>/`

Created automatically when `--chained` is used. Starts empty (full-chain behavior).

### File format

- One CIDR per line
- Single IPs treated as /32
- Lines starting with `#` are comments
- Blank lines ignored
- All `*.txt` files in the directory are read

### Example

```
# /etc/amnezia/amneziawg/routes/awg0/youtube.txt
142.250.0.0/15
172.217.0.0/16
216.58.192.0/19
```

### Shipped presets

The repo ships a `routes/` directory with example service files:

```
routes/
  youtube.txt
  discord.txt
  cloudflare.txt
  example.txt      # documented template
```

Users copy desired files into the interface's routes directory.

### Switching modes

- Full-chain → split: copy route files into the directory, restart interface
- Split → full-chain: remove all files from the directory, restart interface
- Update routes: edit files, restart interface (`awg-quick down/up`)

## Routing Mechanics (split-chained on .1)

### Why AllowedIPs can't do selective routing

WireGuard uses AllowedIPs for both outbound routing AND inbound source filtering. If exit peer has `AllowedIPs = 203.0.113.0/24`, response packets with source IPs outside that range (e.g., CDN, redirect) are dropped. Therefore the exit peer must keep `AllowedIPs = 0.0.0.0/0`.

### Solution: ipset + iptables MARK + policy routing

Exit peer keeps `AllowedIPs = 0.0.0.0/0` and `Table = off`. Selective routing happens at the OS level.

### PostUp flow

```
1. Read all *.txt from /etc/amnezia/amneziawg/routes/<if_name>/
2. If CIDRs found (split mode):
   a. ipset create <if_name>_exit hash:net
   b. For each CIDR: ipset add <if_name>_exit <cidr>
   c. iptables -t mangle -A PREROUTING -i <if_name> -m set --match-set <if_name>_exit dst -j MARK --set-mark 0x1
   d. ip route add default dev <if_name> table <listen_port>
   e. ip rule add fwmark 0x1 table <listen_port> priority 100
   f. iptables -t nat -I POSTROUTING -s <subnet> -o <phys_iface> -j MASQUERADE
   g. iptables FORWARD: awg↔awg + awg↔phys
   h. iptables INPUT: UDP listen port + awg interface
   i. ip route add <subnet> dev <if_name>
3. If no CIDRs (full-chain mode):
   a. ip route add default dev <if_name> table <listen_port>
   b. ip rule add iif <if_name> table <listen_port> priority 100
   c. iptables FORWARD: awg↔awg
   d. iptables INPUT: UDP listen port + awg interface
   e. ip route add <subnet> dev <if_name>
```

### PostDown flow

Reverse of PostUp: destroy ipset, remove iptables rules, remove ip rules/routes. All commands use `2>/dev/null || true`.

### Packet flows

**Split-chained, matching exit route:**
```
Peer → awg0 → PREROUTING: dst matches ipset → MARK 0x1 → fwmark table → dev awg0 → cryptokey routing → exit peer (.2)
```

**Split-chained, not matching:**
```
Peer → awg0 → PREROUTING: no mark → main table → default route → phys iface → MASQUERADE → Internet
```

**Response from exit peer:**
```
Exit node → tunnel → awg0 → AllowedIPs=0.0.0.0/0 accepts → kernel routes to peer
```

## Config on .1 (unchanged from current chained)

- Exit peer: `AllowedIPs = 0.0.0.0/0`
- Interface: `Table = off`

## Exit node (.2) config

Unchanged. The exit node doesn't know or care whether the relay is split or full-chain. It MASQUERADEs everything it receives.

## Files changed

### Templates

- **Delete** `add-nat-routing-chained.sh.tpl` and `remove-nat-routing-chained.sh.tpl`
- **New** `add-nat-chained.sh.tpl` — unified PostUp helper with dynamic split/full logic
- **New** `remove-nat-chained.sh.tpl` — unified PostDown helper

### Scripts

- **`interface.sh`** — in `--chained` path: create routes directory, use new unified template, update printed instructions to explain routes directory
- **`install.sh`** — add `ipset` to apt-get install list

### New files

- `routes/youtube.txt`, `routes/discord.txt`, `routes/cloudflare.txt`, `routes/example.txt` — preset route files shipped in the repo

## Dependencies

- `ipset` package — added to `install.sh` apt-get list (standard on Debian/Ubuntu, often already installed with iptables)

## Backward compatibility

- Standard mode: untouched
- `--chained` with empty routes dir: identical behavior to current full-chained
- No new CLI arguments
- Exit node setup: unchanged
- Peer configs: unchanged
