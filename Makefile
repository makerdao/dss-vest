all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean  :; dapp clean
test   :; ./test.sh $(match)
deploy-kovan-suckable   :; make && dapp create DssVestSuckable 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD $(seth --to-uint256 3170979198376458650) # 100,000,000 Dai/yr
deploy-kovan-mintable   :; make && dapp create DssVestMintable 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD $(seth --to-uint256 31709791983764)      # 1000 MKR/yr
deploy-mainnet-suckable :; make && dapp create DssVestSuckable 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2 $(seth --to-uint256 3170979198376458650) # 100,000,000 Dai/yr
deploy-mainnet-mintable :; make && dapp create DssVestMintable 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2 $(seth --to-uint256 31709791983764)      # 1000 MKR/yr
