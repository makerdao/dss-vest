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

SOLC=~/.nix-profile/bin/solc-0.6.12

# Check if solc-0.6.12 is installed
[[ -f "$SOLC" ]] || nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_6_12

echidna-test echidna/"$VEST".sol --contract "$VEST" --crytic-args "--solc $SOLC" --config echidna.config.yml
