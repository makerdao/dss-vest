PATH := ~/.solc-select/artifacts/solc-0.6.12:~/.solc-select/artifacts/solc-0.5.12:~/.solc-select/artifacts:$(PATH)
all                   :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.12 build
clean                 :; dapp clean && rm -rf crytic-export corpus
test                  :; ./test.sh match="$(match)" block="$(block)" match-test="$(match-test)" match-contract="$(match-contract)"
solc-select           :; pip3 install solc-select && solc-select install 0.6.12
echidna-mintable      :; ./echidna/echidna.sh mintable
echidna-suckable      :; ./echidna/echidna.sh suckable
echidna-transferrable :; ./echidna/echidna.sh transferrable
certora-mintable      :; PATH=${PATH} certoraRun certora/DssVestMintable.conf $(if $(rule), --rule $(rule),)
certora-suckable      :; PATH=${PATH} certoraRun certora/DssVestSuckable.conf $(if $(rule), --rule $(rule),)
certora-transferrable :; $(if $(CERTORAKEY),, @echo "set certora key"; exit 1;) certoraRun --solc ~/.solc-select/artifacts/solc-0.6.12/solc-0.6.12 src/DssVest.sol:DssVestTransferrable certora/Dai.sol --link DssVestTransferrable:gem=Dai --verify DssVestTransferrable:certora/DssVestTransferrable.spec --solc_args "['--optimize','--optimize-runs','200']" --rule_sanity  $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
deploy-mintable       :; make && dapp create DssVestMintable $(gem)
deploy-suckable       :; make && dapp create DssVestSuckable 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F
deploy-transferrable  :; make && dapp create DssVestTransferrable $(owner) $(gem)
