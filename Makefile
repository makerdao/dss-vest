all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean  :; dapp clean
test   :; ./test.sh $(match)
solc   :; pip3 install solc-select && solc-select install 0.6.12
certora-mintable     :; certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12 src/DssVest.sol:DssVestMintable src/specs/DSToken.sol src/specs/MockAuthority.sol --link DssVestMintable:gem=DSToken DSToken:authority=MockAuthority --verify DssVestMintable:src/specs/DssVestMintable.spec --rule_sanity
certora-suckable     :; certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12 src/DssVest.sol:DssVestSuckable src/specs/ChainLog.sol src/specs/Vat.sol src/specs/DaiJoin.sol src/specs/Dai.sol --link DssVestSuckable:chainlog=ChainLog DssVestSuckable:vat=Vat DssVestSuckable:daiJoin=DaiJoin DaiJoin:vat=Vat DaiJoin:dai=Dai --verify DssVestSuckable:src/specs/DssVestSuckable.spec --rule_sanity
certora-transferrable :; certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12 src/DssVest.sol:DssVestTransferrable src/specs/Dai.sol --link DssVestTransferrable:gem=Dai --verify DssVestTransferrable:src/specs/DssVestTransferrable.spec --rule_sanity
deploy-kovan-suckable   :; make && dapp create DssVestSuckable 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD
deploy-kovan-mintable   :; make && dapp create DssVestMintable 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD
deploy-mainnet-suckable :; make && dapp create DssVestSuckable 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2
deploy-mainnet-mintable :; make && dapp create DssVestMintable 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2
