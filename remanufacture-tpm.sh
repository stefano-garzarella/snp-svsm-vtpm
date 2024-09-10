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

#HACK: just clear the SVSM state to re-manufacture it by SVSM
rm -f ${TPM_STATE}; truncate -s16M ${TPM_STATE}

md5sum ${TPM_STATE}
