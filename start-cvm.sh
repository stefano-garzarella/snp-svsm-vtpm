#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

IMAGE="--image ${CVM_IMAGE}"

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Start QEMU Confidential VM"
    echo -e ""
    echo -e "     --image {PATH}  path to the VM disk image [default: ${CVM_IMAGE}]"
    echo -e " -h, --help          print this help"
}

while [ "$1" != "" ]; do
    case $1 in
        --image )
            shift
            IMAGE="--image $1"
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

${SCRIPT_PATH}/svsm/scripts/launch_guest.sh --qemu "${QEMU}" \
    --aproxy "${PROXY_SOCK}" \
    --state "${TPM_STATE}" \
    --monitor "${QEMU_MONITOR_PORT}" \
    ${IMAGE}
