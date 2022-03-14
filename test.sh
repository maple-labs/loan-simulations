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

export FOUNDRY_PROFILE=$profile

if [ -z "$test" ]; then match="[contracts/test/*.t.sol]"; else match=$test; fi

echo Using profile: $FOUNDRY_PROFILE

rm -rf out

forge test --match "$match" --rpc-url "$ETH_RPC_URL"
