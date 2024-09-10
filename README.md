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
  - **Coconut source kernel code. [preferred]**  
    You can build the host kernel by following the instructions here:
    https://github.com/coconut-svsm/svsm/blob/main/Documentation/INSTALL.md#preparing-the-host
  - *Fedora copr package*  
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
                 buildah podman cbindgen bindgen-cli CUnit-devel openssl
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

### Start the Confidential VM

And finally we launch our CVM. SVSM will receive the key from the Key Broker
server and can access its state by decrypting it.

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

#### Change the encryption key

The same behavior is also obtained by changing the encryption key registered in KBS. In this way SVSM is unable to access the previous state and thus the emulated TPM is unable to unseal the keys.

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

