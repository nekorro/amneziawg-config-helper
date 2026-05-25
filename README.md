# AmneziaWG Config Helper

Shell scripts for provisioning [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-tools) (censorship-resistant WireGuard fork) interfaces and peers on Debian/Ubuntu.

## Features

- One-command interface and peer provisioning
- Random AWG obfuscation parameters (Jc, Jmin, Jmax, S1-S4, H1-H4) per interface
- All parameters overridable via CLI arguments
- Chained mode: relay traffic through an exit node on a separate host
- Exit-node setup via `--add-exit` — no manual file copying
- Peer QR codes for mobile setup
- Clean removal of interfaces and peers

## Requirements

- Debian/Ubuntu with root access
- Kernel headers for the running kernel (`linux-headers-$(uname -r)`)

All other dependencies (gcc, make, git, iptables, qrencode, etc.) are installed by `install.sh`.

## Quick Start

```bash
git clone https://github.com/nekorro/amneziawg-config-helper.git
cd amneziawg-config-helper

# 1. Install AmneziaWG tools and kernel module
sudo ./install.sh

# 2. Create an interface
sudo ./interface.sh --add --name awg0 --subnet 10.8.1.0 --port 12345

# 3. Add a peer
sudo ./peer.sh --add --interface awg0 --peer phone
```

## Usage

### install.sh

Installs amneziawg-tools and kernel module from source, configures sysctl (IP forwarding, BBR, buffer sizes), blacklists the standard wireguard module, and sets up module autoload.

```bash
sudo ./install.sh
```

Idempotent — safe to re-run (pulls latest sources on subsequent runs).

### interface.sh

Manage AmneziaWG interfaces.

#### Add an interface

```bash
sudo ./interface.sh --add --name <name> --subnet <subnet> --port <port> [--chained]
```

| Parameter   | Description                                              |
|-------------|----------------------------------------------------------|
| `--name`    | Interface name (max 30 characters)                       |
| `--subnet`  | VPN subnet base (e.g. `10.8.1.0`); must be `10.x.x.x` or `192.168.x.x` |
| `--port`    | UDP listen port (1025-32767)                             |
| `--chained` | Optional. Forward traffic to exit-peer instead of NAT    |

Optional AWG parameter overrides (random by default):

| Parameter             | Description                          |
|-----------------------|--------------------------------------|
| `--jc`, `--jmin`, `--jmax` | Junk packet count, min/max size |
| `--s1`, `--s2`, `--s3`, `--s4` | Init packet paddings          |
| `--h1`, `--h2`, `--h3`, `--h4` | Header obfuscation seeds      |

What it does:
- Generates keypair and random AWG obfuscation parameters (overridable via CLI)
- Creates config at `/etc/amnezia/amneziawg/<name>.conf`
- Generates NAT helper scripts at `/etc/amnezia/amneziawg/helpers/<name>/`
- Starts the interface with `awg-quick up`

```bash
# Standard mode — interface NATs to internet
sudo ./interface.sh --add --name awg0 --subnet 10.8.1.0 --port 12345

# Chained mode — interface relays to exit node
sudo ./interface.sh --add --name awg1 --subnet 10.8.2.0 --port 12346 --chained

# With custom AWG parameters
sudo ./interface.sh --add --name awg0 --subnet 10.8.1.0 --port 12345 \
  --jc 4 --s1 5 --s2 3 --s3 7 --s4 2
```

#### Add an exit-node interface

```bash
sudo ./interface.sh --add-exit --name <name> --private-key <key> --address <ip> \
  --subnet <subnet> --endpoint <host:port> --peer-pub <key> --psk <key> \
  --jc <n> --jmin <n> --jmax <n> --s1 <n> --s2 <n> --s3 <n> --s4 <n> \
  --h1 <n> --h2 <n> --h3 <n> --h4 <n>
```

Creates an exit-node interface from the provided parameters (no key generation). All AWG obfuscation parameters must match the relay interface.

When you create a chained interface, the script prints the exact `--add-exit` command to run on the exit node host — just copy and paste it.

#### Reload exit routes

```bash
sudo ./interface.sh --reload-routes --name <name>
```

Hot-reloads the direct routes ipset from `/etc/amnezia/amneziawg/routes/<name>/local/` without restarting the interface or disconnecting peers. Only works when already in split-chained mode; switching between full-chain and split modes requires an interface restart.

#### Remove an interface

```bash
sudo ./interface.sh --remove --name <name>
```

Stops the interface (if running) and removes:
- Config, private key, public key
- NAT helper scripts
- All peer configs in `./clients/<name>/`

### peer.sh

Manage peers on an existing interface.

#### Add a peer

```bash
sudo ./peer.sh --add --interface <name> [--peer <peer_name>]
```

| Parameter     | Description                                              |
|---------------|----------------------------------------------------------|
| `--interface` | Interface name to add the peer to                        |
| `--peer`      | Optional peer name. Defaults to `peer_<IP>` if omitted   |

What it does:
- Generates peer keypair + preshared key
- Allocates the next available IP in the /24 subnet (max 254 peers)
- Appends a `[Peer]` block to the interface config
- Saves peer config to `./clients/<interface_name>/<peer_name>.conf`
- Restarts the interface if it's running
- Prints the peer config and QR code

```bash
sudo ./peer.sh --add --interface awg0 --peer phone
sudo ./peer.sh --add --interface awg0 --peer laptop
sudo ./peer.sh --add --interface awg0   # auto-named "peer_10.8.1.3"
```

#### Remove a peer

```bash
sudo ./peer.sh --remove --interface <name> --peer <peer_name>
```

Removes the peer's `[Peer]` block from the interface config, deletes the peer config file, and restarts the interface if running.

## Chained Mode

Standard mode routes peer traffic directly to the internet via NAT:

```
Peer --> AWG Interface (.1) --> MASQUERADE --> Internet
```

Chained mode forwards all peer traffic to an exit node (`.2`) on a separate host. The interface acts as a relay — no MASQUERADE:

```
Peer --> AWG Interface (.1) --> Forward --> Exit Node (.2) --> MASQUERADE --> Internet
```

### How it works

When `--chained` is passed to `interface.sh --add`:

1. The config gets a `[Peer]` block with `AllowedIPs = 0.0.0.0/0` for the exit node at `.2`
2. `Table = off` prevents `awg-quick` from hijacking the host's own traffic (SSH, etc.)
3. Policy routing (`ip rule add iif <interface>`) ensures only **forwarded** VPN packets go to the exit node — locally originated traffic is unaffected
4. The script prints the exact `./interface.sh --add-exit` command to run on the exit node

### Setting up the exit node

After creating a chained interface, the script prints the full command. On the exit node host:

```bash
# 1. Clone the repo and install AmneziaWG
git clone https://github.com/nekorro/amneziawg-config-helper.git
cd amneziawg-config-helper
sudo ./install.sh

# 2. Run the printed command (example):
sudo ./interface.sh --add-exit \
  --name awg1-exit \
  --private-key <key> \
  --address 10.8.2.2 \
  --subnet 10.8.2.0/24 \
  --endpoint 203.0.113.1:12346 \
  --peer-pub <key> \
  --psk <key> \
  --jc 4 --jmin 40 --jmax 70 \
  --s1 5 --s2 3 --s3 7 --s4 2 \
  --h1 1234567890 --h2 2345678901 --h3 3456789012 --h4 4000000001
```

A convenience script is also saved to `./clients/<name>/exit_node/setup-exit-node.sh`.

Peers have no internet access until the exit node connects.

### Split-chained (selective routing)

By default, chained mode routes **all** traffic through the exit node. To route specific destinations **directly** via the intermediate host (.1) instead of the exit node:

1. Place `*.txt` files with CIDRs into the routes directory:

```bash
# Copy a preset — access YouTube directly via intermediate host
sudo cp routes/youtube.txt /etc/amnezia/amneziawg/routes/awg0/local/

# Or create your own
sudo tee /etc/amnezia/amneziawg/routes/awg0/local/custom.txt <<EOF
# These IPs exit directly via intermediate host, not via exit node
203.0.113.0/24
198.51.100.0/24
EOF
```

2. Apply the routes (no peer disconnection):

```bash
sudo ./interface.sh --reload-routes --name awg0
```

Or restart the interface if switching between full-chain and split modes:

```bash
sudo awg-quick down awg0 && sudo awg-quick up awg0
```

To switch back to full-chain (all traffic via exit node), remove all files from the routes directory and restart.

Preset route files and fetch scripts are shipped in the `routes/` directory of this repo.

#### Fetching routes from iplist.opencck.org

The `fetch-iplist.opencck.sh` script downloads IP ranges for service groups from [iplist.opencck.org](https://github.com/rekryt/iplist):

```bash
# All Russian services (default: groups vk, russia, yandex)
sudo ./routes/fetch-iplist.opencck.sh > /etc/amnezia/amneziawg/routes/awg0/local/ru-services.txt

# Specific groups
sudo ./routes/fetch-iplist.opencck.sh --group vk --group yandex > /etc/amnezia/amneziawg/routes/awg0/local/vk-yandex.txt

# Global instance (blocked services)
sudo ./routes/fetch-iplist.opencck.sh --base-url https://iplist.opencck.org --group youtube \
  > /etc/amnezia/amneziawg/routes/awg0/local/youtube.txt

# Apply
sudo ./interface.sh --reload-routes --name awg0
```

#### Fetching routes by country

The `fetch-country.sh` script downloads all IP ranges for a country from the 5 regional internet registries:

```bash
sudo ./routes/fetch-country.sh RU > /etc/amnezia/amneziawg/routes/awg0/local/ru.txt
sudo ./interface.sh --reload-routes --name awg0
```

> **Warning:** Country-level lists can contain 8000+ prefixes, which significantly slows down interface startup and increases RAM usage (ipset is loaded into kernel memory). Prefer `fetch-iplist.opencck.sh` or manually crafted lists with only the services you need. Use `fetch-country.sh` only if you specifically need the entire country's IP space.

### Running multiple interfaces on one host

You can run both an exit node and a chained interface on the same host. They don't interfere:

- iptables rules are scoped by interface name and subnet
- Policy routing tables use the listen port as table ID (unique per interface)
- MASQUERADE rules are per-subnet

## File Layout

```
.
├── install.sh              # Install AmneziaWG tools + kernel module
├── interface.sh            # Interface management (--add / --add-exit / --remove)
├── peer.sh                 # Peer management (--add / --remove)
├── clients/                # Generated peer configs
│   └── <interface_name>/
│       ├── phone.conf
│       ├── laptop.conf
│       └── exit_node/      # Chained mode only
│           └── setup-exit-node.sh
├── routes/                 # Route presets and fetch scripts
│   ├── example.txt
│   ├── youtube.txt
│   ├── discord.txt
│   ├── cloudflare.txt
│   ├── fetch-iplist.opencck.sh  # Fetch IPs by service group
│   └── fetch-country.sh         # Fetch IPs by country code
└── templates/              # envsubst templates
    ├── interface.conf.tpl
    ├── peer-client.conf.tpl
    ├── peer.part.tpl
    ├── peer-exit.part.tpl
    ├── add-nat.sh.tpl
    ├── remove-nat.sh.tpl
    ├── add-nat-chained.sh.tpl
    ...
    └── remove-nat-chained.sh.tpl
```

Configs and keys are stored in `/etc/amnezia/amneziawg/`. NAT helper scripts go to `/etc/amnezia/amneziawg/helpers/<interface_name>/`.

## Managing Interfaces Directly

```bash
# Start/stop
sudo awg-quick up <name>
sudo awg-quick down <name>

# Show status
sudo awg show <name>
sudo awg show all
```

## Peer Config Details

Peer configs use split-tunnel AllowedIPs that exclude RFC1918 ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), so local network traffic on the peer device is not routed through the VPN. DNS is set to Cloudflare (1.1.1.1, 1.0.0.1).

## License

MIT
