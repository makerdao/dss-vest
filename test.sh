#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(cast chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            match)           MATCH="$VALUE" ;;
            match-test)      MATCH_TEST="$VALUE" ;;
            match-contract)  MATCH_CONTRACT="$VALUE" ;;
            block)           BLOCK="$VALUE" ;;
            *)
    esac
done

export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200
export FOUNDRY_SOLC=0.6.12

if [[ -z "$MATCH" && -z "$BLOCK" && -z "$MATCH_TEST" && -z "$MATCH_CONTRACT" ]]; then
    forge test --fork-url "$ETH_RPC_URL" -vvv
elif [[ -z "$MATCH" && -z "$MATCH_TEST" && -z "$MATCH_CONTRACT" ]]; then
    forge test --fork-url "$ETH_RPC_URL" --fork-block-number "$BLOCK" -vvv
else
    if [[ -n "$BLOCK" ]]; then
        if [[ -n "$MATCH" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match "$MATCH" --fork-block-number "$BLOCK" -vvvv
        elif [[ -n "$MATCH_TEST" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match-test "$MATCH_TEST" --fork-block-number "$BLOCK" -vvvv
        else
            forge test --fork-url "$ETH_RPC_URL" --match-contract "$MATCH_CONTRACT" --fork-block-number "$BLOCK" -vvvv
        fi
    else
        if [[ -n "$MATCH" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match "$MATCH" -vvvv
        elif [[ -n "$MATCH_TEST" ]]; then
            forge test --fork-url "$ETH_RPC_URL" --match-test "$MATCH_TEST" -vvvv
        else
            forge test --fork-url "$ETH_RPC_URL" --match-contract "$MATCH_CONTRACT" -vvvv
        fi
    fi
fi
