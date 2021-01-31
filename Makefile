all    :; dapp --use solc:0.6.11 build
clean  :; dapp clean
test   :; ./tesh.sh
deploy :; dapp --use solc:0.6.11 build && dapp create DssVest
