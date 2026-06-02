#!/bin/bash
# Disk acquisition tool - dd with progress and hash
# Usage: disk-acquire.sh /dev/sdX image.dd

if [ $# -lt 2 ]; then
    echo "Usage: $0 <source> <output>"
    echo "Example: $0 /dev/sdb1 case001/image.dd"
    exit 1
fi

SRC="$1"
OUT="$2"

echo "============================================"
echo "  FORENSIC DISK ACQUISITION"
echo "  Source: $SRC"
echo "  Output: $OUT"
echo "============================================"

# Check source
if [ ! -b "$SRC" ]; then
    echo "ERROR: Source is not a block device: $SRC"
    exit 1
fi

# Confirm
echo "WARNING: This will acquire an image of $SRC"
echo -n "Proceed? (yes/no): "
read CONFIRM
[ "$CONFIRM" = "yes" ] || exit 1

# Create output directory
mkdir -p "$(dirname "$OUT")"

# Get device info
SIZE=$(blockdev --getsize64 "$SRC" 2>/dev/null || echo "0")
echo "Device size: $(numfmt --to=iec $SIZE)"

# Acquire with hash
echo "Acquiring image..."
dc3dd if="$SRC" of="$OUT" hash=sha256 hashwindow=1G log="${OUT}.log" \
    progress=on hof="${OUT}.hash" 2>&1

# Verify
echo "Calculating SHA256..."
sha256sum "$OUT" > "${OUT}.sha256"
echo "SHA256: $(cat ${OUT}.sha256)"

# Info
echo "============================================"
echo "  ACQUISITION COMPLETE"
echo "  Image: $OUT"
echo "  Size: $(ls -lh "$OUT" | awk '{print $5}')"
echo "  Hash: ${OUT}.sha256"
echo "  Log: ${OUT}.log"
echo "============================================"
