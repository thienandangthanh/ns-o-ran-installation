# Linux VM Setup Guide

This guide sets up the libvirt/KVM host and the gate VM that the L-release (NIST v1.8.0) gates run on, up to the `fresh-install` snapshot. From there, follow [deployment-guide-l-release.md](deployment-guide-l-release.md). The requirements the scripts check are in that guide's Prerequisites table; this guide shows how to meet them.

The legacy Bronze-RIC flow (Ubuntu 20.04, virtiofs share) is at the end.

---

## 1. Host

- Linux with KVM, libvirt and `qemu:///system`.
- The host user manages `qemu:///system` without sudo (libvirt group). The scripts never call host sudo (`scripts/vm/vm-common.sh`).
- `ssh`, `git`, `python3`, `gh` (logged in; `gate-m0-host.sh` checks that the harness repo is public).
- Free space under `/home` (the VM image directory, `VM_IMAGE_DIR`, default `/home/andang/VMs`): about 70 GB for M0 to M7, more for M9 (see the deployment guide's disk budget).

```bash
# Ubuntu/Debian
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager

# Arch Linux (https://wiki.archlinux.org/title/Libvirt)
sudo pacman -S --needed libvirt qemu-desktop dnsmasq edk2-ovmf virt-install virt-manager

sudo usermod -aG libvirt "$(whoami)"   # log out and back in afterwards
sudo systemctl enable --now libvirtd.service virtlogd.socket
virsh -c qemu:///system net-start default 2>/dev/null; virsh -c qemu:///system net-autostart default
```

## 2. Gate VM

The recorded VM (the one every green run used):

| Setting | Value |
|---|---|
| libvirt domain | `ubuntu24.04` (override with `VM_DOMAIN`) |
| ISO | `ubuntu-24.04.5-live-server-amd64.iso`, e.g. `https://ftp.kaist.ac.kr/ubuntu-cd/24.04.5.1/ubuntu-24.04.5-live-server-amd64.iso` |
| Install | vanilla minimal server install, default LVM layout, OpenSSH server enabled; no package updates |
| vCPU / RAM | 8 / 16 GiB (the gates need at least 8 vCPU and 14 GiB) |
| Disk | 100 GB virtio disk in `VM_IMAGE_DIR` (the root LV came out at 96 GB; the gates need 60 GB free on `/`) |
| Network | libvirt `default` NAT network, virtio NIC |
| User | `uc` |
| Shared folders | none: the VM clones the harness and the forks from GitHub at pinned SHAs |

Create it with virt-manager or `virt-install`, for example:

```bash
virt-install --connect qemu:///system --name ubuntu24.04 --vcpus 8 --memory 16384 \
  --disk path=$HOME/VMs/ubuntu24.04,size=100,format=qcow2,bus=virtio \
  --cdrom ubuntu-24.04.5-live-server-amd64.iso --os-variant ubuntu24.04 \
  --network network=default,model=virtio
```

(The `virt-install` line is an equivalent of the recorded setup, not the command that built it. The recorded `fresh-install` overlay has a libvirt-generated name, `ubuntu24.1792618108`, because it was taken without an explicit file.)

## 3. SSH alias and passwordless sudo

On the host, add a key-based alias (default name `oran-kvm-2404`, override with `VM_SSH`):

```bash
virsh -c qemu:///system domifaddr ubuntu24.04     # VM address on the default network
ssh-copy-id uc@<VM address>
cat >> ~/.ssh/config <<'EOF'
Host oran-kvm-2404
    HostName <VM address>
    User uc
EOF
```

Then give `uc` passwordless sudo. This is the only change made to the vanilla install:

```bash
ssh -t oran-kvm-2404 "echo 'uc ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-uc-agent"
```

Do not put git credentials or SSH private keys in the VM; `gate-m0-host.sh` fails if it finds any.

## 4. The `fresh-install` snapshot

Shut the VM off and take an offline, external, disk-only snapshot. Every gate run starts from it, and no script deletes it.

```bash
virsh -c qemu:///system shutdown ubuntu24.04     # wait until "shut off"
virsh -c qemu:///system snapshot-create-as ubuntu24.04 fresh-install \
  --disk-only --atomic \
  --diskspec vda,snapshot=external,file=$HOME/VMs/ubuntu24.04-fresh-install.qcow2 \
  --diskspec sda,snapshot=no
scripts/vm/vm-snapshot.sh list
```

`--diskspec sda,snapshot=no` excludes the empty CD-ROM drive; drop it if the domain has none. Later snapshots are made by `scripts/vm/vm-snapshot.sh create`, which uses the same form.

Next: [deployment-guide-l-release.md](deployment-guide-l-release.md), from "Pins".

Note: all green runs so far used this one host and VM; a run on a second workstation is untested (deferred).

---

## Legacy: Bronze RIC VM (Ubuntu 20.04, virtiofs)

For the legacy flow in the README only; the gates do not use it.

- VM: Ubuntu 20.04.6, at least 4 vCPU, 4 GB RAM, 40 GB disk, Docker.
- Share the repo into the VM with virtiofs. In virt-manager, enable shared memory under Memory (virtiofs does not work without it), then add a Filesystem with driver `virtiofs`, source path `/home/<you>/ns-O-RAN-installation` and target path `/ns-O-RAN-installation`. In the VM:

  ```bash
  mkdir -p ~/ns-O-RAN-installation
  echo "/ns-O-RAN-installation /home/$(whoami)/ns-O-RAN-installation virtiofs defaults 0 0" | sudo tee -a /etc/fstab
  sudo mount -t virtiofs /ns-O-RAN-installation ~/ns-O-RAN-installation
  ```

- Instead of virtiofs, you can clone the repo in the VM: `git clone --recursive <repo-url> ~/ns-O-RAN-installation`.
- The Bronze RIC uses the Docker subnet `10.0.2.0/24` (check with `docker network inspect ric`); the default NAT network works.
- Troubleshooting: if virtiofs does not mount, check shared memory is enabled and `modprobe virtiofs` works in the VM.
