#!/bin/sh
# QEMU+Libvirt Virtualization Environment Installer
# Repository: github.com/scriptmgr/qemu
# POSIX-compliant script for multi-distro, headless server deployments

set -e

# ---------------------------------------------------------------------------
# Respect NO_COLOR (https://no-color.org/)
# ---------------------------------------------------------------------------
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ]; then
    INSTALL_SH_RED=''
    INSTALL_SH_GREEN=''
    INSTALL_SH_YELLOW=''
    INSTALL_SH_NC=''
else
    INSTALL_SH_RED='\033[0;31m'
    INSTALL_SH_GREEN='\033[0;32m'
    INSTALL_SH_YELLOW='\033[1;33m'
    INSTALL_SH_NC='\033[0m'
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
INSTALL_SH_REPO_URL="https://github.com/scriptmgr/qemu"

# Global state set by detect_distro / check_virtualization
INSTALL_SH_DISTRO_ID=""
INSTALL_SH_DISTRO_NAME=""
INSTALL_SH_DISTRO_FAMILY=""
INSTALL_SH_PKG_MANAGER=""
INSTALL_SH_PKG_UPDATE=""
INSTALL_SH_PKG_INSTALL=""
INSTALL_SH_PACKAGES=""
INSTALL_SH_CPU_VENDOR="unknown"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
__log_info() {
    printf "${INSTALL_SH_GREEN}[INFO]${INSTALL_SH_NC} %s\n" "$1"
}

__log_error() {
    printf "${INSTALL_SH_RED}[ERROR]${INSTALL_SH_NC} %s\n" "$1" >&2
}

__log_warn() {
    printf "${INSTALL_SH_YELLOW}[WARN]${INSTALL_SH_NC} %s\n" "$1"
}

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
__check_root() {
    if [ "$(id -u)" != "0" ]; then
        __log_error "This script must be run as root"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Detect Linux distribution
# ---------------------------------------------------------------------------
__detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        INSTALL_SH_DISTRO_ID="$ID"
        INSTALL_SH_DISTRO_NAME="$NAME"
    elif [ -f /etc/redhat-release ]; then
        INSTALL_SH_DISTRO_ID="rhel"
        INSTALL_SH_DISTRO_NAME="Red Hat Enterprise Linux"
    elif [ -f /etc/debian_version ]; then
        INSTALL_SH_DISTRO_ID="debian"
        INSTALL_SH_DISTRO_NAME="Debian"
    else
        __log_error "Cannot detect Linux distribution"
        exit 1
    fi

    # Normalize distro IDs to a family
    case "$INSTALL_SH_DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            INSTALL_SH_DISTRO_FAMILY="debian"
            INSTALL_SH_PKG_MANAGER="apt-get"
            INSTALL_SH_PKG_UPDATE="apt-get update"
            INSTALL_SH_PKG_INSTALL="apt-get install -y"
            ;;
        fedora|rhel|centos|rocky|almalinux|ol)
            INSTALL_SH_DISTRO_FAMILY="rhel"
            if command -v dnf >/dev/null 2>&1; then
                INSTALL_SH_PKG_MANAGER="dnf"
                INSTALL_SH_PKG_UPDATE="dnf check-update || true"
                INSTALL_SH_PKG_INSTALL="dnf install -y"
            else
                INSTALL_SH_PKG_MANAGER="yum"
                INSTALL_SH_PKG_UPDATE="yum check-update || true"
                INSTALL_SH_PKG_INSTALL="yum install -y"
            fi
            ;;
        arch|manjaro|endeavouros)
            INSTALL_SH_DISTRO_FAMILY="arch"
            INSTALL_SH_PKG_MANAGER="pacman"
            INSTALL_SH_PKG_UPDATE="pacman -Sy"
            INSTALL_SH_PKG_INSTALL="pacman -S --noconfirm"
            ;;
        opensuse*|sles)
            INSTALL_SH_DISTRO_FAMILY="suse"
            INSTALL_SH_PKG_MANAGER="zypper"
            INSTALL_SH_PKG_UPDATE="zypper refresh"
            INSTALL_SH_PKG_INSTALL="zypper install -y"
            ;;
        alpine)
            INSTALL_SH_DISTRO_FAMILY="alpine"
            INSTALL_SH_PKG_MANAGER="apk"
            INSTALL_SH_PKG_UPDATE="apk update"
            INSTALL_SH_PKG_INSTALL="apk add"
            ;;
        *)
            __log_error "Unsupported distribution: $INSTALL_SH_DISTRO_ID"
            exit 1
            ;;
    esac

    __log_info "Detected: $INSTALL_SH_DISTRO_NAME ($INSTALL_SH_DISTRO_ID) — family: $INSTALL_SH_DISTRO_FAMILY"
}

# ---------------------------------------------------------------------------
# Package lists — headless server, no GUI tools
# ---------------------------------------------------------------------------
__get_packages() {
    case "$INSTALL_SH_DISTRO_FAMILY" in
        debian)
            # Core hypervisor
            INSTALL_SH_PACKAGES="qemu-system-x86 qemu-kvm qemu-utils qemu-block-extra"
            # Libvirt daemon + CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES libvirt-daemon libvirt-daemon-system"
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES libvirt-clients libvirt-daemon-driver-qemu"
            # Networking (NAT/bridge/DHCP for libvirt networks)
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES bridge-utils dnsmasq-base nftables"
            # UEFI firmware + KVM capability check
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES ovmf cpu-checker"
            # VM provisioning CLI (no GUI)
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES virtinst"
            # Cloud-init: host tooling to build NoCloud seed ISOs
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES cloud-utils cloud-init genisoimage"
            # Software TPM (required for Secure Boot / Windows 11 VMs)
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES swtpm swtpm-tools"
            # Guest agent, OS info DB, NUMA daemon
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES qemu-guest-agent libosinfo-bin numad"
            ;;
        rhel)
            # Core hypervisor
            INSTALL_SH_PACKAGES="qemu-kvm qemu-img"
            # Libvirt daemon + CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES libvirt libvirt-client libvirt-daemon-kvm"
            # Networking
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES bridge-utils dnsmasq nftables"
            # VM provisioning CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES virt-install"
            # UEFI firmware (package name differs by manager)
            if [ "$INSTALL_SH_PKG_MANAGER" = "dnf" ]; then
                INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES edk2-ovmf"
            else
                INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES OVMF"
            fi
            # Cloud-init tooling
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES cloud-utils genisoimage cloud-init"
            # Software TPM, guest agent, OS info DB, NUMA daemon
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES swtpm swtpm-tools qemu-guest-agent osinfo-db numad"
            ;;
        arch)
            # Core hypervisor — qemu-base covers x86_64/i386; qemu-tools adds qemu-img etc.
            INSTALL_SH_PACKAGES="qemu-base qemu-tools"
            # Libvirt daemon + CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES libvirt"
            # Networking
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES bridge-utils dnsmasq vde2 nftables"
            # UEFI firmware
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES edk2-ovmf"
            # VM provisioning CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES virt-install"
            # Cloud-init tooling (cdrtools provides genisoimage)
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES cloud-init cdrtools"
            # Software TPM, guest agent, OS info DB, NUMA daemon
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES swtpm qemu-guest-agent osinfo-db numad"
            ;;
        suse)
            # Core hypervisor
            INSTALL_SH_PACKAGES="qemu qemu-kvm qemu-tools"
            # Libvirt daemon + CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES libvirt libvirt-daemon libvirt-client"
            # Networking
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES bridge-utils dnsmasq nftables"
            # UEFI firmware
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES ovmf"
            # VM provisioning CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES virt-install"
            # Cloud-init tooling
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES cloud-utils cloud-init genisoimage"
            # Software TPM, guest agent, OS info library, NUMA daemon
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES swtpm swtpm-tools qemu-guest-agent libosinfo numad"
            ;;
        alpine)
            # Core hypervisor
            INSTALL_SH_PACKAGES="qemu-system-x86_64 qemu-img"
            # Libvirt daemon + CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES libvirt libvirt-daemon libvirt-client"
            # Networking (cdrkit provides genisoimage on Alpine)
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES bridge-utils dnsmasq nftables"
            # UEFI firmware
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES ovmf"
            # VM provisioning CLI
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES virt-install"
            # Cloud-init tooling
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES cloud-init cloud-utils cdrkit"
            # Software TPM, guest agent, NUMA daemon
            INSTALL_SH_PACKAGES="$INSTALL_SH_PACKAGES swtpm qemu-guest-agent numad"
            __log_warn "Some packages may not be available in all Alpine channels; ensure 'edge/community' is enabled"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# CPU virtualization support check
# ---------------------------------------------------------------------------
__check_virtualization() {
    __log_info "Checking CPU virtualization support..."

    if [ -f /proc/cpuinfo ]; then
        if grep -qE -- '(vmx|svm)' /proc/cpuinfo; then
            if grep -qE -- 'vmx' /proc/cpuinfo; then
                __log_info "Intel VT-x detected"
                INSTALL_SH_CPU_VENDOR="intel"
            else
                __log_info "AMD-V detected"
                INSTALL_SH_CPU_VENDOR="amd"
            fi
        else
            __log_error "CPU does not support hardware virtualization (no vmx/svm in /proc/cpuinfo)"
            __log_error "Enable VT-x/AMD-V in BIOS/UEFI settings and retry"
            exit 1
        fi
    else
        __log_warn "Cannot read /proc/cpuinfo — skipping virtualization check"
        INSTALL_SH_CPU_VENDOR="unknown"
    fi
}

# ---------------------------------------------------------------------------
# Nested virtualization
# ---------------------------------------------------------------------------
__enable_nested_virtualization() {
    if [ "$INSTALL_SH_CPU_VENDOR" = "unknown" ]; then
        __log_warn "CPU vendor unknown — skipping nested virtualization setup"
        return
    fi

    __log_info "Configuring nested virtualization..."

    # Warn when running inside a VM
    if [ -f /sys/devices/virtual/dmi/id/product_name ]; then
        local INSTALL_SH_PRODUCT
        INSTALL_SH_PRODUCT=""
        read -r INSTALL_SH_PRODUCT < /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true
        case "$INSTALL_SH_PRODUCT" in
            *VirtualBox*|*VMware*|*QEMU*|*KVM*)
                __log_warn "Running inside a virtual machine — nested virtualization may have limited performance"
                ;;
        esac
    fi

    local INSTALL_SH_MODULE INSTALL_SH_NESTED_PARAM INSTALL_SH_NESTED_FILE INSTALL_SH_NESTED_STATUS
    if [ "$INSTALL_SH_CPU_VENDOR" = "intel" ]; then
        INSTALL_SH_MODULE="kvm_intel"
        INSTALL_SH_NESTED_PARAM="nested=1"
        INSTALL_SH_NESTED_FILE="/sys/module/kvm_intel/parameters/nested"
    else
        INSTALL_SH_MODULE="kvm_amd"
        INSTALL_SH_NESTED_PARAM="nested=1"
        INSTALL_SH_NESTED_FILE="/sys/module/kvm_amd/parameters/nested"
    fi

    if lsmod | grep -q -- "^${INSTALL_SH_MODULE}"; then
        __log_info "KVM module already loaded"
        if [ -f "$INSTALL_SH_NESTED_FILE" ]; then
            INSTALL_SH_NESTED_STATUS=$(cat "$INSTALL_SH_NESTED_FILE")
            if [ "$INSTALL_SH_NESTED_STATUS" = "Y" ] || [ "$INSTALL_SH_NESTED_STATUS" = "1" ]; then
                __log_info "Nested virtualization already enabled"
            else
                __log_info "Enabling nested virtualization..."
                rmmod "$INSTALL_SH_MODULE" 2>/dev/null || true
                modprobe "$INSTALL_SH_MODULE" "$INSTALL_SH_NESTED_PARAM"
            fi
        fi
    else
        __log_info "Loading KVM module with nested virtualization..."
        modprobe "$INSTALL_SH_MODULE" "$INSTALL_SH_NESTED_PARAM"
    fi

    # Persist across reboots (idempotent — overwrite the file)
    __log_info "Persisting nested virtualization config..."
    printf 'options %s %s\n' "$INSTALL_SH_MODULE" "$INSTALL_SH_NESTED_PARAM" \
        > "/etc/modprobe.d/kvm-nested.conf"

    # Verify
    if [ -f "$INSTALL_SH_NESTED_FILE" ]; then
        INSTALL_SH_NESTED_STATUS=$(cat "$INSTALL_SH_NESTED_FILE")
        if [ "$INSTALL_SH_NESTED_STATUS" = "Y" ] || [ "$INSTALL_SH_NESTED_STATUS" = "1" ]; then
            __log_info "Nested virtualization enabled for ${INSTALL_SH_CPU_VENDOR}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------
__install_packages() {
    __log_info "Updating package repositories..."
    # shellcheck disable=SC2086
    eval "$INSTALL_SH_PKG_UPDATE"

    __log_info "Installing virtualization packages..."
    # shellcheck disable=SC2086
    $INSTALL_SH_PKG_INSTALL $INSTALL_SH_PACKAGES

    # Service enablement per distro
    case "$INSTALL_SH_DISTRO_FAMILY" in
        debian)
            systemctl enable --now libvirtd
            ;;
        rhel)
            systemctl enable --now libvirtd
            if command -v getenforce >/dev/null 2>&1; then
                if [ "$(getenforce)" != "Disabled" ]; then
                    __log_info "Configuring SELinux booleans for virtualization..."
                    setsebool -P virt_use_nfs 1 2>/dev/null || true
                    setsebool -P virt_use_samba 1 2>/dev/null || true
                fi
            fi
            ;;
        arch)
            systemctl enable --now libvirtd
            systemctl enable --now virtlogd
            ;;
        suse)
            systemctl enable --now libvirtd
            ;;
        alpine)
            rc-update add libvirtd
            rc-service libvirtd start
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Configure libvirt (idempotent — uses a sentinel comment)
# ---------------------------------------------------------------------------
__configure_libvirt() {
    __log_info "Configuring libvirt..."

    local INSTALL_SH_CONF="/etc/libvirt/libvirtd.conf"
    local INSTALL_SH_SENTINEL="# scriptmgr/qemu managed config"

    if [ -f "$INSTALL_SH_CONF" ]; then
        # Back up once; never overwrite an existing backup
        if [ ! -f "${INSTALL_SH_CONF}.bak" ]; then
            cp "$INSTALL_SH_CONF" "${INSTALL_SH_CONF}.bak"
        fi

        # Append our block only if it has not already been written
        if ! grep -q -- "$INSTALL_SH_SENTINEL" "$INSTALL_SH_CONF"; then
            cat >> "$INSTALL_SH_CONF" <<EOF

${INSTALL_SH_SENTINEL}
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
unix_sock_ro_perms = "0777"
unix_sock_dir = "/var/run/libvirt"
auth_unix_ro = "none"
auth_unix_rw = "none"
EOF
        fi
    fi

    # Default NAT network
    __log_info "Configuring default libvirt network..."
    if virsh net-list --all | grep -q -- "default"; then
        __log_info "Default network already exists — ensuring it is active and set to autostart"
        virsh net-autostart default 2>/dev/null || true
        if ! virsh net-list | grep -q -- "default.*active"; then
            virsh net-start default 2>/dev/null || true
        fi
    else
        virsh net-define /dev/stdin <<'NETXML'
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
NETXML
        virsh net-autostart default 2>/dev/null || true
        virsh net-start default 2>/dev/null || true
    fi

    # Restart libvirt to pick up config changes
    __log_info "Restarting libvirt service..."
    case "$INSTALL_SH_DISTRO_FAMILY" in
        alpine)
            rc-service libvirtd restart
            ;;
        *)
            systemctl restart libvirtd
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper scripts
# ---------------------------------------------------------------------------
__create_helper_scripts() {
    __log_info "Creating helper scripts..."

    # -- qemu-create-vm: create a VM from an ISO or via PXE -------------------
    cat > /usr/local/bin/qemu-create-vm <<'SCRIPT'
#!/bin/sh
# Create a new KVM VM from an ISO or PXE boot (headless)
set -e

if [ "$#" -lt 2 ]; then
    printf 'Usage: %s <vm-name> <disk-size-GB> [iso-path]\n' "$0"
    printf 'Example: %s debian-srv 20 /var/lib/libvirt/images/debian.iso\n' "$0"
    exit 1
fi

VM_NAME="$1"
DISK_SIZE="$2"
ISO_PATH="${3:-}"
IMAGE_DIR="/var/lib/libvirt/images"

# Create disk image
qemu-img create -f qcow2 "${IMAGE_DIR}/${VM_NAME}.qcow2" "${DISK_SIZE}G"

if [ -n "$ISO_PATH" ]; then
    virt-install \
        --name "$VM_NAME" \
        --memory 2048 \
        --vcpus 2 \
        --disk "${IMAGE_DIR}/${VM_NAME}.qcow2" \
        --cdrom "$ISO_PATH" \
        --network network=default \
        --graphics vnc,listen=127.0.0.1 \
        --console pty,target_type=serial \
        --boot uefi \
        --cpu host-passthrough \
        --features kvm_hidden=on \
        --os-variant detect=on,require=off \
        --noautoconsole
else
    virt-install \
        --name "$VM_NAME" \
        --memory 2048 \
        --vcpus 2 \
        --disk "${IMAGE_DIR}/${VM_NAME}.qcow2" \
        --pxe \
        --network network=default \
        --graphics vnc,listen=127.0.0.1 \
        --console pty,target_type=serial \
        --boot uefi \
        --cpu host-passthrough \
        --features kvm_hidden=on \
        --os-variant detect=on,require=off \
        --noautoconsole
fi

printf 'VM %s created.\n' "$VM_NAME"
printf '  Serial console : virsh console %s\n' "$VM_NAME"
printf '  VNC display    : virsh vncdisplay %s\n' "$VM_NAME"
printf '  SSH tunnel     : ssh -L 5900:127.0.0.1:<port> user@host  then connect VNC to localhost:5900\n'
SCRIPT
    chmod +x /usr/local/bin/qemu-create-vm

    # -- qemu-cloudinit-vm: create a VM from a cloud image with cloud-init ----
    cat > /usr/local/bin/qemu-cloudinit-vm <<'SCRIPT'
#!/bin/sh
# Create a KVM VM from a cloud image (qcow2) with a cloud-init NoCloud seed ISO
set -e

if [ "$#" -lt 3 ]; then
    printf 'Usage: %s <vm-name> <base-image.qcow2> <userdata.yaml> [disk-size-GB]\n' "$0"
    printf 'Example: %s web01 /var/lib/libvirt/images/ubuntu-22.04.qcow2 userdata.yaml 20\n' "$0"
    exit 1
fi

VM_NAME="$1"
BASE_IMAGE="$2"
USERDATA="$3"
DISK_SIZE="${4:-20}"
IMAGE_DIR="/var/lib/libvirt/images"
VM_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
SEED_ISO="${IMAGE_DIR}/${VM_NAME}-seed.iso"

# Create a thin-provisioned overlay on top of the base image
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$VM_DISK" "${DISK_SIZE}G"

# Build the NoCloud seed ISO (requires cloud-utils)
cloud-localds "$SEED_ISO" "$USERDATA"

virt-install \
    --name "$VM_NAME" \
    --memory 2048 \
    --vcpus 2 \
    --disk "$VM_DISK" \
    --disk "${SEED_ISO},device=cdrom,readonly=on" \
    --network network=default \
    --graphics vnc,listen=127.0.0.1 \
    --console pty,target_type=serial \
    --boot uefi \
    --cpu host-passthrough \
    --os-variant detect=on,require=off \
    --import \
    --noautoconsole

printf 'VM %s created.\n' "$VM_NAME"
printf '  Serial console : virsh console %s\n' "$VM_NAME"
printf '  VNC display    : virsh vncdisplay %s\n' "$VM_NAME"
printf '  SSH tunnel     : ssh -L 5900:127.0.0.1:<port> user@host  then connect VNC to localhost:5900\n'
printf '  Remove seed ISO after first boot: virsh change-media %s sda --eject\n' "$VM_NAME"
SCRIPT
    chmod +x /usr/local/bin/qemu-cloudinit-vm

    # -- qemu-manage: lifecycle management ------------------------------------
    cat > /usr/local/bin/qemu-manage <<'SCRIPT'
#!/bin/sh
# VM lifecycle management helper

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
        virsh destroy "$2" 2>/dev/null || true
        virsh undefine "$2" --remove-all-storage
        ;;
    info)
        virsh dominfo "$2"
        ;;
    console)
        virsh console "$2"
        ;;
    *)
        printf 'Usage: %s {list|start|stop|force-stop|delete|info|console} [vm-name]\n' "$0"
        exit 1
        ;;
esac
SCRIPT
    chmod +x /usr/local/bin/qemu-manage
}

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
__verify_installation() {
    __log_info "Verifying installation..."

    if grep -q -- "^kvm" /proc/modules 2>/dev/null; then
        __log_info "KVM module loaded"
    else
        __log_error "KVM module not loaded"
    fi

    if systemctl is-active libvirtd >/dev/null 2>&1 || rc-service libvirtd status >/dev/null 2>&1; then
        __log_info "libvirtd service running"
    else
        __log_error "libvirtd service not running"
    fi

    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        __log_info "QEMU installed: $(qemu-system-x86_64 --version | head -n 1)"
    else
        __log_error "qemu-system-x86_64 not found"
    fi

    if command -v virsh >/dev/null 2>&1; then
        __log_info "virsh available"
    else
        __log_error "virsh not found"
    fi

    if command -v cloud-localds >/dev/null 2>&1; then
        __log_info "cloud-localds available (cloud-init seed ISO creation)"
    else
        __log_warn "cloud-localds not found — cloud-utils may not have installed correctly"
    fi

    if command -v swtpm >/dev/null 2>&1; then
        __log_info "swtpm available (software TPM for Secure Boot / Windows 11)"
    else
        __log_warn "swtpm not found — software TPM unavailable"
    fi

    if [ "$INSTALL_SH_CPU_VENDOR" = "intel" ]; then
        if [ -f /sys/module/kvm_intel/parameters/nested ]; then
            local INSTALL_SH_NESTED
            INSTALL_SH_NESTED=$(cat /sys/module/kvm_intel/parameters/nested)
            if [ "$INSTALL_SH_NESTED" = "Y" ] || [ "$INSTALL_SH_NESTED" = "1" ]; then
                __log_info "Nested virtualization enabled (Intel)"
            fi
        fi
    elif [ "$INSTALL_SH_CPU_VENDOR" = "amd" ]; then
        if [ -f /sys/module/kvm_amd/parameters/nested ]; then
            local INSTALL_SH_NESTED
            INSTALL_SH_NESTED=$(cat /sys/module/kvm_amd/parameters/nested)
            if [ "$INSTALL_SH_NESTED" = "1" ]; then
                __log_info "Nested virtualization enabled (AMD)"
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
__main() {
    printf '╔══════════════════════════════════════╗\n'
    printf '║  QEMU+Libvirt Virtualization         ║\n'
    printf '║  Headless Installation Wizard         ║\n'
    printf '╚══════════════════════════════════════╝\n'
    printf 'Repository: %s\n\n' "$INSTALL_SH_REPO_URL"

    __check_root
    __detect_distro
    __check_virtualization
    __get_packages
    __install_packages
    __enable_nested_virtualization
    __configure_libvirt
    __create_helper_scripts
    __verify_installation

    printf '\n'
    printf '╔══════════════════════════════════════╗\n'
    printf '║  Installation Complete               ║\n'
    printf '╚══════════════════════════════════════╝\n'
    printf '\n'
    printf 'Helper commands installed:\n'
    printf '  qemu-create-vm <name> <disk-GB> [iso]      Create VM from ISO or PXE\n'
    printf '  qemu-cloudinit-vm <name> <img> <ud> [GB]   Create VM from cloud image\n'
    printf '  qemu-manage list|start|stop|delete|info    VM lifecycle management\n'
    printf '  virsh                                       Full libvirt CLI\n'
    printf '\n'
    printf 'Repository: %s\n' "$INSTALL_SH_REPO_URL"
}

__main "$@"
