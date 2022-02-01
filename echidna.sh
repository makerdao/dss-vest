#!/usr/bin/env bash
set -e

[[ "$1" ]] || { echo "Please specify the vest contract to fuzz (e.g. mintable, suckable, transferrable)"; exit 1; }

SOLC=~/.solc-select/artifacts/solc-0.6.12

# Check if solc-select is installed
[[ -x solc-select ]] || pip3 install solc-select

# Check if solc-0.6.12 is installed
[[ -f "$SOLC" ]] || solc-select install 0.6.12

# Run Echidna
case "$1" in
            mintable)
                echidna-test echidna/DssVestMintableEchidnaTest.sol --contract DssVestMintableEchidnaTest --crytic-args "--solc $SOLC" --config echidna.config.yml
                ;;
            suckable)
                echidna-test echidna/DssVestSuckableEchidnaTest.sol --contract DssVestSuckableEchidnaTest --crytic-args "--solc $SOLC" --config echidna.config.yml
                ;;
    transferrable)
                echidna-test echidna/DssVestTransferrableEchidnaTest.sol --contract DssVestTransferrableEchidnaTest --crytic-args "--solc $SOLC" --config echidna.config.yml
                ;;
    *)
esac
