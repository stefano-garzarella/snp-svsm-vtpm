# AMD SEV-SNP PoC with SVSM, KBS proxy, virtio-blk device, and stateful vTPM

This PoC will allow you to start a Confidential VM on AMD SEV-SNP.

In this demo we will see how SVSM can be used to emulate a stateful vTPM (EK keys
and EV state are preserved at each boot).

The vTPM state is saved encrypted in the SVSM state file and exposed to SVSM
as a virtio-blk device over MMIO.
Remote attestation is used to get the SVSM state key after a successful attestation.

## Prerequisites

### Host machine

For running this demo, you need the host machine with:
- AMD processor that supports SEV-SNP
- Coconut Linux kernel installed, you can build it yourself or install it
  via copr in Fedora:
  - Coconut source kernel code.  
    You can build the host kernel by following the instructions here:
    https://github.com/coconut-svsm/svsm/blob/main/Documentation/INSTALL.md#preparing-the-host
  - Fedora copr package  
```shell
sudo dnf copr enable -y @virtmaint-sig/sev-snp-coconut
sudo dnf install kernel-snp-coconut
```

### Build machine

This repository contains the QEMU code, EDK2 code, MS TPM simulator, and several
Rust projects, so I recommend that you install the following packages
(for Fedora 40) to use the scripts contained in this demo:

```
sudo dnf builddep https://src.fedoraproject.org/rpms/qemu/raw/f40/f/qemu.spec
sudo dnf builddep https://src.fedoraproject.org/rpms/edk2/raw/f40/f/edk2.spec
sudo dnf install cargo rust rust-std-static-x86_64-unknown-none \
                 autoconf automake autoconf-archive \
                 buildah podman cbindgen bindgen-cli CUnit-devel openssl \
                 sqlite-devel virt-install
```

## Demo

### Build QEMU, EDK2, and SVSM

This operation is only required the first time, or when git submodules are updated

```shell
./prepare.sh
```

### Build the guest image with an encrypted rootfs

This is only required the first time or when you want to regenerate a new
image (for example, with a different encryption key).

The script will also install the coconut kernel for the guest, put the
`tpm` module in the initrd, and configure `/etc/crypttab` to use the TPM
to unseal the LUKS key.

```shell
./build-vm-image.sh --passphrase <LUKS passphrase>
```

### Start Key Broker server and SVSM proxy

This script starts in the host the Key Broker server (it will be remote in a
real scenario) and the proxy used by SVSM to communicate with the server.
The proxy forwards requests arriving from SVSM via a serial port to the http
connection with the server.

```shell
./start-kbs.sh
```

### Register launch measurement and the SVSM state key in the Key Broker server

This script first calculates the launch measurement (SVSM, OVMF, etc.) and then
registers it in the Key Broker server along with the SVSM state key (512 bits).

```shell
# we are using XTS for the encryption layer with AES256
# XTS requires two AES256 keys, so 512 bits (64 bytes) in total
./register-resource-in-kbs.sh -p $(openssl rand -hex 64)
```

### Manufacture the MS TPM

This operation is only required the first time, or when we want to regenerate
the TPM state.
In this way, the TPM's EK are recreated and NV state reset, so all sealed
secrets can no longer be unsealed.

Note: We currently do not have a tool available, so the script clears the SVSM
state and launches a diskless CVM. In this way SVSM, finding the state empty,
generates a new vTPM.

```shell
./remanufacture-tpm.sh
```

### Start the Confidential VM

And finally we launch our CVM. SVSM will receive the key from the Key Broker
server and can access its state by decrypting it.

```shell
./start-cvm.sh
```

### Seal the LUKS key with the TPM

#### First boot

If the VM disk is encrypted (for example, if it was generated with the script
included in this repo), the passphrase will be requested during the first boot:

```
Please enter passphrase for disk QEMU_HARDDISK (luks-bf91e8fe-c1e3-4696-937f-51c83d312eb9)::
<LUKS passphrase>
```

After entering the right passphrase, the rootfs will be mounted and we have
access to the CVM.

At this point we can take advantage of the stateful TPM emulated by SVSM to
unlock the disk at every boot.
Then, using `systemd-cryptenroll`, we can seal the LUKS passphrase with the TPM
and use different PCRs as policy.

```
# identify the LUKS encrypted volume
blkid -t TYPE=crypto_LUKS
/dev/sda3: UUID="bf91e8fe-c1e3-4696-937f-51c83d312eb9" TYPE="crypto_LUKS" PARTUUID="a7a021b0-f96d-431c-a94f-97ba8761228c"

# install the LUKS key for /dev/sda3 using as policy the PCRs 0,1,4,5,7,9
systemd-cryptenroll /dev/sda3 --tpm2-device=auto --tpm2-pcrs=0,1,4,5,7,9
<LUKS passphrase>
```

Rebooting CVM we can see how the LUKS passphrase is no longer required,
as it is sealed with the TPM.

#### Change the Linux `cmdline` to alter a PCR

Linux's cmdline is measured in PCR 9, so to see what happens when a policy
changes, let's alter the cmdline:

```
# read PCR 9
tpm2_pcrread sha256:9
  sha256:
    9 : 0xCA390570D8EE6298374E7223C3D5D4FF798731D6B9D1B542F564483A391FE4D4

# add a new parameter in the Linux cmdline
grubby --update-kernel=ALL --args="foo"
```

Rebooting CVM we find that the rootfs is no longer automatically unlocked,
as PCR 9 is different. After entering the requested LUKS passphrase during
boot, we can check the PCR 9 and re-install the key:

```
# read PCR 9
tpm2_pcrread sha256:9
  sha256:
    9 : 0xC7824417EDF7422F2011931ECAC930B789AACAA6E68175622347736D71DEE920

# wipe previous keys
systemd-cryptenroll /dev/sda3 --wipe-slot=tpm2

# install the LUKS key for /dev/sda3 using as policy the PCRs 0,1,4,5,7,9
systemd-cryptenroll /dev/sda3 --tpm2-device=auto --tpm2-pcrs=0,1,4,5,7,9
<LUKS passphrase>
```

At this point we can reboot and have the rootfs automatically unlock again
until the PCRs 0,1,4,5,7,9 are unchanged.

#### Re-manufacture the TPM

As we have seen, the LUKS passphrase is soldered with the TPM. This ensures
that if the TPM changes (e.g., it is re-manufactured), the new TPM will no
longer be able to unseal the secret.

So let's try re-manufacturing it. In this way the TPM's EK are regenerated and
NV state completely reset.

```
# Re-manufacture the MS TPM state
./remanufacture-tpm.sh

# Start the CVM
./start-cvm.sh
```

Rebooting CVM we find that the rootfs is no longer automatically unlocked, as
the TPM is a new one. After entering the requested LUKS passphrase during
boot, we can re-install the key:

```
# wipe previous keys
systemd-cryptenroll /dev/sda3 --wipe-slot=tpm2

# install the LUKS key for /dev/sda3 using as policy the PCRs 0,1,4,5,7,9
systemd-cryptenroll /dev/sda3 --tpm2-device=auto --tpm2-pcrs=0,1,4,5,7,9
<LUKS passphrase>
```

### Install EK certificate in the vTPM NVRAM

The MS-TPM does not generate an EK certificate during manufacture, so
launching `tpm2_getekcertificate` or `tpm2_nvread 0x1c00002` in the CVM will
get an error.

In the future we will provide a tool to generate the EK certificate and
install it offline in the vTPM, but for now we can generate it directly in
the VM on the first boot:

```
git clone https://github.com/stefano-garzarella/tpm2_ek_cert_generator.git
cd tpm2_ek_cert_generator
make
```

At this point the EK certificate is written in the NVRAM, so the following
commands now works also after reboot:
```
tpm2_getekcertificate
tpm2_nvread 0x1c00002
```

The certificate is self-signed, but in this PoC we only use it to test the
vTPM functionality.

Note: The `tpm2_ek_cert_generator` installs the certificate in the owner
hierarchy, because the platform hierarchy is disabled by EDK2. When the script
for offline manufacturing will become available, we could use the platform
hierarchy.

### Seal and unseal secrets in the Confidential VM

#### Seal a secret

Now that we have the VM running with the vTPM, we can do secret sealing, also
linking it to certain PCRs.

```
PRIMARY_CTX=/tmp/current_primary.ctx
tpm2_createprimary -c "$PRIMARY_CTX"

tpm2_pcrread -Q -o pcr.bin sha256:0,1,2,3
tpm2_createpolicy --policy-pcr -l sha256:0,1,2,3 -f pcr.bin -L pcr.policy
echo "secret" | tpm2_create -C "$PRIMARY_CTX" -L pcr.policy -i - -u seal.pub -r seal.priv -c seal.ctx
```

This secret can only be released if the TPM state is preserved, so let's try
shutting down the VM and turning it back on.

#### Unseal the secret after a reboot

```
PRIMARY_CTX=/tmp/current_primary.ctx
tpm2_createprimary -c "$PRIMARY_CTX"

tpm2_load -C "$PRIMARY_CTX" -u seal.pub -r seal.priv -c seal.ctx 
tpm2_unseal -c seal.ctx -p pcr:sha256:0,1,2,3
```

If everything works, we should be able to see our “secret” after the last
command.

#### Re-manufacture the TPM

To see what happens if the state of the vTPM changes, let's try
re-manufacturing it. In this way the TPM's EK are regenerated and NV state
completely reset.

```
# Re-manufacture the MS TPM state
./remanufacture-tpm.sh

# Start the CVM
./start-cvm.sh
```

If we try the same steps as in the previous paragraph for unsealing, we see
that this fails because we basically have a new TPM.

```
$ tpm2_load -C "$PRIMARY_CTX" -u seal.pub -r seal.priv -c seal.ctx
WARNING:esys:src/tss2-esys/api/Esys_Load.c:324:Esys_Load_Finish() Received TPM Error 
ERROR:esys:src/tss2-esys/api/Esys_Load.c:112:Esys_Load() Esys Finish ErrorCode (0x000001df) 
ERROR: Eys_Load(0x1DF) - tpm:parameter(1):integrity check failed
```

#### Change the encryption key

The same behavior is also obtained by changing the encryption key registered in
KBS. In this way SVSM is unable to access the previous state and thus the
emulated TPM is unable to unseal the keys.

```
# Register a new SVMS encryption state key
./register-resource-in-kbs.sh -p $(openssl rand -hex 64)

# Start the CVM
./start-cvm.sh --image path/to/guest/disk.qcow2
```

And the TPM is not able to unseal the secrets.

```
$ tpm2_load -C "$PRIMARY_CTX" -u seal.pub -r seal.priv -c seal.ctx
WARNING:esys:src/tss2-esys/api/Esys_Load.c:324:Esys_Load_Finish() Received TPM Error 
ERROR:esys:src/tss2-esys/api/Esys_Load.c:112:Esys_Load() Esys Finish ErrorCode (0x000001df) 
ERROR: Eys_Load(0x1DF) - tpm:parameter(1):integrity check failed
```

