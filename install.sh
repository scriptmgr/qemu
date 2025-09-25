#!/bin/sh
# QEMU+Libvirt Virtualization Environment Installer
# Repository: github.com/scriptmgr/qemu
# POSIX-compliant script for multi-distro support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COCKPIT_PORT=41443
REPO_URL="https://github.com/scriptmgr/qemu"

# Logging
log_info() {
    printf "${GREEN}✅ [INFO]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}❌ [ERROR]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}⚠️  [WARN]${NC} %s\n" "$1"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_NAME="$NAME"
    elif [ -f /etc/redhat-release ]; then
        DISTRO_ID="rhel"
        DISTRO_NAME="Red Hat Enterprise Linux"
    elif [ -f /etc/debian_version ]; then
        DISTRO_ID="debian"
        DISTRO_NAME="Debian"
    else
        log_error "Cannot detect Linux distribution"
        exit 1
    fi

    # Normalize distro IDs
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            DISTRO_FAMILY="debian"
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update"
            PKG_INSTALL="apt-get install -y"
            ;;
        fedora|rhel|centos|rocky|almalinux|ol)
            DISTRO_FAMILY="rhel"
            if command -v dnf >/dev/null 2>&1; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf check-update || true"
                PKG_INSTALL="dnf install -y"
            else
                PKG_MANAGER="yum"
                PKG_UPDATE="yum check-update || true"
                PKG_INSTALL="yum install -y"
            fi
            ;;
        arch|manjaro|endeavouros)
            DISTRO_FAMILY="arch"
            PKG_MANAGER="pacman"
            PKG_UPDATE="pacman -Sy"
            PKG_INSTALL="pacman -S --noconfirm"
            ;;
        opensuse*|sles)
            DISTRO_FAMILY="suse"
            PKG_MANAGER="zypper"
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            ;;
        alpine)
            DISTRO_FAMILY="alpine"
            PKG_MANAGER="apk"
            PKG_UPDATE="apk update"
            PKG_INSTALL="apk add"
            ;;
        *)
            log_error "Unsupported distribution: $DISTRO_ID"
            exit 1
            ;;
    esac

    log_info "🐧 Detected: $DISTRO_NAME ($DISTRO_ID) - Family: $DISTRO_FAMILY"
}

# Package mapping for different distributions
get_packages() {
    case "$DISTRO_FAMILY" in
        debian)
            PACKAGES="qemu-system-x86 qemu-utils qemu-block-extra"
            PACKAGES="$PACKAGES libvirt-daemon libvirt-daemon-system libvirt-clients"
            PACKAGES="$PACKAGES bridge-utils virt-manager virtinst"
            PACKAGES="$PACKAGES ovmf cpu-checker"
            PACKAGES="$PACKAGES cockpit cockpit-machines cockpit-bridge"
            # Development tools for potential compilation
            PACKAGES="$PACKAGES build-essential libguestfs-tools"
            ;;
        rhel)
            PACKAGES="qemu-kvm qemu-img virt-install"
            PACKAGES="$PACKAGES libvirt libvirt-client libvirt-daemon-kvm"
            PACKAGES="$PACKAGES bridge-utils virt-manager"
            PACKAGES="$PACKAGES cockpit cockpit-machines"
            # OVMF for UEFI support
            if [ "$PKG_MANAGER" = "dnf" ]; then
                PACKAGES="$PACKAGES edk2-ovmf"
            else
                PACKAGES="$PACKAGES OVMF"
            fi
            PACKAGES="$PACKAGES libguestfs-tools"
            ;;
        arch)
            PACKAGES="qemu-full libvirt virt-manager"
            PACKAGES="$PACKAGES bridge-utils dnsmasq vde2"
            PACKAGES="$PACKAGES edk2-ovmf cockpit cockpit-machines"
            PACKAGES="$PACKAGES libguestfs"
            ;;
        suse)
            PACKAGES="qemu qemu-kvm qemu-tools"
            PACKAGES="$PACKAGES libvirt libvirt-daemon libvirt-client"
            PACKAGES="$PACKAGES bridge-utils virt-manager"
            PACKAGES="$PACKAGES cockpit cockpit-machines"
            PACKAGES="$PACKAGES ovmf libguestfs"
            ;;
        alpine)
            PACKAGES="qemu qemu-system-x86_64 qemu-img"
            PACKAGES="$PACKAGES libvirt libvirt-daemon libvirt-client"
            PACKAGES="$PACKAGES bridge-utils virt-install"
            PACKAGES="$PACKAGES ovmf libguestfs"
            # Note: Cockpit might not be available on Alpine
            log_warn "Cockpit may not be available on Alpine Linux"
            ;;
    esac
}

# Check CPU virtualization support
check_virtualization() {
    log_info "🖥️  Checking CPU virtualization support..."

    if [ -f /proc/cpuinfo ]; then
        if grep -E '(vmx|svm)' /proc/cpuinfo > /dev/null 2>&1; then
            if grep -E 'vmx' /proc/cpuinfo > /dev/null 2>&1; then
                log_info "💎 Intel VT-x detected"
                CPU_VENDOR="intel"
            else
                log_info "💎 AMD-V detected"
                CPU_VENDOR="amd"
            fi
        else
            log_error "CPU does not support hardware virtualization"
            log_error "Please enable VT-x/AMD-V in BIOS/UEFI settings"
            exit 1
        fi
    else
        log_warn "Cannot check CPU virtualization support"
    fi
}

# Enable nested virtualization
enable_nested_virtualization() {
    log_info "🔧 Configuring nested virtualization..."

    # Check if running in a VM
    if [ -f /sys/devices/virtual/dmi/id/product_name ]; then
        PRODUCT=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
        case "$PRODUCT" in
            *VirtualBox*|*VMware*|*QEMU*|*KVM*)
                log_warn "Running inside a virtual machine. Nested virtualization may have limited performance."
                ;;
        esac
    fi

    # Load KVM modules
    if [ "$CPU_VENDOR" = "intel" ]; then
        MODULE="kvm_intel"
        NESTED_PARAM="nested=1"
    else
        MODULE="kvm_amd"
        NESTED_PARAM="nested=1"
    fi

    # Check if module is loaded
    if lsmod | grep -q "^$MODULE"; then
        log_info "KVM module already loaded"
        # Check if nested virtualization is enabled
        if [ "$CPU_VENDOR" = "intel" ]; then
            NESTED_FILE="/sys/module/kvm_intel/parameters/nested"
        else
            NESTED_FILE="/sys/module/kvm_amd/parameters/nested"
        fi

        if [ -f "$NESTED_FILE" ]; then
            NESTED_STATUS=$(cat "$NESTED_FILE")
            if [ "$NESTED_STATUS" = "Y" ] || [ "$NESTED_STATUS" = "1" ]; then
                log_info "Nested virtualization already enabled"
            else
                log_info "Enabling nested virtualization..."
                rmmod "$MODULE" 2>/dev/null || true
                modprobe "$MODULE" "$NESTED_PARAM"
            fi
        fi
    else
        log_info "Loading KVM module with nested virtualization..."
        modprobe "$MODULE" "$NESTED_PARAM"
    fi

    # Make nested virtualization persistent
    log_info "Making nested virtualization persistent..."
    echo "options $MODULE $NESTED_PARAM" > "/etc/modprobe.d/kvm-nested.conf"

    # Verify nested virtualization
    if [ "$CPU_VENDOR" = "intel" ]; then
        if [ -f /sys/module/kvm_intel/parameters/nested ]; then
            NESTED_ENABLED=$(cat /sys/module/kvm_intel/parameters/nested)
            if [ "$NESTED_ENABLED" = "Y" ] || [ "$NESTED_ENABLED" = "1" ]; then
                log_info "Nested virtualization successfully enabled for Intel"
            fi
        fi
    else
        if [ -f /sys/module/kvm_amd/parameters/nested ]; then
            NESTED_ENABLED=$(cat /sys/module/kvm_amd/parameters/nested)
            if [ "$NESTED_ENABLED" = "1" ]; then
                log_info "Nested virtualization successfully enabled for AMD"
            fi
        fi
    fi
}

# Install packages
install_packages() {
    log_info "📦 Updating package repositories..."
    $PKG_UPDATE

    log_info "📦 Installing virtualization packages (including virt-manager GUI)..."
    # shellcheck disable=SC2086
    $PKG_INSTALL $PACKAGES

    # Install additional tools based on distro
    case "$DISTRO_FAMILY" in
        debian)
            # Enable libvirtd service
            systemctl enable --now libvirtd
            ;;
        rhel)
            # Enable and start services
            systemctl enable --now libvirtd
            # Configure SELinux if present
            if command -v getenforce >/dev/null 2>&1; then
                if [ "$(getenforce)" != "Disabled" ]; then
                    log_info "Configuring SELinux for virtualization..."
                    setsebool -P virt_use_nfs 1 2>/dev/null || true
                    setsebool -P virt_use_samba 1 2>/dev/null || true
                fi
            fi
            ;;
        arch)
            # Enable and start services
            systemctl enable --now libvirtd
            systemctl enable --now virtlogd
            ;;
        suse)
            # Enable and start services
            systemctl enable --now libvirtd
            ;;
        alpine)
            # Add services to runlevel
            rc-update add libvirtd
            rc-service libvirtd start
            ;;
    esac
}

# Configure libvirt
configure_libvirt() {
    log_info "⚙️  Configuring libvirt..."

    # Backup original configuration
    if [ -f /etc/libvirt/libvirtd.conf ]; then
        cp /etc/libvirt/libvirtd.conf /etc/libvirt/libvirtd.conf.bak
    fi

    # Enable TCP listening for management (localhost only)
    cat >> /etc/libvirt/libvirtd.conf <<EOF

# Custom configuration for QEMU management
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
unix_sock_ro_perms = "0777"
unix_sock_dir = "/var/run/libvirt"
auth_unix_ro = "none"
auth_unix_rw = "none"
EOF

    # Configure QEMU to run as root for better hardware access (optional)
    if [ -f /etc/libvirt/qemu.conf ]; then
        cp /etc/libvirt/qemu.conf /etc/libvirt/qemu.conf.bak
        # Uncomment and set user/group if needed
        # sed -i 's/#user = "root"/user = "root"/' /etc/libvirt/qemu.conf
        # sed -i 's/#group = "root"/group = "root"/' /etc/libvirt/qemu.conf
    fi

    # Configure default network
    log_info "Configuring default network..."
    # Check if default network already exists
    if virsh net-list --all | grep -q "default"; then
        log_info "Default network already exists, skipping creation..."
        virsh net-autostart default 2>/dev/null || true
        if ! virsh net-list | grep -q "default.*active"; then
            virsh net-start default 2>/dev/null || true
        fi
    else
        virsh net-define /dev/stdin <<EOF
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:60:70:80'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
        virsh net-autostart default 2>/dev/null || true
        virsh net-start default 2>/dev/null || true
    fi

    # Restart libvirt
    log_info "Restarting libvirt service..."
    case "$DISTRO_FAMILY" in
        alpine)
            rc-service libvirtd restart
            ;;
        *)
            systemctl restart libvirtd
            ;;
    esac
}

# Configure Cockpit web panel
configure_cockpit() {
    log_info "🌐 Configuring Cockpit web panel..."

    # Check if Cockpit is installed
    if ! command -v cockpit-ws >/dev/null 2>&1; then
        log_warn "Cockpit not available on this distribution"
        log_warn "You can use virt-manager for GUI management instead"
        return
    fi

    # Create Cockpit configuration directory
    mkdir -p /etc/systemd/system/cockpit.socket.d/

    # Configure Cockpit to listen on specified port
    cat > /etc/systemd/system/cockpit.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=127.0.0.1:$COCKPIT_PORT
EOF

    # Configure Cockpit for localhost only
    cat > /etc/cockpit/cockpit.conf <<EOF
[WebService]
Origins = http://127.0.0.1:$COCKPIT_PORT http://localhost:$COCKPIT_PORT
ProtocolHeader = X-Forwarded-Proto
AllowUnencrypted = true

[Session]
Banner = /etc/cockpit/banner.txt
EOF

    # Create welcome banner
    cat > /etc/cockpit/banner.txt <<EOF
QEMU/KVM Virtualization Management Panel
Repository: $REPO_URL
Access URL: http://127.0.0.1:$COCKPIT_PORT
EOF

    # Enable and start Cockpit
    log_info "🚀 Starting Cockpit service on port $COCKPIT_PORT..."
    systemctl daemon-reload
    systemctl enable --now cockpit.socket

    # Add firewall rule if firewall is active
    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active firewalld >/dev/null 2>&1; then
            log_info "Configuring firewall..."
            firewall-cmd --permanent --zone=public --add-port=$COCKPIT_PORT/tcp
            firewall-cmd --reload
        fi
    elif command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            log_info "Configuring UFW firewall..."
            ufw allow from 127.0.0.1 to any port $COCKPIT_PORT
        fi
    fi
}

# Create helper scripts
create_helper_scripts() {
    log_info "📝 Creating helper scripts..."

    # Create VM creation helper
    cat > /usr/local/bin/qemu-create-vm <<'EOF'
#!/bin/sh
# Helper script to create a new VM

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <vm-name> <disk-size-GB> [iso-path]"
    echo "Example: $0 ubuntu-vm 20 /path/to/ubuntu.iso"
    exit 1
fi

VM_NAME="$1"
DISK_SIZE="$2"
ISO_PATH="$3"

# Create disk
qemu-img create -f qcow2 "/var/lib/libvirt/images/${VM_NAME}.qcow2" "${DISK_SIZE}G"

# Build virt-install command
VIRT_CMD="virt-install --name ${VM_NAME}"
VIRT_CMD="$VIRT_CMD --memory 2048"
VIRT_CMD="$VIRT_CMD --vcpus 2"
VIRT_CMD="$VIRT_CMD --disk /var/lib/libvirt/images/${VM_NAME}.qcow2"
VIRT_CMD="$VIRT_CMD --network network=default"
VIRT_CMD="$VIRT_CMD --graphics vnc"
VIRT_CMD="$VIRT_CMD --console pty,target_type=serial"
VIRT_CMD="$VIRT_CMD --boot uefi"
VIRT_CMD="$VIRT_CMD --cpu host-passthrough"
VIRT_CMD="$VIRT_CMD --features kvm_hidden=on"

if [ -n "$ISO_PATH" ]; then
    VIRT_CMD="$VIRT_CMD --cdrom $ISO_PATH"
else
    VIRT_CMD="$VIRT_CMD --pxe"
fi

echo "Creating VM: $VM_NAME"
eval $VIRT_CMD
EOF
    chmod +x /usr/local/bin/qemu-create-vm

    # Create VM management helper
    cat > /usr/local/bin/qemu-manage <<'EOF'
#!/bin/sh
# VM Management Helper

case "$1" in
    list)
        virsh list --all
        ;;
    start)
        virsh start "$2"
        ;;
    stop)
        virsh shutdown "$2"
        ;;
    force-stop)
        virsh destroy "$2"
        ;;
    delete)
        virsh destroy "$2" 2>/dev/null
        virsh undefine "$2" --remove-all-storage
        ;;
    info)
        virsh dominfo "$2"
        ;;
    *)
        echo "Usage: $0 {list|start|stop|force-stop|delete|info} [vm-name]"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/local/bin/qemu-manage
}

# Verify installation
verify_installation() {
    log_info "🔍 Verifying installation..."

    # Check KVM module
    if lsmod | grep -q kvm; then
        log_info "✓ KVM module loaded"
    else
        log_error "✗ KVM module not loaded"
    fi

    # Check libvirt
    if systemctl is-active libvirtd >/dev/null 2>&1 || rc-service libvirtd status >/dev/null 2>&1; then
        log_info "✓ Libvirt service running"
    else
        log_error "✗ Libvirt service not running"
    fi

    # Check QEMU
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        log_info "✓ QEMU installed"
    else
        log_error "✗ QEMU not found"
    fi

    # Check Cockpit
    if systemctl is-active cockpit.socket >/dev/null 2>&1; then
        log_info "✓ Cockpit web panel running on http://127.0.0.1:$COCKPIT_PORT"
    else
        log_warn "! Cockpit not running (may not be available on this distro)"
    fi

    # Check nested virtualization
    if [ "$CPU_VENDOR" = "intel" ]; then
        if [ -f /sys/module/kvm_intel/parameters/nested ]; then
            NESTED=$(cat /sys/module/kvm_intel/parameters/nested)
            if [ "$NESTED" = "Y" ] || [ "$NESTED" = "1" ]; then
                log_info "✓ Nested virtualization enabled"
            fi
        fi
    else
        if [ -f /sys/module/kvm_amd/parameters/nested ]; then
            NESTED=$(cat /sys/module/kvm_amd/parameters/nested)
            if [ "$NESTED" = "1" ]; then
                log_info "✓ Nested virtualization enabled"
            fi
        fi
    fi
}

# Main installation flow
main() {
    cat <<EOF
╔══════════════════════════════════════╗
║  🚀 QEMU+Libvirt Virtualization      ║
║      Installation Wizard              ║
╚══════════════════════════════════════╝
📦 Repository: $REPO_URL

EOF

    check_root
    detect_distro
    check_virtualization
    get_packages
    install_packages
    enable_nested_virtualization
    configure_libvirt
    configure_cockpit
    create_helper_scripts
    verify_installation

    cat <<EOF

╔══════════════════════════════════════╗
║    ✅ Installation Complete!         ║
╚══════════════════════════════════════╝

🌐 Web Panel: http://127.0.0.1:$COCKPIT_PORT
   (Login with your system credentials)

🖥️  GUI Management: virt-manager
   (Run 'virt-manager' in terminal or desktop)

📋 Helper Commands:
   • qemu-create-vm <name> <disk-GB> [iso]  - Create new VM
   • qemu-manage list                        - List all VMs
   • qemu-manage start <vm>                  - Start a VM
   • qemu-manage stop <vm>                   - Stop a VM
   • virsh                                   - Advanced CLI
   • virt-manager                            - GUI Manager

📦 Repository: $REPO_URL

EOF
}

# Run main function
main "$@"