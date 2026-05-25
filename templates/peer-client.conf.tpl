[Interface]
PrivateKey = $PRIVATE_KEY
Address = $ADDRESS/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
S3 = $AWG_S3
S4 = $AWG_S4
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PresharedKey = $PRESHARED_KEY
PublicKey = $PUBLIC_KEY
Endpoint = $ENDPOINT
PersistentKeepalive = 60
AllowedIPs = 0.0.0.0/0
