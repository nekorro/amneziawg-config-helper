# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell scripts for provisioning AmneziaWG (censorship-resistant WireGuard fork) interface and peer configurations on Debian/Ubuntu. All scripts require root (`sudo`). Target platform is Linux only.

## Key Commands

```bash
# Install amneziawg tools, kernel module, and configure OS (Debian/Ubuntu)
sudo ./install.sh

# Interface management (all params by name)
sudo ./interface.sh --add --name awg0 --subnet 10.8.1.0 --port 12345
sudo ./interface.sh --add --name awg1 --subnet 10.8.2.0 --port 12346 --chained
sudo ./interface.sh --add-exit --name awg1-exit --private-key <key> --address 10.8.2.2 ...
sudo ./interface.sh --remove --name awg0

# Peer management (all params by name)
sudo ./peer.sh --add --interface awg0
sudo ./peer.sh --add --interface awg0 --peer phone
sudo ./peer.sh --remove --interface awg0 --peer phone

# Manage interfaces directly
awg-quick up <name>
awg-quick down <name>
```

## Architecture

- **`install.sh`** — Installs amneziawg-tools and kernel module from source, configures sysctl (IP forwarding, BBR), blacklists standard wireguard module, sets up module autoload.
- **`interface.sh`** — `--add`: generates keypair, random AWG obfuscation parameters (Jc, S1-S4, H1-H4), creates config and NAT helper scripts. `--add-exit`: creates exit-node interface from provided params (no key generation). `--remove`: stops interface, deletes config/keys/helpers/peer configs. `--chained`: forwards traffic to exit-peer .2 instead of MASQUERADE.
- **`peer.sh`** — `--add`: generates peer keypair + preshared key, finds next available IP, appends peer block, generates peer config with QR code. `--remove`: removes peer block from interface config, deletes peer config file. Peer configs saved to `./clients/<interface_name>/`.
- **`templates/`** — `envsubst`-compatible templates using `$VAR` syntax:
  - `interface.conf.tpl` — Interface config with AWG obfuscation params
  - `peer-client.conf.tpl` — Peer config with split-tunnel AllowedIPs (excludes RFC1918 ranges)
  - `peer.part.tpl` — Peer block appended to interface config for each new peer
  - `peer-exit.part.tpl` — Exit-peer block for chained mode
  - `add-nat.sh.tpl` / `remove-nat.sh.tpl` — Shared MASQUERADE NAT rules (runtime IFACE detection)
  - `add-nat-chained.sh.tpl` / `remove-nat-chained.sh.tpl` — Chained mode: dynamic split/full routing via ipset

## Key Details

- Config base path: `/etc/amnezia/amneziawg/`
- NAT helper scripts go to `/etc/amnezia/amneziawg/helpers/<interface_name>/`
- Subnet must be `10.x.x.x` or `192.168.x.x`; port range `1025-32767`
- Interface name max 30 chars (WireGuard interface name limit)
- Peer IP allocation is sequential (finds max host number in existing peers, increments by 1), limited to /24 subnet (max 254 peers)
- AWG obfuscation params: Jc, Jmin, Jmax, S1-S4, H1-H4 — can be overridden via CLI args
- Templates use `envsubst` for variable substitution — variables must be exported before calling envsubst
- Shared NAT templates use explicit var list (`envsubst '$VPN_IF $SUBNET'`) to avoid baking runtime vars
- Chained routes dir: `/etc/amnezia/amneziawg/routes/<if_name>/` — empty = full-chain, with *.txt CIDRs = split-chain
- Split-chained uses ipset + iptables MARK + fwmark policy routing
- `install.sh` logs are bilingual (Russian descriptions)
