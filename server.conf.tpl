[Interface]
PrivateKey = $SERVER_KEY 
Address = $SERVER_ADDRESS/32
ListenPort = $SERVER_PORT
Jc = $AWG_JC
Jmin = 50
Jmax = 1000
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
PostUp = $PATH_HELPERS/add-nat-routing.sh
PostDown = $PATH_HELPERS/remove-nat-routing.sh

