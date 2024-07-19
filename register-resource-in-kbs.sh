#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Register launch measurement and the TPM state in KBS"
    echo -e ""
    echo -e " -p, --passphrase    passphrase"
    echo -e " -t, --tpm           TPM state file (NVChip) [default: ${TPM_STATE}]"
    echo -e " -h, --help          print this help"
}

RESOURCE=

while [ "$1" != "" ]; do
    case $1 in
        -p | --passphrase )
            shift
            RESOURCE="--passphrase $1"
            ;;
        -t | --tpm )
            shift
            RESOURCE="--resource $1"
            ;;
        -h | --help )
            usage
            exit
            ;;
        * )
            echo -e "\nParameter not found: $1\n"
            usage
            exit 1
    esac
    shift
done

set -ex

MEASUREMENT="$("${SCRIPT_PATH}/svsm/target/x86_64-unknown-linux-gnu/debug/igvmmeasure" \
    --check-kvm ${SCRIPT_PATH}/svsm/bin/coconut-qemu.igvm measure -b)"

pushd "${SCRIPT_PATH}/kbs/raclients"
cargo run --example=svsm-register --all-features -- --url "${KBS_URL}" \
    --reference-kbs --workload-id svsm \
    ${RESOURCE} --measurement "${MEASUREMENT}"
popd
