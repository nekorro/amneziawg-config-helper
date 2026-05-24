# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell scripts for provisioning AmneziaWG (censorship-resistant WireGuard fork) server and client configurations on Debian/Ubuntu. All scripts require root (`sudo`). Target platform is Linux only.

## Key Commands

```bash
# Install amneziawg tools, kernel module, and configure OS (Debian/Ubuntu)
sudo ./install.sh

# Server management (all params by name)
sudo ./server.sh --add --name wg0 --subnet 10.8.1.0 --port 12345
sudo ./server.sh --add --name wg1 --subnet 10.8.2.0 --port 12346 --chained
sudo ./server.sh --remove --name wg0

# Client management (all params by name)
sudo ./client.sh --add --server wg0
sudo ./client.sh --add --server wg0 --client phone
sudo ./client.sh --remove --server wg0 --client phone

# Manage servers directly
awg-quick up <server_name>
awg-quick down <server_name>
```

## Architecture

- **`install.sh`** — Installs amneziawg-tools and kernel module from source, configures sysctl (IP forwarding, BBR), blacklists standard wireguard module, sets up module autoload.
- **`server.sh`** — `--add`: generates server keypair, random AWG obfuscation parameters (Jc, S1, S2, H1-H4), creates server config and NAT helper scripts via `envsubst` from templates. `--remove`: stops server, deletes config/keys/helpers/client configs. `--chained`: forwards traffic to exit-peer .2 instead of MASQUERADE.
- **`client.sh`** — `--add`: generates client keypair + preshared key, finds next available IP, appends peer block, generates client config with QR code. `--remove`: removes peer block from server config, deletes client config file. Client configs saved to `./clients/<server_name>/`.
- **`templates/`** — `envsubst`-compatible templates using `$VAR` syntax:
  - `server.conf.tpl` — Server interface config with AWG obfuscation params
  - `client.conf.tpl` — Client config with split-tunnel AllowedIPs (excludes RFC1918 ranges)
  - `client-exit.conf.tpl` — Exit-node client config for chained mode
  - `peer.part.tpl` — Peer block appended to server config for each new client
  - `peer-exit.part.tpl` — Exit-peer block for chained mode
  - `add-nat.sh.tpl` / `remove-nat.sh.tpl` — Shared MASQUERADE NAT rules (runtime IFACE detection)
  - `add-nat-routing-chained.sh.tpl` / `remove-nat-routing-chained.sh.tpl` — Chained mode forwarding rules

## Key Details

- Config base path: `/etc/amnezia/amneziawg/`
- NAT helper scripts go to `/etc/amnezia/amneziawg/helpers/<server_name>/`
- Server subnet must be `10.x.x.x` or `192.168.x.x`; port range `1025-32767`
- Server name max 30 chars (WireGuard interface name limit)
- Client IP allocation is sequential (finds max host number in existing peers, increments by 1), limited to /24 subnet (max 254 clients)
- Templates use `envsubst` for variable substitution — variables must be exported before calling envsubst
- Shared NAT templates use explicit var list (`envsubst '$VPN_IF $SUBNET'`) to avoid baking runtime vars
- `install.sh` logs are bilingual (Russian descriptions)
