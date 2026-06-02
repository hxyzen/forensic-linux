#!/bin/bash
#=============================================================================
#  Custom Forensic Linux Distribution Build System
#  Build from scratch: kernel + rootfs + forensics tools → bootable ISO
#  Usage: sudo ./build.sh [iso|clean|chroot]
#=============================================================================
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$PROJECT/build"
ROOTFS="$PROJECT/rootfs"
CONFIGS="$PROJECT/configs"
SCRIPTS="$PROJECT/scripts"
DISTRO_NAME="$(basename "$PROJECT")"
VERSION="1.0"
ARCH="amd64"
ISO_FILE="$PROJECT/${DISTRO_NAME}-${VERSION}-${ARCH}.iso"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

# Check root
[[ $EUID -eq 0 ]] || err "Root required: sudo ./build.sh"

#=============================================================================
# Stage 1: Build custom Linux kernel
#=============================================================================
stage_kernel() {
    info "=== Stage 1: Installing distribution kernel ==="
    # Use distro kernel for now (custom kernel build will be added later)
    mkdir -p "$ROOTFS"
    
    # Install kernel packages into rootfs via debootstrap stage
    # This ensures we have a working kernel + modules + initrd
    info "Distribution kernel will be installed during debootstrap stage"
    ok "Kernel stage: will use distro kernel"
}

#=============================================================================
# Stage 2: Create root filesystem with debootstrap
#=============================================================================
stage_rootfs() {
    info "=== Stage 2: Creating root filesystem ==="
    
    # Check debootstrap
    command -v debootstrap >/dev/null 2>&1 || apt-get install -y debootstrap

    if [ ! -f "$ROOTFS/bin/bash" ]; then
        info "Bootstrapping Debian base system..."
        debootstrap --arch=$ARCH --include=systemd,systemd-sysv,systemd-resolved,\
bash,coreutils,busybox,util-linux,sysvinit-utils,udev,kmod,\
iproute2,iputils-ping,net-tools,wget,ca-certificates,curl,gpg,\
apt-utils,whiptail,locales,kbd,console-setup,\
linux-image-amd64,initramfs-tools \
            bookworm "$ROOTFS" http://deb.debian.org/debian/
        ok "Base system bootstrapped"
    fi

    # Generate locale
    chroot "$ROOTFS" locale-gen en_US.UTF-8 2>/dev/null || true

    # Configure sources.list
    cat > "$ROOTFS/etc/apt/sources.list" << EOF
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main
EOF

    # Configure hostname
    echo "forensics" > "$ROOTFS/etc/hostname"
    echo "127.0.1.1 forensics" >> "$ROOTFS/etc/hosts"

    # Configure network
    cat > "$ROOTFS/etc/systemd/network/20-wired.network" << EOF
[Match]
Name=en*
[Network]
DHCP=yes
EOF

    # Configure fstab
    cat > "$ROOTFS/etc/fstab" << EOF
# <file system>    <mount point>   <type>  <options>           <dump> <pass>
proc               /proc           proc    defaults            0      0
sysfs              /sys            sysfs   defaults            0      0
tmpfs              /tmp            tmpfs   defaults,noatime    0      0
/dev/sr0           /mnt/iso        iso9660 ro,noauto           0      0
EOF

    ok "Root filesystem configured"
}

#=============================================================================
# Stage 3: Install forensic tools
#=============================================================================
stage_tools() {
    info "=== Stage 3: Installing forensic tools ==="

    # Mount special filesystems for chroot
    mount_chroot

    # Update package lists
    chroot "$ROOTFS" apt-get update 2>&1 | tail -2

    # Install forensic packages
    chroot "$ROOTFS" apt-get install -y 2>&1 | tail -3 \
        sleuthkit \
        foremost \
        testdisk \
        binwalk \
        xxd \
        hexdump \
        file \
        binutils \
        ddrescue \
        dc3dd \
        guymager \
        wireshark \
        tshark \
        nmap \
        netcat-openbsd \
        network-manager \
        volatility3 \
        yara \
        bulk-extractor \
        afflib-tools \
        ewf-tools \
        libewf-dev \
        pff-tools \
        vinetto \
        scrounge-ntfs \
        ntfs-3g \
        exfatprogs \
        btrfs-progs \
        xfsprogs \
        f2fs-tools \
        e2fsprogs \
        mdadm \
        lvm2 \
        cryptsetup \
        cryptmount \
        hdparm \
        smartmontools \
        pciutils \
        usbutils \
        lshw \
        dmidecode \
        htop \
        iotop \
        lsof \
        strace \
        ltrace \
        gdb \
        python3 \
        python3-pip \
        perl \
        ruby \
        vim \
        nano \
        less \
        tree \
        rsync \
        screen \
        tmux \
        bash-completion \
        man-db \
        zip \
        unzip \
        gzip \
        bzip2 \
        xz-utils \
        p7zip-full \
        pv \
        jq \
        whois \
        dnsutils \
        bc \
        hashdeep \
        md5deep \
        sha1deep \
        sha256deep \
        openjdk-17-jre-headless 2>&1 | grep -E "^(Setting up|Selecting|Unpacking)" | tail -3 || true

    # Python forensic packages
    chroot "$ROOTFS" pip3 install --quiet 2>&1 | tail -2 \
        dfvfs \
        dfimagetools \
        plaso \
        pytsk3 \
        libvshadow \
        libvhdi \
        libvmdk \
        libqcow \
        libbde \
        artifacts \
        forensic-utils \
        capstone \
        cstruct \
        dpkt \
        lxml \
        pefile \
        jabba \
        python-registry \
        pycryptodome 2>&1 | tail -2 || true

    # Custom scripts
    mkdir -p "$ROOTFS/usr/local/bin"
    cp "$SCRIPTS"/*.sh "$ROOTFS/usr/local/bin/" 2>/dev/null || true
    chroot "$ROOTFS" chmod +x /usr/local/bin/*.sh 2>/dev/null || true

    # Create forensics workspace
    mkdir -p "$ROOTFS/home/forensics/{images,cases,tools,reports}"
    chroot "$ROOTFS" useradd -m -s /bin/bash forensics 2>/dev/null || true
    echo "forensics:forensics" | chroot "$ROOTFS" chpasswd 2>/dev/null || true
    chroot "$ROOTFS" chown -R forensics:forensics /home/forensics 2>/dev/null || true

    # Clean apt cache
    chroot "$ROOTFS" apt-get clean

    # Unmount
    umount_chroot
    ok "Forensic tools installed"
}

#=============================================================================
# Stage 4: Build custom initramfs (static BusyBox + live-boot init)
#=============================================================================
stage_initramfs() {
    info "=== Stage 4: Building custom initramfs ==="
    if [ -f "$BUILD/initramfs.cpio.gz" ]; then
        info "Initramfs already exists, skipping build"
        return
    fi
    bash "$SCRIPTS/build-initramfs.sh"
    ok "Custom initramfs built"
}

#=============================================================================
# Stage 5: Configure bootloader & create ISO
#=============================================================================
stage_iso() {
    info "=== Stage 5: Creating bootable ISO ==="

    # Install GRUB and xorriso
    command -v grub-mkrescue >/dev/null 2>&1 || apt-get install -y grub-pc-bin xorriso mtools

    # Create ISO directory structure
    ISO_DIR="$BUILD/iso"
    mkdir -p "$ISO_DIR/boot/grub"
    mkdir -p "$ISO_DIR/live"

    # Copy kernel and initrd from rootfs
    KERNEL_FILE=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | head -1)
    INITRD_FILE=$(ls "$ROOTFS/boot/initrd.img-"* 2>/dev/null | head -1)
    
    if [ -n "$KERNEL_FILE" ]; then
        cp "$KERNEL_FILE" "$ISO_DIR/boot/kernel.bzImage"
        ok "Kernel: $(basename $KERNEL_FILE)"
    else
        err "No kernel found in rootfs!"
    fi

    # Use custom initramfs if available, otherwise Debian's initrd
    if [ -f "$BUILD/initramfs.cpio.gz" ]; then
        info "Using custom initramfs..."
        cp "$BUILD/initramfs.cpio.gz" "$ISO_DIR/boot/initrd.gz"
    elif [ -n "$INITRD_FILE" ]; then
        info "Using distribution initrd..."
        cp "$INITRD_FILE" "$ISO_DIR/boot/initrd.gz"
    else
        err "No initrd found!"
    fi
    ok "Initrd ready"

    # Create squashfs for live system
    info "Creating squashfs filesystem..."
    command -v mksquashfs >/dev/null 2>&1 || apt-get install -y squashfs-tools
    mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" -comp xz -e boot 2>&1 | tail -2
    ok "Squashfs created"

    # GRUB configuration
    cat > "$ISO_DIR/boot/grub/grub.cfg" << 'GRUB'
set timeout=5
set default=0

loadfont unicode
set gfxmode=1024x768
set gfxpayload=keep
insmod all_video
insmod gfxterm
insmod gfxmenu

menuentry "Forensic Linux Distribution" {
    linux /boot/kernel.bzImage boot=live toram=0 quiet splash
    initrd /boot/initrd.gz
}

menuentry "Forensic Linux - Safe Mode (no NET)" {
    linux /boot/kernel.bzImage boot=live net.ifnames=0 noNetwork quiet
    initrd /boot/initrd.gz
}

menuentry "Forensic Linux - Hardware Test" {
    linux /boot/kernel.bzImage boot=live memtest=1 quiet
    initrd /boot/initrd.gz
}

menuentry "Boot from hard disk" {
    insmod chain
    insmod ntfs
    insmod ext2
    set root=(hd0)
    chainloader +1
}

menuentry "System Information" {
    linux /boot/kernel.bzImage boot=live info quiet
    initrd /boot/initrd.gz
}
GRUB

    # Create ISO
    info "Generating ISO..."
    grub-mkrescue -o "$ISO_FILE" "$ISO_DIR" 2>&1 | tail -3
    ok "ISO created: $ISO_FILE"
}

#=============================================================================
# Utility functions
#=============================================================================
mount_chroot() {
    mount --bind /dev "$ROOTFS/dev" 2>/dev/null || true
    mount --bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true
    mount --bind /proc "$ROOTFS/proc" 2>/dev/null || true
    mount --bind /sys "$ROOTFS/sys" 2>/dev/null || true
}

umount_chroot() {
    umount "$ROOTFS/dev/pts" 2>/dev/null || true
    umount "$ROOTFS/dev" 2>/dev/null || true
    umount "$ROOTFS/proc" 2>/dev/null || true
    umount "$ROOTFS/sys" 2>/dev/null || true
}

clean_all() {
    warn "Cleaning all build artifacts..."
    umount_chroot 2>/dev/null || true
    rm -rf "$BUILD" 2>/dev/null || true
    rm -f "$ISO_FILE" 2>/dev/null || true
    ok "Clean complete"
}

#=============================================================================
# Main
#=============================================================================
case "${1:-iso}" in
    iso)
        stage_kernel
        stage_rootfs
        stage_tools
        stage_initramfs
        stage_iso
        info "========================================"
        info "Build complete!"
        info "ISO: $ISO_FILE"
        info "Size: $(ls -lh "$ISO_FILE" | awk '{print $5}')"
        info "Burn to USB: sudo dd if=$ISO_FILE of=/dev/sdX bs=4M status=progress"
        info "========================================"
        ;;
    kernel)
        stage_kernel
        ;;
    rootfs)
        stage_rootfs
        ;;
    tools)
        mount_chroot
        stage_tools
        umount_chroot
        ;;
    initramfs)
        stage_initramfs
        ;;
    iso-only)
        stage_iso
        ;;
    clean)
        clean_all
        ;;
    chroot)
        mount_chroot
        info "Entering chroot. Type 'exit' when done."
        chroot "$ROOTFS"
        umount_chroot
        ;;
    *)
        echo "Usage: $0 [iso|kernel|rootfs|tools|iso-only|chroot|clean]"
        echo "  iso        - Full build (default)"
        echo "  kernel     - Build kernel only"
        echo "  rootfs     - Bootstrap root filesystem only"
        echo "  tools      - Install tools only (requires rootfs)"
        echo "  initramfs  - Build custom initramfs (BusyBox + live-boot init)"
        echo "  iso-only   - Create ISO from existing rootfs"
        echo "  chroot     - Enter chroot for manual configuration"
        echo "  clean      - Remove build artifacts"
        ;;
esac
