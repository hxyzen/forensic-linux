#!/bin/bash
#=============================================================================
#  Build custom initramfs for Forensic Linux live-boot
#  Uses static BusyBox + custom init script
#=============================================================================
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$PROJECT/build"
INITRAMFS_DIR="$BUILD/initramfs"
CONFIGS="$PROJECT/configs"
SCRIPTS="$PROJECT/scripts"
ROOTFS="$PROJECT/rootfs"

ARCH="${ARCH:-amd64}"
BUSYBOX_VERSION="1.36.1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || err "Root required for initramfs build"

#=============================================================================
# Stage 1: Build static BusyBox
#=============================================================================
build_busybox() {
    info "Building static BusyBox $BUSYBOX_VERSION..."
    mkdir -p "$BUILD/busybox"
    cd "$BUILD/busybox"

    if [ ! -f busybox-${BUSYBOX_VERSION}.tar.bz2 ]; then
        wget -q --show-progress \
            https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
    fi

    if [ ! -d busybox-${BUSYBOX_VERSION} ]; then
        tar xf busybox-${BUSYBOX_VERSION}.tar.bz2
    fi

    cd busybox-${BUSYBOX_VERSION}

    cp "$CONFIGS/busybox.config" .config
    make olddefconfig
    info "Compiling BusyBox (static)..."
    make -j$(nproc) 2>&1 | tail -3
    make install 2>&1 | tail -3
    ok "BusyBox built: $(./busybox --help 2>&1 | head -1)"
}

#=============================================================================
# Stage 2: Create initramfs directory structure
#=============================================================================
create_initramfs() {
    info "Creating initramfs structure..."
    rm -rf "$INITRAMFS_DIR"
    mkdir -p "$INITRAMFS_DIR"/{bin,sbin,etc,dev,proc,sys,mnt,tmp,root,run,lib/modules}

    # Copy BusyBox
    cp -a "$BUILD/busybox/busybox-${BUSYBOX_VERSION}/_install/"* "$INITRAMFS_DIR/"
    
    # Create additional BusyBox applet symlinks
    cd "$INITRAMFS_DIR/bin"
    for applet in $(./busybox --list 2>/dev/null); do
        [ -L "$applet" ] || [ -f "$applet" ] && continue
        ln -sf busybox "$applet" 2>/dev/null || true
    done
    cd "$INITRAMFS_DIR"
    ok "BusyBox applets installed"
}

#=============================================================================
# Stage 3: Write the init script
#=============================================================================
write_init_script() {
    info "Writing initramfs init script..."

    cat > "$INITRAMFS_DIR/init" << 'INIT_SCRIPT'
#!/bin/busybox sh
#=============================================================================
#  init - Forensic Linux live-boot initramfs
#=============================================================================
set -e

# Export PATH
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount essential filesystems
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev
/bin/busybox mkdir -p /dev/pts
/bin/busybox mount -t devpts none /dev/pts
/bin/busybox mkdir -p /dev/shm
/bin/busybox mount -t tmpfs none /dev/shm
/bin/busybox mount -t tmpfs none /tmp
/bin/busybox mount -t tmpfs none /run

# Populate /dev with mdev
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s

# Set hostname
echo "forensics" > /proc/sys/kernel/hostname

# Parse kernel command line
CMDLINE=$(cat /proc/cmdline)
BOOT_MODE="live"
ROOT_DEV=""
NO_NET=""
DEBUG=""
INFO=""

for param in $CMDLINE; do
    case "$param" in
        boot=live)        BOOT_MODE="live" ;;
        boot=local)       BOOT_MODE="local" ;;
        toram=1|toram)    BOOT_MODE="toram" ;;
        noNetwork)        NO_NET="1" ;;
        debug)            DEBUG="1" ;;
        info)             INFO="1" ;;
        memtest=1)        BOOT_MODE="memtest" ;;
        root=*)           ROOT_DEV="${param#root=}" ;;
    esac
done

# Print boot info
[ -n "$DEBUG" ] && echo "DEBUG: CMDLINE=$CMDLINE"
[ -n "$DEBUG" ] && echo "DEBUG: BOOT_MODE=$BOOT_MODE"

# System information screen
if [ -n "$INFO" ]; then
    echo "============================================"
    echo "  Forensic Linux - System Information"
    echo "============================================"
    echo "  Kernel: $(uname -r)"
    echo "  CPU:    $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2)"
    echo "  RAM:    $(grep MemTotal /proc/meminfo | awk '{print $2, $3}')"
    echo "  Date:   $(date)"
    echo ""
    echo "  PCI Devices:"
    lspci 2>/dev/null | head -10 || cat /sys/devices/pci*/*/device 2>/dev/null
    echo ""
    echo "  Block Devices:"
    for dev in /sys/block/*; do
        [ -e "$dev" ] && echo "    /dev/$(basename $dev)"
    done
    echo ""
    echo "  Kernel Modules:"
    lsmod
    echo "============================================"
    echo "  Press ENTER to continue boot..."
    read dummy
fi

# Memory test mode
if [ "$BOOT_MODE" = "memtest" ]; then
    echo "Running memory test..."
    memtester 100M 1 2>/dev/null || echo "memtester not available"
    echo "Memory test complete. Press ENTER to reboot."
    read dummy
    reboot -f
fi

# Find the live filesystem
find_livefs() {
    local label="$1"
    local sysfs="/sys/class/block"

    # Check /dev/sr* (optical drives) first
    for dev in /dev/sr0 /dev/sr1 /dev/sr2; do
        [ -b "$dev" ] || continue
        echo "Checking $dev..."
        blkid -o value -s LABEL "$dev" 2>/dev/null | grep -qi "$label" && {
            echo "$dev"
            return
        }
        # Try mounting
        mkdir -p /mnt/check
        mount -t iso9660 -o ro "$dev" /mnt/check 2>/dev/null && {
            if [ -f /mnt/check/live/filesystem.squashfs ]; then
                umount /mnt/check 2>/dev/null
                echo "$dev"
                return
            fi
            umount /mnt/check 2>/dev/null
        }
    done

    # Scan USB / SATA devices
    for dev in /dev/sd* /dev/vd* /dev/nvme*; do
        [ -b "$dev" ] || continue
        # Skip partitions that are already mounted
        mount | grep -q "$dev " && continue
        # Check label
        blkid -o value -s LABEL "$dev" 2>/dev/null | grep -qi "$label" && {
            echo "$dev"
            return
        }
        # Try direct mount
        mkdir -p /mnt/check
        mount "$dev" /mnt/check 2>/dev/null && {
            if [ -f /mnt/check/live/filesystem.squashfs ]; then
                umount /mnt/check 2>/dev/null
                echo "$dev"
                return
            fi
            umount /mnt/check 2>/dev/null
        }
    done

    echo ""
}

# Find and mount the boot device
LIVE_DEV=""
LIVE_DEV=$(find_livefs "FORENSICS")

if [ -z "$LIVE_DEV" ] && [ -b "$ROOT_DEV" ]; then
    LIVE_DEV="$ROOT_DEV"
fi

if [ -z "$LIVE_DEV" ]; then
    echo "Forensic Linux live filesystem not found."
    echo "Please insert the Forensic Linux CD/USB."
    echo "Available devices:"
    for dev in /dev/sr* /dev/sd* /dev/vd* /dev/nvme*; do
        [ -b "$dev" ] && echo "  $dev ($(blkid -o value -s LABEL "$dev" 2>/dev/null || echo 'no label'))"
    done
    echo ""
    echo "Type device path or press ENTER to retry:"
    read MANUAL_DEV
    [ -n "$MANUAL_DEV" ] && LIVE_DEV="$MANUAL_DEV"
fi

# Loop until we find it
while [ -z "$LIVE_DEV" ]; do
    echo "Retrying..."
    sleep 2
    LIVE_DEV=$(find_livefs "FORENSICS")
done

[ -n "$DEBUG" ] && echo "DEBUG: Boot device found: $LIVE_DEV"

# Mount boot device
mkdir -p /mnt/bootdev
mount -t auto -o ro "$LIVE_DEV" /mnt/bootdev 2>/dev/null || \
    mount -t iso9660 -o ro "$LIVE_DEV" /mnt/bootdev 2>/dev/null || {
    echo "Failed to mount $LIVE_DEV"
    echo "Trying forcing..."
    mount -o ro "$LIVE_DEV" /mnt/bootdev
}

# Load necessary kernel modules
modprobe squashfs 2>/dev/null || true
modprobe overlay 2>/dev/null || true
modprobe loop 2>/dev/null || true

# Handle different boot modes
case "$BOOT_MODE" in
    toram)
        echo "Copying filesystem to RAM..."
        mkdir -p /mnt/squashfs
        cp -a /mnt/bootdev/live/filesystem.squashfs /tmp/filesystem.squashfs
        umount /mnt/bootdev
        mkdir -p /mnt/squashfs
        mount -t squashfs -o ro,loop /tmp/filesystem.squashfs /mnt/squashfs
        ;;
    *)
        # Mount squashfs
        mkdir -p /mnt/squashfs
        if [ -f /mnt/bootdev/live/filesystem.squashfs ]; then
            mount -t squashfs -o ro,loop /mnt/bootdev/live/filesystem.squashfs /mnt/squashfs
        elif [ -d /mnt/bootdev/live/root ]; then
            # Uncompressed rootfs (for debugging)
            mount --bind /mnt/bootdev/live/root /mnt/squashfs
        else
            # Maybe the whole bootdev is the rootfs
            mount --bind /mnt/bootdev /mnt/squashfs
        fi
        ;;
esac

# Create overlay for writable root
echo "Creating overlay filesystem..."
mkdir -p /mnt/upper
mkdir -p /mnt/work
mkdir -p /mnt/root

mount -t overlay -o lowerdir=/mnt/squashfs,upperdir=/mnt/upper,workdir=/mnt/work \
    overlay /mnt/root

# Move critical filesystems to new root
mount --move /dev /mnt/root/dev
mount --move /proc /mnt/root/proc
mount --move /sys /mnt/root/sys
mount --move /tmp /mnt/root/tmp
mount --move /run /mnt/root/run

# If boot device is still mounted, keep it available at /mnt/iso
mkdir -p /mnt/root/mnt/iso
mount --move /mnt/bootdev /mnt/root/mnt/iso 2>/dev/null || true
mkdir -p /mnt/root/mnt/persistence
mount --move /mnt/upper /mnt/root/mnt/persistence 2>/dev/null || true

# Clean up /mnt
rmdir /mnt/squashfs 2>/dev/null || true
rmdir /mnt/check 2>/dev/null || true

# Switch to new root
echo "Switching to new root filesystem..."
exec switch_root /mnt/root /sbin/init
INIT_SCRIPT

    chmod +x "$INITRAMFS_DIR/init"
    ok "Init script written"
}

#=============================================================================
# Stage 4: Create mdev configuration
#=============================================================================
write_mdev_conf() {
    mkdir -p "$INITRAMFS_DIR/etc"
    cat > "$INITRAMFS_DIR/etc/mdev.conf" << 'MDEV'
# mdev configuration
# Syntax: <device regex> <uid>:<gid> <octal permissions> [=path] [$|*]
# =path: move to path
# *: run cmd after creation
# $: run cmd after removal

# Block devices
sd[a-z][0-9]* 0:0 660 */sbin/mdev.sh
sd[a-z]*       0:0 660 */sbin/mdev.sh
nvme[0-9]n[0-9]p[0-9]* 0:0 660 */sbin/mdev.sh
nvme[0-9]n[0-9] 0:0 660 */sbin/mdev.sh
sr[0-9]        0:0 440 */sbin/mdev.sh
hd[a-z][0-9]*  0:0 660 */sbin/mdev.sh
vd[a-z][0-9]*  0:0 660 */sbin/mdev.sh

# Input
event[0-9].*   0:0 640
mouse[0-9]     0:0 640
kbd            0:0 640

# TTY
tty[0-9]       0:0 600
ttyS[0-9]      0:0 600
console        0:0 600

# Misc
random         0:0 644
urandom        0:0 644
null           0:0 666
zero           0:0 666
full           0:0 666
ptmx           0:0 666
tty            0:0 666
MDEV
}

#=============================================================================
# Stage 5: Create mdev helper script
#=============================================================================
write_mdev_helper() {
    mkdir -p "$INITRAMFS_DIR/sbin"
    cat > "$INITRAMFS_DIR/sbin/mdev.sh" << 'MDEVSH'
#!/bin/busybox sh
# Called by mdev when block devices appear/disappear
[ -n "$DEBUG" ] && echo "mdev: $ACTION $MDEV" > /dev/console
MDEVSH
    chmod +x "$INITRAMFS_DIR/sbin/mdev.sh"
}

#=============================================================================
# Stage 6: Write inittab for emergency shell
#=============================================================================
write_inittab() {
    cat > "$INITRAMFS_DIR/etc/inittab" << 'INITTAB'
# Forensics Linux initramfs inittab
::sysinit:/bin/busybox mount -o remount,rw /
::sysinit:/bin/busybox echo "Forensic Linux - Emergency Initramfs Shell"
::sysinit:/bin/busybox hostname -F /etc/hostname 2>/dev/null
::respawn:-/bin/busybox sh
::restart:/sbin/init
::shutdown:/bin/umount -a -r
INITTAB
}

#=============================================================================
# Stage 7: Create hostname file
#=============================================================================
write_etc_files() {
    echo "forensics" > "$INITRAMFS_DIR/etc/hostname"
    echo "forensics" > "$INITRAMFS_DIR/etc/hostname"
    touch "$INITRAMFS_DIR/etc/fstab"
}

#=============================================================================
# Stage 8: Package the initramfs
#=============================================================================
package_initramfs() {
    info "Packaging initramfs..."
    cd "$INITRAMFS_DIR"
    
    # Create cpio archive
    find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 > "$BUILD/initramfs.cpio.gz"
    
    # Also create uncompressed version for debugging
    find . -print0 | cpio --null -o --format=newc 2>/dev/null > "$BUILD/initramfs.cpio" || true
    
    local size=$(stat -c%s "$BUILD/initramfs.cpio.gz" 2>/dev/null || stat -f%z "$BUILD/initramfs.cpio.gz" 2>/dev/null)
    ok "Initramfs packaged: $BUILD/initramfs.cpio.gz ($(($size/1024)) KB)"
}

#=============================================================================
# Main
#=============================================================================
info "=== Building Forensic Linux Initramfs ==="
build_busybox
create_initramfs
write_init_script
write_mdev_conf
write_mdev_helper
write_inittab
write_etc_files
package_initramfs

info "Initramfs build complete"
info "Kernel + initramfs ready for ISO generation"
