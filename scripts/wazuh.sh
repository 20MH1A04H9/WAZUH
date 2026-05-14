#!/bin/bash

# =========================================================
# Wazuh Custom Rules Installer
# Art by Viswa
# =========================================================

set -e

RULES_DIR="/var/ossec/etc/rules"
TMP_DIR="/tmp/wazuh-custom-rules"

echo "[+] Updating system..."
apt update -y

echo "[+] Installing git..."
apt install git -y

echo "[+] Removing old temp files..."
rm -rf $TMP_DIR

echo "[+] Cloning GitHub repository..."
git clone https://github.com/20MH1A04H9/WAZUH.git $TMP_DIR

echo "[+] Copying custom rules..."

# Copy all XML rules
cp -v $TMP_DIR/Rules/*.xml $RULES_DIR/

echo "[+] Setting permissions..."
chown root:wazuh $RULES_DIR/*.xml
chmod 640 $RULES_DIR/*.xml

echo "[+] Validating rules..."

/var/ossec/bin/wazuh-logtest -t || true

echo "[+] Restarting Wazuh Manager..."
systemctl restart wazuh-manager

echo "[+] Checking Wazuh Manager status..."
systemctl status wazuh-manager --no-pager

echo ""
echo "======================================="
echo " Custom Wazuh Rules Installed"
echo "======================================="
