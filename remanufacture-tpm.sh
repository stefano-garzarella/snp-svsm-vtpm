#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "(Re)manufacture the MS TPM simulator"
    echo -e ""
    echo -e " -h, --help          print this help"
}

while [ "$1" != "" ]; do
    case $1 in
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

[ -f "${TPM_STATE}" ] && md5sum ${TPM_STATE}

#TODO: pre-fill the vTPM state in the SVSM state
#pushd "${SCRIPT_PATH}/ms-tpm-containerized-build"
#git submodule update --init
#make manufacture
#popd

# HACK: while waiting for a tool, just clear the SVSM state, and start the CVM
# without a disk, so SVSM will do the re-manufacture of the vTPM without
# starting any guest

echo "Starting a CVM without a disk to re-manufacture the vTPM"
rm -f ${TPM_STATE}; truncate -s16M ${TPM_STATE}

LOG_FILE=remanufacture-tpm.log
truncate -s0 ${LOG_FILE}

# launch_guest.sh uses stty, so let's use script to create a terminal session
script -q -f -c "${SCRIPT_PATH}/svsm/scripts/launch_guest.sh --qemu ${QEMU} \
    --proxy ${PROXY_SOCK} \
    --state ${TPM_STATE}" --log-out ${LOG_FILE} &
CVM_PID=$!

set +x
# Wait for the UEFI shell expected since there is no disk attached to the CVM
tail -f ${LOG_FILE} \
    | while IFS= read -r line; do
        #echo "$line"
        if [[ "$line" == *"UEFI Interactive Shell"* ]]; then
            kill ${CVM_PID}
            break
        fi
    done
set -x

wait

echo "vTPM re-manufactured"

md5sum ${TPM_STATE}
