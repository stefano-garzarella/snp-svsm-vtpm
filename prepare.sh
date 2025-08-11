#!/bin/bash

SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

CLEAN=0

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Initialize git submodules and build QEMU, EDK2, SVSM, etc."
    echo -e ""
    echo -e " -c, --clean         clean all previous artifacts"
    echo -e " -h, --help          print this help"
}

while [ "$1" != "" ]; do
    case $1 in
        -c | --clean )
            CLEAN=1
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

pushd "${SCRIPT_PATH}"
if [ "${CLEAN}" == "1" ]; then
    git clean -xfd
    git submodule foreach --recursive git clean -xfd
fi
git submodule sync
git submodule update --init
popd

# Based on https://github.com/coconut-svsm/svsm/blob/main/Documentation/INSTALL.md

pushd "${SCRIPT_PATH}/igvm"
make -f igvm_c/Makefile
PREFIX=${SCRIPT_PATH}/install make -f igvm_c/Makefile install
popd

pushd "${SCRIPT_PATH}/qemu"
if [ ! -d "./build" ]; then
    PKG_CONFIG_PATH=${SCRIPT_PATH}/install/lib64/pkgconfig ./configure \
        --disable-docs --disable-user --target-list=x86_64-softmmu \
        --disable-libnfs \
        --enable-igvm --extra-ldflags=-L"${SCRIPT_PATH}/install/lib64" \
        --extra-cflags=-I"${SCRIPT_PATH}/install/include"
fi
make -j"$(nproc)"
popd

pushd "${SCRIPT_PATH}/edk2"
git submodule sync
git submodule update --init
export PYTHON3_ENABLE=TRUE
export PYTHON_COMMAND=python3
make -j"$(nproc)" -C BaseTools/
{
    source ./edksetup.sh --reconfig
    build -a X64 -b DEBUG -t GCC -DTPM2_ENABLE \
        --pcd PcdUninstallMemAttrProtocol=TRUE -p OvmfPkg/OvmfPkgX64.dsc
}
popd

pushd "${SCRIPT_PATH}/ms-tpm-containerized-build"
git submodule sync
git submodule update --init
make
popd

pushd "${SCRIPT_PATH}/svsm"
git submodule sync
git submodule update --init
make utils/cbit aproxy
FW_FILE=${SCRIPT_PATH}/edk2/Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd FEATURES=vtpm,attest make
popd
