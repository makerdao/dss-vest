all    :; DAPP_SOLC_OPTIMIZE=true DAPP_SOLC_OPTIMIZE_RUNS=200 SOLC_FLAGS="--optimize --optimize-runs=200" dapp --use solc:0.6.11 build
clean  :; dapp clean
test   :; ./test.sh
deploy :; DAPP_SOLC_OPTIMIZE=true DAPP_SOLC_OPTIMIZE_RUNS=200 SOLC_FLAGS="--optimize --optimize-runs=200" dapp --use solc:0.6.11 build && dapp create DssVest
