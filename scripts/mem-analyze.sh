#!/bin/bash
# Memory analysis toolkit
# Usage: mem-analyze.sh <memory_dump.raw|dump.mem|dump.vmem>

if [ $# -lt 1 ]; then
    echo "Usage: $0 <memory_dump>"
    echo "  Supports: raw, mem, vmem, img, dmp, dump files"
    exit 1
fi

DUMP="$1"
[ -f "$DUMP" ] || { echo "File not found: $DUMP"; exit 1; }

echo "============================================"
echo "  MEMORY ANALYSIS: $(basename "$DUMP")"
echo "============================================"
echo ""

echo "--- File Info ---"
echo "  Size: $(ls -lh "$DUMP" | awk '{print $5}')"
echo "  Type: $(file "$DUMP")"
echo ""

echo "--- Volatility3 Analysis ---"
if command -v vol >/dev/null 2>&1; then
    # Detect profile
    echo "  Detecting profile..."
    vol -f "$DUMP" windows.info 2>/dev/null | head -10 || \
    vol -f "$DUMP" linux.info 2>/dev/null | head -10 || \
    vol -f "$DUMP" mac.info 2>/dev/null | head -10 || \
    echo "  (Profile detection failed)"

    echo ""
    echo "  Processes (top 20):"
    vol -f "$DUMP" windows.pslist 2>/dev/null | head -20 || \
    vol -f "$DUMP" linux.pslist 2>/dev/null | head -20 || \
    echo "  (Process listing failed)"

    echo ""
    echo "  Network connections:"
    vol -f "$DUMP" windows.netscan 2>/dev/null | head -15 || \
    vol -f "$DUMP" linux.netstat 2>/dev/null | head -15 || \
    echo "  (Network scan failed)"
else
    echo "  Volatility3 not found. Install: pip3 install volatility3"
fi

echo ""
echo "--- Strings Analysis ---"
echo -n "  Total strings found: "
strings "$DUMP" | wc -l

echo -n "  URLs extracted: "
strings "$DUMP" | grep -Eo 'https?://[^ ]+' | sort -u > /tmp/mem_urls.txt 2>/dev/null
wc -l < /tmp/mem_urls.txt 2>/dev/null || echo "0"

echo -n "  IP addresses: "
strings "$DUMP" | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort -u > /tmp/mem_ips.txt 2>/dev/null
wc -l < /tmp/mem_ips.txt 2>/dev/null || echo "0"

echo -n "  Credentials (potential): "
strings "$DUMP" | grep -Ei '(password|passwd|pwd|login|username|user)' | sort -u > /tmp/mem_creds.txt 2>/dev/null
wc -l < /tmp/mem_creds.txt 2>/dev/null || echo "0"
echo ""

echo "--- First 100 characters ---"
head -c 100 "$DUMP" | xxd
echo ""

echo "============================================"
echo "  Output files:"
echo "  URLs:  /tmp/mem_urls.txt"
echo "  IPs:   /tmp/mem_ips.txt"
echo "  Creds: /tmp/mem_creds.txt"
echo "============================================"
