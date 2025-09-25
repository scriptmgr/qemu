# 🚀 QEMU/KVM Virtualization Environment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://github.com/scriptmgr/qemu)
[![Shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](https://github.com/scriptmgr/qemu)

Complete QEMU+libvirt virtualization environment installer with web management panel and GUI tools.

## ✨ Features

- 🐧 **Multi-distro support**: Debian/Ubuntu, RHEL/Fedora/CentOS, Arch, OpenSUSE, Alpine
- 🔧 **Nested virtualization**: Automatically enabled for Intel VT-x and AMD-V
- 🌐 **Web management**: Cockpit panel on `http://127.0.0.1:41443`
- 🖥️ **GUI management**: virt-manager included for desktop environments
- 📝 **Helper scripts**: Simplified VM creation and management
- 🔒 **UEFI support**: OVMF/EDK2 firmware included
- 🌐 **Network management**: Pre-configured NAT network with DHCP
- 🎨 **Pretty output**: Color-coded logs with emoji indicators
- 🔄 **Smart detection**: Handles existing configurations gracefully

## 📦 Installation

```bash
# Clone repository
git clone https://github.com/scriptmgr/qemu.git
cd qemu

# Make script executable
chmod +x install.sh

# Run installer as root
sudo ./install.sh
```

## 🐧 Supported Distributions

| Distribution | Package Manager | Status |
|-------------|----------------|---------|
| Ubuntu/Debian | apt | ✅ Full support |
| Fedora/RHEL/CentOS/AlmaLinux | dnf/yum | ✅ Full support |
| Arch Linux/Manjaro | pacman | ✅ Full support |
| OpenSUSE/SLES | zypper | ✅ Full support |
| Alpine Linux | apk | ⚠️ Limited (no Cockpit) |

## 📋 Package Mapping

### 🎯 Core Packages
- **QEMU**: System emulation and virtualization
- **KVM**: Kernel-based Virtual Machine modules
- **libvirt**: Virtualization API and management daemon
- **bridge-utils**: Network bridging utilities

### 🛠️ Management Tools
- **virt-manager**: Full-featured GUI application for managing VMs (included by default)
- **virsh**: Command-line interface for libvirt
- **Cockpit**: Web-based management interface
- **cockpit-machines**: VM management plugin for Cockpit

## 💻 Usage

### 🌐 Web Interface
Access the Cockpit web panel at `http://127.0.0.1:41443`
- 🔐 Login with your system credentials
- 🖥️ Manage VMs through the "Virtual Machines" section
- 📊 Monitor system resources and performance
- 🌐 Configure network settings
- 💾 Manage storage pools

### 🖥️ GUI Management
```bash
# Run virt-manager GUI
virt-manager

# virt-manager features:
# - Create and configure VMs with wizard
# - Live migration between hosts
# - Performance monitoring
# - Snapshot management
# - Console access (VNC/SPICE)
# - Network and storage pool management
```

### ⌨️ Command Line

#### 📝 Helper Scripts
```bash
# Create a new VM
qemu-create-vm <name> <disk-size-GB> [iso-path]
# Example:
qemu-create-vm ubuntu-vm 20 /path/to/ubuntu.iso

# List VMs
qemu-manage list

# Start/Stop VMs
qemu-manage start <vm-name>
qemu-manage stop <vm-name>

# Delete VM
qemu-manage delete <vm-name>
```

#### 🔧 Using virsh
```bash
# List all VMs
virsh list --all

# Start a VM
virsh start <vm-name>

# Connect to VM console
virsh console <vm-name>

# Get VM info
virsh dominfo <vm-name>

# Create snapshot
virsh snapshot-create-as <vm-name> <snapshot-name>

# List snapshots
virsh snapshot-list <vm-name>
```

#### 🚀 Using virt-install
```bash
# Create VM with full options
virt-install \
  --name test-vm \
  --memory 2048 \
  --vcpus 2 \
  --disk size=10 \
  --cdrom /path/to/iso \
  --network network=default \
  --graphics vnc \
  --boot uefi \
  --cpu host-passthrough
```

## 🪆 Nested Virtualization

The installer automatically enables nested virtualization for both Intel and AMD processors:

- **Intel**: `kvm_intel` module with `nested=1`
- **AMD**: `kvm_amd` module with `nested=1`

Verify nested virtualization:
```bash
# Intel
cat /sys/module/kvm_intel/parameters/nested

# AMD
cat /sys/module/kvm_amd/parameters/nested

# Check if running in VM (for nested setup)
systemd-detect-virt
```

## 🌐 Network Configuration

Default network configuration:
- **Bridge**: virbr0
- **Network**: 192.168.122.0/24
- **Gateway**: 192.168.122.1
- **DHCP Range**: 192.168.122.2 - 192.168.122.254
- **Mode**: NAT

Additional network management:
```bash
# List networks
virsh net-list --all

# Create new network
virsh net-define /path/to/network.xml

# Edit network
virsh net-edit <network-name>
```

## 🔍 Troubleshooting

### ❌ KVM Module Not Loading
```bash
# Check if virtualization is enabled in BIOS
egrep -c '(vmx|svm)' /proc/cpuinfo

# Load module manually
sudo modprobe kvm_intel  # For Intel
sudo modprobe kvm_amd    # For AMD

# Check module status
lsmod | grep kvm
```

### ❌ Cockpit Not Accessible
```bash
# Check service status
systemctl status cockpit.socket

# Restart service
systemctl restart cockpit.socket

# Check listening port
ss -tlnp | grep 41443

# Check if Cockpit is enabled
systemctl is-enabled cockpit.socket

# View logs
journalctl -u cockpit
```

### ❌ Permission Denied
```bash
# Add user to libvirt group
sudo usermod -aG libvirt $USER

# Re-login for group changes to take effect
newgrp libvirt

# Check group membership
groups
```

### ❌ VM Network Issues
```bash
# Check default network
virsh net-list --all

# Start default network
virsh net-start default
virsh net-autostart default

# Restart libvirt
systemctl restart libvirtd

# Check firewall rules
iptables -L -n -v | grep virbr0
```

## 🔒 Security Considerations

- 🔒 Cockpit is configured to listen only on localhost (127.0.0.1:41443)
- Authentication required for all management operations
- SELinux/AppArmor policies maintained where applicable
- Firewall rules automatically configured
- libvirt uses polkit for access control
- VMs run with restricted privileges by default

## 📁 Files and Directories

- `/var/lib/libvirt/images/` - Default VM disk storage
- `/etc/libvirt/` - libvirt configuration
- `/etc/cockpit/` - Cockpit configuration
- `/usr/local/bin/qemu-*` - Helper scripts
- `/etc/modprobe.d/kvm-nested.conf` - Nested virtualization config
- `/var/log/libvirt/` - libvirt logs

## ⚡ Requirements

- Root/sudo access for installation
- CPU with virtualization support (Intel VT-x or AMD-V)
- Minimum 4GB RAM recommended
- 20GB+ free disk space for VMs
- 64-bit processor architecture
- Linux kernel 3.x or higher

## 📄 License

MIT

## 📦 Repository

https://github.com/scriptmgr/qemu

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🐛 Issues

Report issues at: https://github.com/scriptmgr/qemu/issues