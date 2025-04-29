#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Register launch measurement and the TPM state key in KBS"
    echo -e ""
    echo -e " -p, --passphrase {PASS}   passphrase"
    echo -e " -h, --help                print this help"
}

# we are using XTS for the encryption layer with AES256
# XTS requires two AES256 keys, so 512 bits (64 bytes) in total
SECRET="$(openssl rand -hex 64)"

while [ "$1" != "" ]; do
    case $1 in
        -p | --passphrase )
            shift
            SECRET="$1"
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

echo $MEASUREMENT | xxd -r -p | base64 -w 0 > $KBS_MEASUREMENT
echo $SECRET | xxd -r -p | base64 -w 0 > $KBS_SECRET

if [ -f "$KBS_PID" ]; then
    PID=$(cat "$KBS_PID")
    rm -f "$KBS_PID"
    kill "$PID" 2>/dev/null
fi
