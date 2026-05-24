# AmneziaWG Config Helper

Shell scripts for provisioning [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-tools) (censorship-resistant WireGuard fork) servers and clients on Debian/Ubuntu.

## Features

- One-command server and client provisioning
- Random AWG obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1-H4) per server
- Chained mode: relay traffic through an exit node on a separate host
- Client QR codes for mobile setup
- Named parameters for all commands
- Clean removal of servers and clients

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

# 2. Create a server
sudo ./server.sh --add --name wg0 --subnet 10.8.1.0 --port 12345

# 3. Add a client
sudo ./client.sh --add --server wg0 --client phone
```

## Usage

### install.sh

Installs amneziawg-tools and kernel module from source, configures sysctl (IP forwarding, BBR, buffer sizes), blacklists the standard wireguard module, and sets up module autoload.

```bash
sudo ./install.sh
```

Idempotent — safe to re-run (pulls latest sources on subsequent runs).

### server.sh

Manage AmneziaWG server instances.

#### Add a server

```bash
sudo ./server.sh --add --name <name> --subnet <subnet> --port <port> [--chained]
```

| Parameter   | Description                                              |
|-------------|----------------------------------------------------------|
| `--name`    | Server/interface name (max 30 characters)                |
| `--subnet`  | VPN subnet base (e.g. `10.8.1.0`); must be `10.x.x.x` or `192.168.x.x` |
| `--port`    | UDP listen port (1025-32767)                             |
| `--chained` | Optional. Forward traffic to exit-peer instead of NAT    |

What it does:
- Generates server keypair and random AWG obfuscation parameters
- Creates server config at `/etc/amnezia/amneziawg/<name>.conf`
- Generates NAT helper scripts at `/etc/amnezia/amneziawg/helpers/<name>/`
- Starts the server with `awg-quick up`

```bash
# Standard mode — server NATs to internet
sudo ./server.sh --add --name wg0 --subnet 10.8.1.0 --port 12345

# Chained mode — server relays to exit node
sudo ./server.sh --add --name wg1 --subnet 10.8.2.0 --port 12346 --chained
```

#### Remove a server

```bash
sudo ./server.sh --remove --name <name>
```

Stops the server (if running) and removes:
- Server config, private key, public key
- NAT helper scripts
- All client configs in `./clients/<name>/`

### client.sh

Manage client peers on an existing server.

#### Add a client

```bash
sudo ./client.sh --add --server <name> [--client <client_name>]
```

| Parameter  | Description                                                    |
|------------|----------------------------------------------------------------|
| `--server` | Server name to add the client to                               |
| `--client` | Optional client name. Defaults to `client_<IP>` if omitted     |

What it does:
- Generates client keypair + preshared key
- Allocates the next available IP in the /24 subnet (max 254 clients)
- Appends a `[Peer]` block to the server config
- Saves client config to `./clients/<server_name>/<client_name>.conf`
- Restarts the server if it's running
- Prints the client config and QR code

```bash
sudo ./client.sh --add --server wg0 --client phone
sudo ./client.sh --add --server wg0 --client laptop
sudo ./client.sh --add --server wg0   # auto-named "client_10.8.1.3"
```

#### Remove a client

```bash
sudo ./client.sh --remove --server <name> --client <client_name>
```

Removes the client's `[Peer]` block from the server config, deletes the client config file, and restarts the server if running.

## Chained Mode

Standard mode routes client traffic directly to the internet via NAT on the server:

```
Client --> AWG Server (.1) --> MASQUERADE --> Internet
```

Chained mode forwards all client traffic to an exit node (peer `.2`) on a separate host. The server acts as a relay — no MASQUERADE, no internet access from the server itself:

```
Client --> AWG Server (.1) --> Forward --> Exit Node (.2) --> MASQUERADE --> Internet
```

### How it works

When `--chained` is passed to `server.sh --add`:

1. The server config gets a `[Peer]` block with `AllowedIPs = 0.0.0.0/0` for the exit node at `.2`
2. `Table = off` is added to prevent `awg-quick` from hijacking the server's own traffic (SSH, etc.)
3. Policy routing (`ip rule add iif <interface>`) ensures only **forwarded** VPN packets go to the exit node — the server's locally originated traffic is unaffected
4. Exit node config and helper scripts are generated in `./clients/<server_name>/exit_node/`

### Setting up the exit node

After creating a chained server, the script outputs setup instructions. In short:

```bash
# On the exit node host:
sudo ./install.sh                     # Install AmneziaWG

# Copy generated files from the server
scp -r user@server:amneziawg-config-helper/clients/<name>/exit_node/ /tmp/exit/

# Place config and helpers
sudo cp /tmp/exit/<name>-exit.conf /etc/amnezia/amneziawg/
sudo mkdir -p /etc/amnezia/amneziawg/helpers/<name>-exit/
sudo cp /tmp/exit/add-nat.sh /tmp/exit/remove-nat.sh /etc/amnezia/amneziawg/helpers/<name>-exit/

# Start
sudo awg-quick up <name>-exit
```

The exit node does MASQUERADE for VPN traffic and forwards it to the internet. Clients have no internet access until the exit node connects.

### Running multiple interfaces on one host

You can run both an exit node and a chained server on the same host. They don't interfere:

- iptables rules are scoped by interface name and subnet
- Policy routing tables use the server port as table ID (unique per server)
- MASQUERADE rules are per-subnet

## File Layout

```
.
├── install.sh              # Install AmneziaWG tools + kernel module
├── server.sh               # Server management (--add / --remove)
├── client.sh               # Client management (--add / --remove)
├── clients/                # Generated client configs
│   └── <server_name>/
│       ├── phone.conf
│       ├── laptop.conf
│       └── exit_node/      # Chained mode only
│           ├── <name>-exit.conf
│           ├── add-nat.sh
│           └── remove-nat.sh
└── templates/              # envsubst templates
    ├── server.conf.tpl
    ├── client.conf.tpl
    ├── client-exit.conf.tpl
    ├── peer.part.tpl
    ├── peer-exit.part.tpl
    ├── add-nat.sh.tpl
    ├── remove-nat.sh.tpl
    ├── add-nat-routing-chained.sh.tpl
    └── remove-nat-routing-chained.sh.tpl
```

Server configs and keys are stored in `/etc/amnezia/amneziawg/`. NAT helper scripts go to `/etc/amnezia/amneziawg/helpers/<server_name>/`.

## Managing Servers Directly

```bash
# Start/stop
sudo awg-quick up <server_name>
sudo awg-quick down <server_name>

# Show status
sudo awg show <server_name>
sudo awg show all
```

## Client Config Details

Client configs use split-tunnel AllowedIPs that exclude RFC1918 ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), so local network traffic on the client device is not routed through the VPN. DNS is set to Cloudflare (1.1.1.1, 1.0.0.1).

## License

MIT
