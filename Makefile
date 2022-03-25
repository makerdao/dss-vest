all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean  :; dapp clean && rm -rf crytic-export corpus
test   :; make && ./test.sh $(match)
solc-select           :; pip3 install solc-select && solc-select install 0.6.12
echidna-mintable      :; ./echidna/echidna.sh mintable
echidna-suckable      :; ./echidna/echidna.sh suckable
echidna-transferrable :; ./echidna/echidna.sh transferrable
certora-mintable      :; certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12 src/DssVest.sol:DssVestMintable certora/DSToken.sol certora/MockAuthority.sol --link DssVestMintable:gem=DSToken DSToken:authority=MockAuthority --verify DssVestMintable:certora/DssVestMintable.spec --solc_args "['--optimize','--optimize-runs','200']" --rule_sanity $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
certora-suckable      :; certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12 src/DssVest.sol:DssVestSuckable certora/ChainLog.sol certora/Vat.sol certora/DaiJoin.sol certora/Dai.sol --link DssVestSuckable:chainlog=ChainLog DssVestSuckable:vat=Vat DssVestSuckable:daiJoin=DaiJoin DaiJoin:vat=Vat DaiJoin:dai=Dai --verify DssVestSuckable:certora/DssVestSuckable.spec --solc_args "['--optimize','--optimize-runs','200']" --rule_sanity  $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
certora-transferrable :; certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12 src/DssVest.sol:DssVestTransferrable certora/Dai.sol --link DssVestTransferrable:gem=Dai --verify DssVestTransferrable:certora/DssVestTransferrable.spec --solc_args "['--optimize','--optimize-runs','200']" --rule_sanity  $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
deploy-mintable       :; make && dapp create DssVestMintable $(gem)
deploy-suckable       :; make && dapp create DssVestSuckable 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F
deploy-transferrable  :; make && dapp create DssVestTransferrable $(owner) $(gem)
