all    :; DAPP_SOLC_OPTIMIZE=true DAPP_SOLC_OPTIMIZE_RUNS=200 SOLC_FLAGS="--optimize --optimize-runs=200" dapp --use solc:0.6.11 build
clean  :; dapp clean
test   :; ./test.sh
deploy-kovan   :; DAPP_SOLC_OPTIMIZE=true DAPP_SOLC_OPTIMIZE_RUNS=200 SOLC_FLAGS="--optimize --optimize-runs=200" dapp --use solc:0.6.11 build && dapp create DssVest 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD
deploy-mainnet :; DAPP_SOLC_OPTIMIZE=true DAPP_SOLC_OPTIMIZE_RUNS=200 SOLC_FLAGS="--optimize --optimize-runs=200" dapp --use solc:0.6.11 build && dapp create DssVest 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2
