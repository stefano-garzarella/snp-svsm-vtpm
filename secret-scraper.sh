#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

SECRET=""
DUMP=1

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Dump QEMU VM memory and search for a secret"
    echo -e ""
    echo -e " -s, --secret        secret to scrape"
    echo -e "     --no-dump       do NOT dump the memory, use the one already dumped"
    echo -e " -h, --help          print this help"
}

while [ "$1" != "" ]; do
    case $1 in
        -s | --secret )
            shift
            SECRET=$1
            ;;
        --no-dump )
            DUMP=0
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

if [ "${DUMP}" == "1" ]; then
    echo "pmemsave 0x0 0xFFFFFFFF vm_ram.bin" | nc localhost ${QEMU_MONITOR_PORT}
fi
strings ${SCRIPT_PATH}/vm_ram.bin | grep "$SECRET"
