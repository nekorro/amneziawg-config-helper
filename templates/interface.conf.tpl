[Interface]
PrivateKey = $PRIVATE_KEY
Address = $IF_ADDRESS/32
ListenPort = $LISTEN_PORT
Jc = $AWG_JC
Jmin = 40
Jmax = 70
S1 = $AWG_S1
S2 = $AWG_S2
S3 = $AWG_S3
S4 = $AWG_S4
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
PostUp = $PATH_HELPERS/add-nat.sh
PostDown = $PATH_HELPERS/remove-nat.sh
