#!/usr/bin/env bash
set -e

[[ "$1" ]] || { echo "Please specify the vest contract to fuzz (e.g. mintable, suckable, transferrable)"; exit 1; }

case "$1" in
         mintable)
             VEST=DssVestMintableEchidnaTest
             ;;
         suckable)
             VEST=DssVestSuckableEchidnaTest
             ;;
    transferrable)
             VEST=DssVestTransferrableEchidnaTest
             ;;
    *)       echo "Incorrect vest contract: '$1' (mintable, suckable, transferrable)"; exit 1
             ;;
esac

SOLC=~/.solc-select/artifacts/solc-0.6.12

# Check if solc-select is installed
[[ -x solc-select ]] || pip3 install solc-select

# Check if solc-0.6.12 is installed
[[ -f "$SOLC" ]] || solc-select install 0.6.12

echidna-test echidna/"$VEST".sol --contract "$VEST" --crytic-args "--solc $SOLC" --config echidna.config.yml
