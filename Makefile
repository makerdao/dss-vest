all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean  :; dapp clean
test   :; ./test.sh $(match)
deploy-kovan   :; make && dapp create DssVest 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD
deploy-mainnet :; make && dapp create DssVest 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2
