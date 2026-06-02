#!/bin/bash
# Comprehensive file analysis tool
# Usage: file-analyze.sh <file>

if [ $# -lt 1 ]; then
    echo "Usage: $0 <file>"
    exit 1
fi

FILE="$1"
[ -f "$FILE" ] || { echo "File not found: $FILE"; exit 1; }

echo "============================================"
echo "  FILE ANALYSIS: $(basename "$FILE")"
echo "============================================"
echo ""

echo "--- File Info ---"
echo "  Path: $(realpath "$FILE")"
echo "  Size: $(ls -lh "$FILE" | awk '{print $5}')"
echo "  Type: $(file "$FILE")"
echo "  Permissions: $(stat -c '%a %A' "$FILE")"
echo "  Owner: $(stat -c '%U:%G' "$FILE")"
echo "  Created: $(stat -c '%w' "$FILE" 2>/dev/null || echo 'N/A')"
echo "  Modified: $(stat -c '%y' "$FILE")"
echo "  Accessed: $(stat -c '%x' "$FILE")"
echo "  Inode: $(stat -c '%i' "$FILE")"
echo ""

echo "--- Hashes ---"
echo "  MD5:    $(md5sum "$FILE" | cut -d' ' -f1)"
echo "  SHA1:   $(sha1sum "$FILE" | cut -d' ' -f1)"
echo "  SHA256: $(sha256sum "$FILE" | cut -d' ' -f1)"
echo "  SHA512: $(sha512sum "$FILE" | cut -d' ' -f1)"
echo ""

echo "--- Strings Analysis ---"
echo -n "  Printable strings: "
strings "$FILE" | wc -l
echo -n "  URLs: "
strings "$FILE" | grep -Eo 'https?://[^ ]+' | sort -u | wc -l
echo -n "  Emails: "
strings "$FILE" | grep -Eo '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | sort -u | wc -l
echo -n "  IPs: "
strings "$FILE" | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort -u | wc -l
echo ""

echo "--- Binary Analysis ---"
xxd "$FILE" | head -20
echo "  ..."
echo ""

# Check for known file signatures
echo "--- Signature Check ---"
SIG=$(xxd -l 8 "$FILE" | cut -d' ' -f2-3)
case "$SIG" in
    "89504e47"*) echo "  Detected: PNG Image" ;;
    "ffd8ffe0"*|"ffd8ffe1"*) echo "  Detected: JPEG Image" ;;
    "25504446"*) echo "  Detected: PDF Document" ;;
    "504b0304"*) echo "  Detected: ZIP Archive" ;;
    "47494638"*) echo "  Detected: GIF Image" ;;
    "49492a00"*|"4d4d002a"*) echo "  Detected: TIFF Image" ;;
    "424d"*) echo "  Detected: BMP Image" ;;
    *) echo "  Raw hex: $SIG" ;;
esac
echo ""

# EXIF for images
if file "$FILE" | grep -qiE 'image|jpeg|png|tiff'; then
    echo "--- EXIF Data (if available) ---"
    identify -verbose "$FILE" 2>/dev/null | head -40 || true
    echo ""
fi

echo "============================================"
