# AMD SEV-SNP PoC with SVSM, KBS proxy, and vTPM state injection

This PoC will allow you to start a Confidential VM on AMD SEV-SNP.

In this demo we will see how SVSM can be used to emulate a trusted vTPM.
Remote attestation is used to unlock the vTPM state which is then injected at
every boot.

This is just a PoC and the state is reloaded by KBS at every boot. In this way
the EK keys are preserved at each boot, but the EV state is reset to the one
registered in KBS.

The next step is to save the encrypted state in the host and receive from KBS
only the key to unlock it.

## Prerequisites

### Host machine

For running this demo, you need the host machine with:
- AMD processor that supports SEV-SNP
- Coconut Linux kernel installed, you can build it yourself or install it
  via copr in Fedora:
  - **Coconut source kernel code. [preferred]**  
    You can build the host kernel by following the instructions here:
    https://github.com/coconut-svsm/svsm/blob/main/Documentation/INSTALL.md#preparing-the-host
  - *Fedora copr package*  
    As we write the copr repository has not yet been updated, so this may not support vTPM.
```shell
sudo dnf copr enable -y @virtmaint-sig/sev-snp-coconut
sudo dnf install kernel-snp-coconut
```

### Guest virtual machine

For running this demo, you need a QCOW2 disk image with:
- Coconut Linux kernel installed, you can build it yourself or install it
  via copr in Fedora:
  - **Coconut source kernel code. [preferred]**  
    You can build the host kernel by following the instructions here:
    https://github.com/coconut-svsm/svsm/blob/main/Documentation/INSTALL.md#preparing-the-host
  - *Fedora copr package*  
    As we write the copr repository has not yet been updated, so this may not support vTPM.
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
                 buildah podman cbindgen bindgen-cli CUnit-devel
```

## Demo

### Build QEMU, EDK2, and SVSM

This operation is only required the first time, or when git submodules are updated

```shell
./prepare.sh
```

### Manufacture the MS TPM

This operation is only required the first time, or when we want to regenerate
the TPM state.
In this way, the TPM's EK are recreated and NV state reset, so all sealed
secrets can no longer be unsealed.

```shell
./remanufacture-tpm.sh
```

#### Use the simulator locally
The simulator can also be used locally in the host for example to do a
sealing of a secret. See more details [here](https://github.com/stefano-garzarella/ms-tpm-containerized-build/tree/5deed9b66ac234af4924a3af9142a2445a27ed07?tab=readme-ov-file#tpm2-tools-and-tpm2-abrmd).

### Start Key Broker server and SVSM proxy

This script starts in the host the Key Broker server (it will be remote in a
real scenario) and the proxy used by SVSM to communicate with the server.
The proxy forwards requests arriving from SVSM via a serial port to the http
connection with the server.

```shell
./start-kbs.sh
```

### Register launch measurement and the TPM state in the Key Broker server

This script first calculates the launch measurement (SVSM, OVMF, etc.) and then
registers it in the Key Broker server along with the TPM state.

```shell
./register-resource-in-kbs.sh
```

### Start the Confidential VM

And finally we launch our CVM which will receive the key from the Key Broker
server and mount the rootfs by decrypting it.

```shell
./start-cvm.sh --image path/to/guest/disk.qcow2
```

### Seal a secret in the Confidential VM
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

### Unseal the secret after a reboot

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

# Register the new state in KBS
./register-resource-in-kbs.sh

# Start the CVM
./start-cvm.sh --image path/to/guest/disk.qcow2
```

If we try the same steps as in the previous paragraph for unsealing, we see
that this fails because we basically have a new TPM.

```
$ tpm2_load -C "$PRIMARY_CTX" -u seal.pub -r seal.priv -c seal.ctx
WARNING:esys:src/tss2-esys/api/Esys_Load.c:324:Esys_Load_Finish() Received TPM Error 
ERROR:esys:src/tss2-esys/api/Esys_Load.c:112:Esys_Load() Esys Finish ErrorCode (0x000001df) 
ERROR: Eys_Load(0x1DF) - tpm:parameter(1):integrity check failed
```
