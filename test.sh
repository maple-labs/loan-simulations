#!/usr/bin/env bash
set -e

while getopts t:r:p:m: flag
do
    case "${flag}" in
        t) test=${OPTARG};;
        r) runs=${OPTARG};;
        p) profile=${OPTARG};;
        m) match=${OPTARG};;
    esac
done

if [ -z "$profile" ]; then profile="default"; fi

export FOUNDRY_PROFILE=$profile

if [ -z "$test" ]; then match="[contracts/test/*.t.sol]"; else match=$test; fi

echo Using profile: $FOUNDRY_PROFILE

export DAPP_FORK_BLOCK=14341118  # TODO: Investigate why this isn't working in toml

forge test --match "$match" --rpc-url "$ETH_RPC_URL"
