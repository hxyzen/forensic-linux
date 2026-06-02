#!/bin/bash
# Secure disk wipe tool
# Usage: wipe-disk.sh /dev/sdX [method]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <device> [method]"
    echo "Methods:"
    echo "  zero    - Single pass zeros (default)"
    echo "  random  - Single pass random"
    echo "  dod     - DoD 5220.22-M (3 passes)"
    echo "  gutmann - Gutmann (35 passes)"
    exit 1
fi

DEV="$1"
METHOD="${2:-zero}"

[ -b "$DEV" ] || { echo "Not a block device: $DEV"; exit 1; }

echo "============================================"
echo "  SECURE DISK WIPE"
echo "  Device: $DEV"
echo "  Method: $METHOD"
echo "============================================"
echo "WARNING: ALL DATA ON $DEV WILL BE DESTROYED!"
echo -n "Type 'erase' to confirm: "
read CONFIRM
[ "$CONFIRM" = "erase" ] || exit 1

SIZE=$(blockdev --getsize64 "$DEV" 2>/dev/null || echo "unknown")

wipe_zero() {
    echo "Zeroing $DEV ($SIZE bytes)..."
    dd if=/dev/zero of="$DEV" bs=4M status=progress
    sync
}

wipe_random() {
    echo "Randomizing $DEV ($SIZE bytes)..."
    dd if=/dev/urandom of="$DEV" bs=4M status=progress
    sync
}

wipe_dod() {
    echo "DOD 5220.22-M wipe (3 passes)..."
    echo "Pass 1/3: Zeros"
    dd if=/dev/zero of="$DEV" bs=4M status=progress
    sync
    echo "Pass 2/3: Ones"
    dd if=/dev/zero of="$DEV" bs=4M status=progress | tr '\0' '\377'
    sync
    echo "Pass 3/3: Random"
    dd if=/dev/urandom of="$DEV" bs=4M status=progress
    sync
}

wipe_gutmann() {
    echo "Gutmann wipe (35 passes)..."
    for i in $(seq 1 35); do
        echo "Pass $i/35..."
        case $((i % 3)) in
            0) dd if=/dev/zero of="$DEV" bs=4M status=none ;;
            1) dd if=/dev/urandom of="$DEV" bs=4M status=none ;;
            2) dd if=/dev/zero of="$DEV" bs=4M status=none | tr '\0' '\377' ;;
        esac
        sync
    done
    echo "Gutmann wipe complete"
}

case "$METHOD" in
    zero)    wipe_zero ;;
    random)  wipe_random ;;
    dod)     wipe_dod ;;
    gutmann) wipe_gutmann ;;
    *)       echo "Unknown method: $METHOD"; exit 1 ;;
esac

echo "============================================"
echo "  WIPE COMPLETE: $DEV"
echo "  Method: $METHOD"
echo "============================================"
