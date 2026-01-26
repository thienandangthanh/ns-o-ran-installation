# Linux VM Setup Guide

This guide covers Linux-specific setup for running ns-O-RAN in a VM using libvirt/KVM with virt-manager. If you're using Windows with VirtualBox/VMware, you can skip this guide and follow the main README.md instructions.

---

## Prerequisites

- **Host OS**: Linux (any distribution)
- **VM**: Ubuntu 20.04.6
- **Tools**: libvirt, virt-manager, virtiofs support

---

## VM Setup with libvirt/KVM

### 1. Install libvirt and virt-manager

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager

# Archlinux
# https://wiki.archlinux.org/title/Libvirt
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm \
  virt-manager qemu vde2 dnsmasq bridge-utils \
  openbsd-netcat libvirt edk2-ovmf iptables iptables-nft \
  qemu-desktop
sudo usermod -aG libvirt "$(whoami)"
# You may need to log out and log back in for group changes to take effect.

# Start libvirt service
sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now virtlogd.socket
```

### 2. Create Ubuntu 20.04 VM

1. Download ISO file of Ubuntu 20.04.6 LTS (Focal Fossa) from [official website](https://releases.ubuntu.com/focal/)
3. Open virt-manager: `virt-manager`
4. Create a new VM:
   - **Name**: `oran-kvm` (or your preferred name)
   - **OS**: Ubuntu 20.04.6
   - **Memory**: At least 4GB recommended
   - **CPU**: At least 4 cores recommended
   - **Disk**: At least 40GB

### 3. Configure virtiofs for Shared Directory

To share the repository directory from host to VM:

1. **On host**, create a shared directory (if not exists):
   ```bash
   mkdir -p ~/ns-O-RAN-installation
   ```

2. **In virt-manager**:
   - Select your VM -> Open
   - Click "View" -> "Details"
   - In "Memory" tab -> Check "Enable shared memory" **Without shared memory enabled, virtiofs will not work.**
   - Click "Add Hardware" -> Filesystem
   - **Driver**: virtiofs
   - **Source path**: `/home/YOUR_USERNAME/ns-O-RAN-installation` (or your repo path)
   - **Target path**: `/ns-O-RAN-installation`
   - Apply and start the VM

3. **In the VM**, mount the virtiofs share:
   ```bash
   # Add to /etc/fstab for permanent mount
   echo "/ns-O-RAN-installation /home/$(whoami)/ns-O-RAN-installation virtiofs defaults 0 0" | sudo tee -a /etc/fstab

   # Mount it
   sudo mkdir -p ~/ns-O-RAN-installation
   sudo mount -t virtiofs /ns-O-RAN-installation ~/ns-O-RAN-installation

   # Fix ownership
   sudo chown -R $(whoami):$(whoami) ~/ns-O-RAN-installation
   ```

   **Alternative**: If you prefer manual mounting:
   ```bash
   sudo mount -t virtiofs /ns-O-RAN-installation ~/ns-O-RAN-installation
   ```

### 4. Configure SSH Access (Optional)

If you want to access the VM via SSH from the host:

1. **In the VM**, install and enable SSH:
   ```bash
   sudo apt-get update
   sudo apt-get install -y openssh-server
   sudo systemctl enable --now ssh
   ```

2. **Configure hostname** (optional, for easier SSH access):
   ```bash
   # In VM
   sudo hostnamectl set-hostname oran-kvm
   ```

3. **Set up SSH key authentication** (recommended):
   ```bash
   # On host
   ssh-keygen -t ed25519 -C "your_email@example.com"  # if you don't have one
   ssh-copy-id user@VM_IP_ADDRESS

   # Add to ~/.ssh/config on host for convenience
   cat >> ~/.ssh/config << EOF
   Host oran-kvm
       HostName VM_IP_ADDRESS
       User your_vm_username
       IdentityFile ~/.ssh/id_ed25519
   EOF
   ```

4. **Find VM IP address**:
   ```bash
   # In VM
   ip addr show | grep "inet "

   # Or from host (if using default network)
   virsh domifaddr oran-kvm
   ```

### 5. Network Configuration

The RIC stack uses the subnet `10.0.2.0/24`. Ensure your VM network allows this:

- **Default NAT**: Usually works out of the box
- **Bridge network**: May need additional configuration
- **Custom network**: Configure in virt-manager -> Virtual Networks

---

## Quick Reference

### Common Commands

```bash
# List VMs
virsh list --all

# Start VM
virsh start oran-kvm

# Shutdown VM
virsh shutdown oran-kvm

# Access VM console
virsh console oran-kvm

# SSH to VM (if configured)
ssh oran-kvm

# Check virtiofs mount in VM
mount | grep virtiofs
```

### Troubleshooting

**virtiofs not mounting:**
- Ensure virtiofs is enabled in VM hardware
- Check kernel support: `modprobe virtiofs` (in VM)
- Verify mount point exists: `ls -la ~/ns-O-RAN-installation`

**SSH connection issues:**
- Verify SSH service is running: `sudo systemctl status ssh`
- Check firewall: `sudo ufw status`
- Verify IP address hasn't changed: `ip addr show`

**Network connectivity:**
- Test ping: `ping 10.0.2.10` (from VM)
- Check Docker network: `docker network ls`
- Verify RIC subnet: `docker network inspect ric`

---

## Alternative: Without virtiofs

If you prefer not to use virtiofs, you can:

1. **Clone repo directly in VM**:
   ```bash
   cd ~
   git clone <repo-url> ns-O-RAN-installation
   cd ns-O-RAN-installation
   git submodule update --init --recursive
   ```

2. **Use SCP/SFTP** to transfer files between host and VM

3. **Use shared folders** (if using VirtualBox/VMware)

---

## Next Steps

After completing this setup:

1. Ensure the repo is at `~/ns-O-RAN-installation` in the VM
2. Follow the main [README.md](../README.md) for installation and usage instructions
