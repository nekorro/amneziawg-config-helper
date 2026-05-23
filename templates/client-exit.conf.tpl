[Interface]
PrivateKey = $EXIT_KEY
Address = $EXIT_PEER_IP/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420
Jc = $AWG_JC
Jmin = 40
Jmax = 70
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PresharedKey = $EXIT_PSK
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP_PUB:$SERVER_PORT
PersistentKeepalive = 25
AllowedIPs = $SUBNET
