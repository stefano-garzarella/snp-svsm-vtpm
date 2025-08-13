#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

IMAGE="${CVM_IMAGE}"

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Start QEMU standard VM"
    echo -e ""
    echo -e "     --image {PATH}  path to the VM disk image [default: ${CVM_IMAGE}]"
    echo -e " -h, --help          print this help"
}

while [ "$1" != "" ]; do
    case $1 in
        --image )
            shift
            IMAGE="$1"
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

QEMU_VERSION=`$QEMU --version | grep -Po '(?<=version )[^ ]+'`

if [ "$EUID" -ne 0 ]; then
	SUDO_CMD="sudo"
else
	SUDO_CMD=""
fi

echo "============================="
echo "Launching no confidential guest"
echo "============================="
echo "QEMU:         ${QEMU}"
echo "QEMU Version: ${QEMU_VERSION}"
echo "IMAGE:        ${IMAGE}"
echo "============================="
echo "Press Ctrl-] to interrupt"
echo "============================="

# Store original terminal settings and restore it on exit
STTY_ORIGINAL=$(stty -g)
trap 'stty "$STTY_ORIGINAL"' EXIT

# Remap Ctrl-C to Ctrl-] to allow the guest to handle Ctrl-C.
stty intr ^]

set -ex

$SUDO_CMD \
  $QEMU \
    -machine q35,accel=kvm,memory-backend=mem0 \
    -object memory-backend-memfd,size=2G,id=mem0 \
    -smp 4 \
    -no-reboot \
    -netdev user,id=vmnic -device e1000,netdev=vmnic,romfile= \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=/usr/share/edk2/ovmf/OVMF_VARS.fd \
    -drive file=$IMAGE,if=none,id=disk0,format=qcow2,snapshot=off \
    -device virtio-scsi-pci,id=scsi0,disable-legacy=on \
    -device scsi-hd,drive=disk0,bootindex=0 \
    -nographic \
    -monitor tcp:127.0.0.1:${QEMU_MONITOR_PORT},server,nowait
