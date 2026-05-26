#!/bin/bash

INSTALL_DIR="/var/ossec/etc/shared/default"
WAZUH_SCA_DIR="/var/ossec/ruleset/sca"
GITHUB_RAW="https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/sca/policies"
BACKUP_DIR="/var/ossec/etc/shared/default/backup_$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

POLICIES=(
  "antivirus_sca.yml"
  "bitlocker_sca.yml"
)

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║      Wazuh SCA Policy Installer                     ║"
echo "║      Target : /var/ossec/etc/shared/default/        ║"
echo "║      Source : github.com/20MH1A04H9/WAZUH           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

[[ $EUID -ne 0 ]] && { echo -e "${RED}[ERROR] Run as root: sudo bash ~/install_sca.sh${NC}"; exit 1; }
[ ! -d "$INSTALL_DIR" ] && { echo -e "${RED}[ERROR] $INSTALL_DIR not found.${NC}"; exit 1; }

echo -e "${GREEN}[✓] Install directory: $INSTALL_DIR${NC}"

command -v curl &>/dev/null && DL="curl" || command -v wget &>/dev/null && DL="wget" || { echo -e "${RED}[ERROR] curl or wget required.${NC}"; exit 1; }
echo -e "${GREEN}[✓] Downloader: $DL${NC}"

echo -e "\n${CYAN}[*] Checking for existing SCA files to backup...${NC}"
BACKED=false
for P in "${POLICIES[@]}"; do
  if [ -f "$INSTALL_DIR/$P" ]; then
    $BACKED || { mkdir -p "$BACKUP_DIR"; BACKED=true; }
    cp "$INSTALL_DIR/$P" "$BACKUP_DIR/"
    echo -e "${YELLOW}  [backup] $P → $BACKUP_DIR/${NC}"
  fi
done
$BACKED || echo -e "  No existing files to backup."

echo -e "\n${CYAN}[*] Downloading SCA policies from GitHub...${NC}"
OK=0; FAIL=0

for P in "${POLICIES[@]}"; do
  URL="$GITHUB_RAW/$P"
  DEST="$INSTALL_DIR/$P"
  echo -e "\n  → ${YELLOW}$P${NC}"
  echo -e "    URL  : $URL"
  echo -e "    Dest : $DEST"

  [ "$DL" = "curl" ] && CODE=$(curl -fsSL -o "$DEST" -w "%{http_code}" "$URL") || { wget -q -O "$DEST" "$URL" && CODE="200" || CODE="000"; }

  if [ "$CODE" = "200" ] && [ -s "$DEST" ]; then
    chown root:wazuh "$DEST" 2>/dev/null || chown root:root "$DEST"
    chmod 660 "$DEST"
    echo -e "    ${GREEN}[✓] Installed successfully${NC}"
    ((OK++))
  else
    echo -e "    ${RED}[✗] Download failed (HTTP $CODE)${NC}"
    [ -f "$DEST" ] && rm -f "$DEST"
    ((FAIL++))
  fi
done

echo -e "\n${CYAN}[*] Copying policies to ruleset/sca...${NC}"
if [ -d "$WAZUH_SCA_DIR" ]; then
  for P in "${POLICIES[@]}"; do
    [ -f "$INSTALL_DIR/$P" ] && cp "$INSTALL_DIR/$P" "$WAZUH_SCA_DIR/$P" && \
    chown root:wazuh "$WAZUH_SCA_DIR/$P" 2>/dev/null; chmod 640 "$WAZUH_SCA_DIR/$P" && \
    echo -e "  ${GREEN}[✓] Copied $P → $WAZUH_SCA_DIR/${NC}"
  done
else
  echo -e "  ${YELLOW}[!] $WAZUH_SCA_DIR not found, skipping.${NC}"
fi

echo -e "\n${CYAN}[*] Restarting Wazuh Manager...${NC}"
if systemctl is-active --quiet wazuh-manager 2>/dev/null; then
  systemctl restart wazuh-manager && sleep 3
  systemctl is-active --quiet wazuh-manager \
    && echo -e "${GREEN}[✓] Wazuh Manager restarted successfully${NC}" \
    || echo -e "${RED}[✗] Restart failed. Check: journalctl -u wazuh-manager -n 30${NC}"
else
  /var/ossec/bin/wazuh-control restart 2>/dev/null || /var/ossec/bin/ossec-control restart 2>/dev/null || \
  echo -e "${YELLOW}[!] Run manually: /var/ossec/bin/wazuh-control restart${NC}"
fi

echo -e "\n${CYAN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║            INSTALLATION SUMMARY          ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo -e "  Policies Installed : ${GREEN}$OK${NC}"
echo -e "  Policies Failed    : ${RED}$FAIL${NC}"
echo -e "  Install Path       : $INSTALL_DIR"
echo -e "  Ruleset SCA Path   : $WAZUH_SCA_DIR"
[ -d "$BACKUP_DIR" ] && echo -e "  Backups            : $BACKUP_DIR"
echo ""
echo -e "${CYAN}[*] Verify:${NC} tail -f /var/ossec/logs/ossec.log | grep -i sca"
echo ""
[ "$FAIL" -eq 0 ] \
  && echo -e "${GREEN}${BOLD}[✓] All SCA policies installed successfully!${NC}" \
  || echo -e "${YELLOW}[!] $FAIL policy/policies failed. Check GitHub connectivity.${NC}"
