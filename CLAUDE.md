# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell scripts for provisioning AmneziaWG (censorship-resistant WireGuard fork) server and client configurations on Debian/Ubuntu. All scripts require root (`sudo`). Target platform is Linux only.

## Key Commands

```bash
# Install amneziawg tools, kernel module, and configure OS (Debian/Ubuntu)
sudo ./install.sh

# Create a new server (generates keys, config, NAT rules, and starts it)
sudo ./add_server.sh <server_name> <vpn_subnet> <server_port>
# Example: sudo ./add_server.sh wg_test 10.8.1.0 12345

# Add a client to an existing server (appends peer, restarts server, prints config + QR)
sudo ./add_client.sh <server_name>

# Manage servers
awg-quick up <server_name>
awg-quick down <server_name>
```

## Architecture

- **`install.sh`** — Installs amneziawg-tools and kernel module from source, configures sysctl (IP forwarding, BBR), blacklists standard wireguard module, sets up module autoload.
- **`add_server.sh`** — Generates server keypair, random AWG obfuscation parameters (Jc, S1, S2, H1-H4), creates server config and NAT helper scripts via `envsubst` from templates.
- **`add_client.sh`** — Generates client keypair + preshared key, finds next available IP by parsing existing peers in server config, appends peer block to server config, generates client config with QR code output. Client configs saved to `./clients/`.
- **`templates/`** — `envsubst`-compatible templates using `$VAR` syntax:
  - `server.conf.tpl` — Server interface config with AWG obfuscation params
  - `client.conf.tpl` — Client config with split-tunnel AllowedIPs (excludes RFC1918 ranges)
  - `peer.part.tpl` — Peer block appended to server config for each new client
  - `add-nat-routing.sh.tpl` / `remove-nat-routing.sh.tpl` — iptables NAT rules for PostUp/PostDown

## Key Details

- Config base path: `/etc/amnezia/amneziawg/`
- NAT helper scripts go to `/etc/amnezia/amneziawg/helpers/<server_name>/`
- Server subnet must be `10.x.x.x` or `192.168.x.x`; port range `1025-32767`
- Server name max 30 chars (WireGuard interface name limit)
- Client IP allocation is sequential (finds max host number in existing peers, increments by 1), limited to /24 subnet (max 254 clients)
- Templates use `envsubst` for variable substitution — variables must be exported before calling envsubst
- `install.sh` logs are bilingual (Russian descriptions)
