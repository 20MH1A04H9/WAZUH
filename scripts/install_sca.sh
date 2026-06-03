#!/bin/bash
# =============================================================================
# Wazuh SCA Policy Installer — Dynamic (auto-discovers from GitHub)
# Repo  : https://github.com/20MH1A04H9/WAZUH
# Path  : sca/policies/
# Usage : curl -so ~/install_sca.sh https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/scripts/install_sca.sh && sudo bash ~/install_sca.sh
# =============================================================================

INSTALL_DIR="/var/ossec/etc/shared/default"
WAZUH_SCA_DIR="/var/ossec/ruleset/sca"
GITHUB_RAW="https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/sca/policies"
GITHUB_API="https://api.github.com/repos/20MH1A04H9/WAZUH/contents/sca/policies"
BACKUP_DIR="/var/ossec/etc/shared/default/backup_$(date +%Y%m%d_%H%M%S)"

# Fallback list — update this when adding new policies to GitHub
FALLBACK_POLICIES=(
  "antivirus_sca.yml"
  "bitlocker_sca.yml"
  "powershell_sca.yml"
  "win_applications_sca.yml"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Banner ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║      Wazuh SCA Policy Installer  (Dynamic)          ║"
echo "║      Target : /var/ossec/etc/shared/default/        ║"
echo "║      Source : github.com/20MH1A04H9/WAZUH           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Preflight ──────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo -e "${RED}[ERROR] Run as root: sudo bash ~/install_sca.sh${NC}"; exit 1; }
[ ! -d "$INSTALL_DIR" ]   && { echo -e "${RED}[ERROR] $INSTALL_DIR not found. Is Wazuh installed?${NC}"; exit 1; }
echo -e "${GREEN}[✓] Install directory: $INSTALL_DIR${NC}"

command -v curl  &>/dev/null && DL="curl"  \
  || command -v wget &>/dev/null && DL="wget" \
  || { echo -e "${RED}[ERROR] curl or wget required.${NC}"; exit 1; }
echo -e "${GREEN}[✓] Downloader: $DL${NC}"

# ── Discover policies from GitHub API ──────────────────────────────────────
echo -e "\n${CYAN}[*] Discovering policies from GitHub...${NC}"

POLICIES=()

_api_fetch() {
  if [ "$DL" = "curl" ]; then
    curl -fsSL --connect-timeout 8 "$GITHUB_API"
  else
    wget -qO- --timeout=8 "$GITHUB_API"
  fi
}

if command -v python3 &>/dev/null; then
  API_RESPONSE=$(_api_fetch 2>/dev/null)
  if echo "$API_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['name']) for f in d if isinstance(f,dict) and f.get('type')=='file' and f.get('name','').endswith('.yml')]" 2>/dev/null | grep -q '.'; then
    mapfile -t POLICIES < <(echo "$API_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if isinstance(data, list):
    for f in data:
        if isinstance(f, dict) and f.get('type') == 'file' and f.get('name', '').endswith('.yml'):
            print(f['name'])
")
    echo -e "${GREEN}[✓] Discovered ${#POLICIES[@]} policies from GitHub API${NC}"
  else
    echo -e "${YELLOW}[!] GitHub API unavailable or rate-limited — using fallback list${NC}"
    POLICIES=("${FALLBACK_POLICIES[@]}")
  fi
else
  echo -e "${YELLOW}[!] python3 not found — using fallback list${NC}"
  POLICIES=("${FALLBACK_POLICIES[@]}")
fi

if [ ${#POLICIES[@]} -eq 0 ]; then
  echo -e "${RED}[ERROR] No policies to install.${NC}"
  exit 1
fi

echo -e "\n  Policies to install:"
for P in "${POLICIES[@]}"; do
  echo -e "    ${CYAN}•${NC} $P"
done

# ── Backup existing files ──────────────────────────────────────────────────
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

# ── Download and install ───────────────────────────────────────────────────
echo -e "\n${CYAN}[*] Downloading SCA policies from GitHub...${NC}"
OK=0; FAIL=0

for P in "${POLICIES[@]}"; do
  URL="$GITHUB_RAW/$P"
  DEST="$INSTALL_DIR/$P"
  echo -e "\n  → ${YELLOW}$P${NC}"
  echo -e "    URL  : $URL"
  echo -e "    Dest : $DEST"

  if [ "$DL" = "curl" ]; then
    CODE=$(curl -fsSL --connect-timeout 10 -o "$DEST" -w "%{http_code}" "$URL" 2>/dev/null)
  else
    wget -q --timeout=10 -O "$DEST" "$URL" 2>/dev/null && CODE="200" || CODE="000"
  fi

  if [[ "$CODE" == "200" ]] && [ -s "$DEST" ]; then
    chown root:wazuh "$DEST" 2>/dev/null || chown root:root "$DEST"
    chmod 660 "$DEST"
    echo -e "    ${GREEN}[✓] Installed successfully${NC}"
    ((OK++))
  else
    echo -e "    ${RED}[✗] Download failed (HTTP $CODE)${NC}"
    [ -f "$DEST" ] && rm -f "$DEST"
    # Restore from backup if it existed
    [ -f "$BACKUP_DIR/$P" ] && cp "$BACKUP_DIR/$P" "$DEST" && \
      echo -e "    ${YELLOW}[↩] Restored from backup${NC}"
    ((FAIL++))
  fi
done

# ── Copy to ruleset/sca ────────────────────────────────────────────────────
echo -e "\n${CYAN}[*] Copying policies to ruleset/sca...${NC}"
if [ -d "$WAZUH_SCA_DIR" ]; then
  for P in "${POLICIES[@]}"; do
    if [ -f "$INSTALL_DIR/$P" ]; then
      cp "$INSTALL_DIR/$P" "$WAZUH_SCA_DIR/$P"
      chown root:wazuh "$WAZUH_SCA_DIR/$P" 2>/dev/null
      chmod 640 "$WAZUH_SCA_DIR/$P"
      echo -e "  ${GREEN}[✓] Copied $P → $WAZUH_SCA_DIR/${NC}"
    fi
  done
else
  echo -e "  ${YELLOW}[!] $WAZUH_SCA_DIR not found, skipping ruleset copy.${NC}"
fi

# ── Restart Wazuh ──────────────────────────────────────────────────────────
echo -e "\n${CYAN}[*] Restarting Wazuh Manager...${NC}"
if systemctl is-active --quiet wazuh-manager 2>/dev/null || systemctl list-units --type=service 2>/dev/null | grep -q wazuh-manager; then
  systemctl restart wazuh-manager
  sleep 3
  if systemctl is-active --quiet wazuh-manager; then
    echo -e "${GREEN}[✓] Wazuh Manager restarted successfully${NC}"
  else
    echo -e "${RED}[✗] Restart failed. Check: journalctl -u wazuh-manager -n 30${NC}"
    exit 1
  fi
else
  /var/ossec/bin/wazuh-control restart 2>/dev/null \
    || /var/ossec/bin/ossec-control restart 2>/dev/null \
    || echo -e "${YELLOW}[!] Run manually: /var/ossec/bin/wazuh-control restart${NC}"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║            INSTALLATION SUMMARY          ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo -e "  Policies Discovered : ${CYAN}${#POLICIES[@]}${NC}"
echo -e "  Policies Installed  : ${GREEN}$OK${NC}"
echo -e "  Policies Failed     : ${RED}$FAIL${NC}"
echo -e "  Install Path        : $INSTALL_DIR"
echo -e "  Ruleset SCA Path    : $WAZUH_SCA_DIR"
[ -d "$BACKUP_DIR" ] && echo -e "  Backups             : $BACKUP_DIR"
echo ""
echo -e "${CYAN}[*] Verify:${NC} tail -f /var/ossec/logs/ossec.log | grep -i sca"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}[✓] All SCA policies installed successfully!${NC}"
else
  echo -e "${YELLOW}[!] $FAIL policy/policies failed. Check GitHub connectivity or update FALLBACK_POLICIES.${NC}"
  exit 1
fi
