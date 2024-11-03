# amneziawg-config-helper
Scripts for creating server/client configs for amneziawg.

## How to
1. Clone repo
2. Run `sudo ./install_prereq.sh` to install dependencies and configure OS (currently working on Debian/Ubuntu only)
3. To add server run `sudo ./add_server.sh <server_name> <vpn_subnet> <server_port>`
```
sudo ./add_server.sh wg_test 10.8.1.0 12345
```
4. Keys and config will be in `/etc/amnezia/amneziawg` folder.
5. To add new client to server run `sudo ./add_client.sh <server_name>`.
```
sudo ./add_client.sh wg_test
```
6. Client config will be in current folder `./<server_name>_client_<client_ip>.conf`
7. Start your server via `awg-quick up <server_name>`. To stop run `awg-quick down <server_name>`
