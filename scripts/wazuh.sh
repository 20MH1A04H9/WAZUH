#!/bin/bash
# =========================================================
# Wazuh Custom Rules Installer
# Art by Viswa
# =========================================================
set -e

RULES_DIR="/var/ossec/etc/rules"
DECODERS_DIR="/var/ossec/etc/decoders"
TMP_DIR="/tmp/wazuh-custom-rules"

echo "[+] Updating system..."
apt update -y

echo "[+] Installing git..."
apt install git -y

echo "[+] Removing old temp files..."
rm -rf $TMP_DIR

echo "[+] Cloning GitHub repository..."
git clone https://github.com/20MH1A04H9/WAZUH.git $TMP_DIR

# ── Detect decoder files by inspecting XML root element ──────────────────────
echo "[+] Sorting rules and decoders..."
RULE_FILES=()
DECODER_FILES=()

for f in $TMP_DIR/Rules/*.xml; do
    # A decoder file has <decoder as its first meaningful XML element
    root_elem=$(grep -m1 -oP '(?<=<)[a-zA-Z_]+' "$f" | head -1)
    if [[ "$root_elem" == "decoder" ]]; then
        DECODER_FILES+=("$f")
    else
        RULE_FILES+=("$f")
    fi
done

echo "[+] Rules   (${#RULE_FILES[@]}):   $(basename -a "${RULE_FILES[@]}" | tr '\n' ' ')"
echo "[+] Decoders (${#DECODER_FILES[@]}): $(basename -a "${DECODER_FILES[@]}" | tr '\n' ' ')"

# ── Copy rules ────────────────────────────────────────────────────────────────
if [ ${#RULE_FILES[@]} -gt 0 ]; then
    echo "[+] Copying custom rules to $RULES_DIR ..."
    cp -v "${RULE_FILES[@]}" "$RULES_DIR/"
    chown root:wazuh "$RULES_DIR"/*.xml
    chmod 640 "$RULES_DIR"/*.xml
fi

# ── Copy decoders ─────────────────────────────────────────────────────────────
if [ ${#DECODER_FILES[@]} -gt 0 ]; then
    echo "[+] Copying custom decoders to $DECODERS_DIR ..."
    cp -v "${DECODER_FILES[@]}" "$DECODERS_DIR/"
    chown root:wazuh "$DECODERS_DIR"/*.xml
    chmod 640 "$DECODERS_DIR"/*.xml
fi

# ── Validate before restarting ────────────────────────────────────────────────
echo "[+] Validating configuration..."
if /var/ossec/bin/wazuh-analysisd -t 2>&1 | grep -E 'ERROR|CRITICAL'; then
    echo "[!] Validation found errors above. Aborting restart."
    echo "[!] Fix the errors and re-run, or manually restart with: systemctl start wazuh-manager"
    exit 1
else
    echo "[+] Validation passed (warnings above are non-fatal)."
fi

# ── Restart ───────────────────────────────────────────────────────────────────
echo "[+] Restarting Wazuh Manager..."
systemctl restart wazuh-manager

echo "[+] Checking Wazuh Manager status..."
systemctl status wazuh-manager --no-pager

echo ""
echo "======================================="
echo " Custom Wazuh Rules Installed"
echo "======================================="
