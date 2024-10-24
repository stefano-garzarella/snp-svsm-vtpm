#!/bin/bash
SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

LUKS_KS="${SCRIPT_PATH}/images/luks.ks"

function usage
{
    echo -e "usage: $0 [OPTION...]"
    echo -e ""
    echo -e "Build a VM image with rootfs encrypted"
    echo -e ""
    echo -e " -p, --passphrase {PASS}   LUKS passphrase [default: ${CVM_LUKS_PASSPHRASE}]"
    echo -e " -h, --help                print this help"
}

while [ "$1" != "" ]; do
    case $1 in
        -p | --passphrase )
            shift
            CVM_LUKS_PASSPHRASE=$1
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

mkdir -p ${SCRIPT_PATH}/images

# Anaconda kickstart file based on
# https://gist.github.com/crobinso/830512728bf707a35e73755ed65988c4
cat << EOF > "${LUKS_KS}"
rootpw --plaintext root
firstboot --disable
timezone America/New_York --utc
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
reboot
text
skipx

ignoredisk --only-use=vda
clearpart --all --initlabel --disklabel=gpt --drives=vda
part /boot/efi --size=512 --fstype=efi
part /boot --size=512 --fstype=xfs --label=boot
part / --fstype="xfs" --ondisk=vda --encrypted --label=root --luks-version=luks2 --grow --passphrase "${CVM_LUKS_PASSPHRASE}"

%packages
@^server-product-environment
%end

%post
# use tpm to unlock the disk
cat /etc/crypttab | awk '{print \$1" "\$2" - tpm2-device=auto,tpm2-pcrs=0,1,4,5,7,9"}' | tee /etc/crypttab
# Put "tpm" driver in the initrd
echo 'add_drivers+=" tpm "' > /etc/dracut.conf.d/99-tpm.conf
# Trigger initrd rebuild
dnf reinstall -y kernel\*
# Install coconut kernel
dnf copr enable -y @virtmaint-sig/sev-snp-coconut
dnf install -y kernel-snp-coconut tpm2-tools git make pwgen
%end
EOF

virt-install --connect qemu:///session \
    --ram 4096 --vcpus 4 --disk path="${CVM_IMAGE}",size=20 \
    --location https://dl.fedoraproject.org/pub/fedora/linux/releases/"${CVM_FEDORA}"/Server/x86_64/os/ \
    --noreboot --transient --destroy-on-exit --nographic \
    --initrd-inject "${LUKS_KS}" --extra-args "inst.ks=file:/luks.ks console=ttyS0" \
    --tpm none --boot uefi

#rm "${LUKS_KS}"
