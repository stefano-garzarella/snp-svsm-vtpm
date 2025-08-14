#!/bin/bash
SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Load VM configuration
source "${SCRIPT_PATH}/vm.conf"

LUKS_KS="${SCRIPT_PATH}/images/luks.ks"
USE_LIBVIRT=yes

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
        --no-libvirt)
            USE_LIBVIRT=no
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

# GPT partition type UUID for the root partition, for automatic detection.
# https://www.freedesktop.org/software/systemd/man/latest/systemd-gpt-auto-generator.html
SD_GPT_ROOT_X86_64=4f68bce3-e8cd-4db1-96e7-fbcaf984b709

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
part /boot --size=1024 --fstype=xfs --label=boot
part / --fstype="xfs" --ondisk=vda --encrypted --label=root --luks-version=luks2 --grow --passphrase "${CVM_LUKS_PASSPHRASE}"
bootloader --append="console=ttyS0"

%packages
@^server-product-environment
%end

%post
# Set GPT parition type UUID for the root parition
parted --script /dev/vda type 3 $SD_GPT_ROOT_X86_64
# use tpm to unlock the disk
cat /etc/crypttab | awk '{print \$1" "\$2" - tpm2-device=auto,tpm2-pcrs=0,1,4,5,7,9"}' | tee /etc/crypttab
# Put "tpm" driver in the initrd
echo 'add_drivers+=" tpm "' > /etc/dracut.conf.d/99-tpm.conf
# Trigger initrd rebuild
dracut --regenerate-all --force
%end
EOF

if [ "$USE_LIBVIRT" == "yes" ]; then

  virt-install --connect qemu:///session \
      --ram 4096 --vcpus 4 --disk path="${CVM_IMAGE}",size=20 \
      --location "${INSTALLER_URL}" \
      --noreboot --transient --destroy-on-exit --nographic \
      --initrd-inject "${LUKS_KS}" --extra-args "inst.ks=file:/luks.ks console=ttyS0" \
      --tpm none --boot uefi

  echo "You can ignore \"Domain installation does not appear to have been successful\""
  echo "message. CVM doesn't support reboot, so virt-install rebooting will fail,"
  echo "but your VM image is ready, enjoy!"

else

  "$QEMU_IMG" create -f qcow2 "${CVM_IMAGE}" 10G

  OEMDRV=$(mktemp)
  trap 'rm ${OEMDRV} || true' EXIT

  # Place kickstart file in a disk image
  truncate -s4M "${OEMDRV}"
  mkfs.vfat -n OEMDRV "${OEMDRV}"
  mcopy -o -i "${OEMDRV}" "${LUKS_KS}" ::ks.cfg

  # Download kernel and initrd
  curl --continue-at - \
    --remote-name "${INSTALLER_URL}/images/pxeboot/vmlinuz" \
    --remote-name "${INSTALLER_URL}/images/pxeboot/initrd.img"

  FW_CODE=${SCRIPT_PATH}/edk2/Build/OvmfX64/DEBUG_GCC/FV/OVMF.fd

  "${QEMU}" \
    -machine q35 \
    -machine accel=kvm -boot menu=off \
    -cpu max \
    -smp 4 \
    -m 4G \
    -blockdev node-name=code,driver=file,filename="${FW_CODE}",read-only=on \
    -machine pflash0=code \
    -device virtio-rng-pci \
    -drive if=virtio,file="${CVM_IMAGE}" \
    -drive if=virtio,file="${OEMDRV}",read-only=on,format=raw \
    -kernel ./vmlinuz \
    -initrd ./initrd.img \
    -append "console=ttyS0 console= inst.repo=$INSTALLER_URL" \
    -vga none \
    -display none \
    -serial stdio \
    -no-reboot
fi
echo "Disk image written to: ${CVM_IMAGE}"

#rm "${LUKS_KS}"
