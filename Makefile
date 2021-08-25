all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean  :; dapp clean
test   :; make && ./test.sh $(match)
deploy-suckable      :; make && dapp create DssVestSuckable 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F
deploy-mintable      :; make && dapp create DssVestMintable $(gem)
deploy-transferrable :; make && dapp create DssVestTransferrable $(owner) $(gem)
