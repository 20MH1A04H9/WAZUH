#!/bin/bash

# Wazuh Indexer Auto Configuration
# Includes:
# - JVM heap tuning
# - nofile limits
# - vm.max_map_count
# - swap disable
# - service restart

set -e

JVM_FILE="/etc/wazuh-indexer/jvm.options"
LIMITS_FILE="/etc/security/limits.conf"
SYSCTL_FILE="/etc/sysctl.conf"

echo "==========================================="
echo "Wazuh Auto Configuration Started"
echo "==========================================="

# ----------------------------------------
# ROOT CHECK
# ----------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run this script as root"
    exit 1
fi

# ----------------------------------------
# FILE CHECK
# ----------------------------------------
if [ ! -f "$JVM_FILE" ]; then
    echo "ERROR: $JVM_FILE not found"
    exit 1
fi

# ----------------------------------------
# DETECT TOTAL RAM
# ----------------------------------------
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')

# Safer heap sizing
if [ "$TOTAL_RAM_GB" -le 2 ]; then
    HEAP="512m"
elif [ "$TOTAL_RAM_GB" -le 4 ]; then
    HEAP="1g"
elif [ "$TOTAL_RAM_GB" -le 8 ]; then
    HEAP="2g"
elif [ "$TOTAL_RAM_GB" -le 16 ]; then
    HEAP="4g"
else
    HEAP="8g"
fi

echo "Detected RAM: ${TOTAL_RAM_GB}GB"
echo "Selected JVM Heap: ${HEAP}"

# ----------------------------------------
# BACKUPS
# ----------------------------------------
TIMESTAMP=$(date +%F-%H%M%S)

cp "$JVM_FILE" "${JVM_FILE}.bak.${TIMESTAMP}"
cp "$LIMITS_FILE" "${LIMITS_FILE}.bak.${TIMESTAMP}"
cp "$SYSCTL_FILE" "${SYSCTL_FILE}.bak.${TIMESTAMP}"

echo "Backup files created."

# ----------------------------------------
# JVM CONFIGURATION
# ----------------------------------------
echo ""
echo "Updating JVM heap settings..."

sed -i '/^-Xms/d' "$JVM_FILE"
sed -i '/^-Xmx/d' "$JVM_FILE"

cat <<EOF >> "$JVM_FILE"

# Auto-configured heap settings
-Xms${HEAP}
-Xmx${HEAP}
EOF

echo "JVM heap updated."

# ----------------------------------------
# LIMITS.CONF CONFIGURATION
# ----------------------------------------
echo ""
echo "Updating file descriptor limits..."

grep -q "^root soft nofile 65536" "$LIMITS_FILE" || \
echo "root soft nofile 65536" >> "$LIMITS_FILE"

grep -q "^root hard nofile 65536" "$LIMITS_FILE" || \
echo "root hard nofile 65536" >> "$LIMITS_FILE"

echo "limits.conf updated."

# ----------------------------------------
# VM.MAX_MAP_COUNT
# ----------------------------------------
echo ""
echo "Configuring vm.max_map_count..."

sysctl -w vm.max_map_count=262144

if ! grep -q "^vm.max_map_count=262144" "$SYSCTL_FILE"; then
    echo "vm.max_map_count=262144" >> "$SYSCTL_FILE"
fi

sysctl -p

echo "vm.max_map_count configured."

# ----------------------------------------
# SWAP DISABLE
# ----------------------------------------
echo ""
echo "Checking active swap..."

if swapon --show | grep -q "/"; then
    echo "Swap detected. Disabling swap..."

    swapoff -a

    # Disable permanently in fstab
    sed -ri '/\sswap\s/s/^/#/' /etc/fstab

    echo "Swap disabled."
else
    echo "No active swap found."
fi

# ----------------------------------------
# SHOW CONFIG
# ----------------------------------------
echo ""
echo "==========================================="
echo "Applied Configuration"
echo "==========================================="

echo ""
echo "JVM Heap:"
grep -E "^-Xms|^-Xmx" "$JVM_FILE"

echo ""
echo "File Limits:"
grep "nofile 65536" "$LIMITS_FILE"

echo ""
echo "vm.max_map_count:"
sysctl vm.max_map_count

echo ""
echo "Swap Status:"
swapon --show || true

# ----------------------------------------
# RESTART SERVICE
# ----------------------------------------
echo ""
echo "Restarting wazuh-indexer..."

systemctl restart wazuh-indexer

sleep 5

echo ""
echo "Service Status:"
systemctl status wazuh-indexer --no-pager

echo ""
echo "==========================================="
echo "Configuration completed successfully."
echo "==========================================="