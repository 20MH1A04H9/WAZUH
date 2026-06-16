#!/bin/bash
# =============================================================================
# Wazuh SCA Policy Installer
# Repo   : https://github.com/20MH1A04H9/WAZUH
# Folder : sca/policies/
# Usage  : sudo bash install_sca.sh
# =============================================================================

INSTALL_DIR="/var/ossec/etc/shared/default"
RULESET_DIR="/var/ossec/ruleset/sca"
RAW_BASE="https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/sca/policies"
BACKUP_DIR="/var/ossec/backups/sca/backup_$(date +%Y%m%d_%H%M%S)"

POLICIES=(
  "antivirus_sca.yml"
  "bitlocker_sca.yml"
  "powershell_sca.yml"
  "win_applications_sca.yml"
  "sca_sysmon_windows.yml"
)

# ── colours ──────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' B='\033[1m'    N='\033[0m'

# ── banner ───────────────────────────────────────────────────────────────────
echo -e "${C}${B}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         Wazuh SCA Policy Installer                      ║"
echo "║         Policies : ${#POLICIES[@]} files                             ║"
echo "║         Source   : github.com/20MH1A04H9/WAZUH          ║"
echo "║         Target   : /var/ossec/etc/shared/default/       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${N}"

# ── preflight ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && {
  echo -e "${R}[ERROR] Must run as root.  sudo bash install_sca.sh${N}"; exit 1; }

[[ ! -d "$INSTALL_DIR" ]] && {
  echo -e "${R}[ERROR] $INSTALL_DIR not found. Wazuh installed?${N}"; exit 1; }

command -v curl  &>/dev/null && DL="curl" \
  || command -v wget &>/dev/null && DL="wget" \
  || { echo -e "${R}[ERROR] curl or wget required.${N}"; exit 1; }

echo -e "${G}[✓] Install dir  : $INSTALL_DIR${N}"
echo -e "${G}[✓] Ruleset dir  : $RULESET_DIR${N}"
echo -e "${G}[✓] Downloader   : $DL${N}"
echo -e "${G}[✓] Policies     : ${#POLICIES[@]}${N}"
echo ""

# ── backup any existing copies (stored OUTSIDE shared/default so wazuh-remoted doesn't try to serve them) ──
echo -e "${C}[*] Checking for existing policies to backup...${N}"
BACKED=false
for P in "${POLICIES[@]}"; do
  if [[ -f "$INSTALL_DIR/$P" ]]; then
    $BACKED || { mkdir -p "$BACKUP_DIR"; BACKED=true; }
    cp "$INSTALL_DIR/$P" "$BACKUP_DIR/"
    echo -e "  ${Y}[backup]${N} $P  →  $BACKUP_DIR/"
  fi
done
$BACKED || echo -e "  No existing files found — skipping backup."

# ── download loop ────────────────────────────────────────────────────────────
echo -e "\n${C}[*] Downloading and installing SCA policies...${N}"
OK=0; FAIL=0

for P in "${POLICIES[@]}"; do
  URL="${RAW_BASE}/${P}"
  DEST="${INSTALL_DIR}/${P}"

  echo -e "\n  ──────────────────────────────────────────────"
  echo -e "  ${B}Policy :${N} $P"
  echo -e "  ${B}URL    :${N} $URL"
  echo -e "  ${B}Dest   :${N} $DEST"

  # download
  if [[ "$DL" == "curl" ]]; then
    HTTP=$(curl -fsSL --connect-timeout 10 -o "$DEST" -w "%{http_code}" "$URL" 2>/dev/null)
  else
    wget -q --timeout=10 -O "$DEST" "$URL" 2>/dev/null && HTTP="200" || HTTP="000"
  fi

  # validate
  if [[ "$HTTP" == "200" ]] && [[ -s "$DEST" ]]; then
    chown root:wazuh "$DEST" 2>/dev/null || chown root:root "$DEST"
    chmod 660 "$DEST"
    # extract policy name for confirmation
    PNAME=$(grep -m1 'name:' "$DEST" | sed 's/.*name: *"//' | sed 's/".*//')
    echo -e "  ${G}[✓] Installed${N}  —  $PNAME"
    ((OK++))
  else
    echo -e "  ${R}[✗] Failed (HTTP $HTTP)${N}"
    [[ -f "$DEST" ]] && rm -f "$DEST"
    # restore backup if available
    if [[ -f "$BACKUP_DIR/$P" ]]; then
      cp "$BACKUP_DIR/$P" "$DEST"
      echo -e "  ${Y}[↩] Restored previous version from backup${N}"
    fi
    ((FAIL++))
  fi
done

# ── copy to ruleset/sca ───────────────────────────────────────────────────────
echo -e "\n${C}[*] Syncing to ruleset/sca...${N}"
if [[ -d "$RULESET_DIR" ]]; then
  for P in "${POLICIES[@]}"; do
    if [[ -f "$INSTALL_DIR/$P" ]]; then
      cp "$INSTALL_DIR/$P" "$RULESET_DIR/$P"
      chown root:wazuh "$RULESET_DIR/$P" 2>/dev/null
      chmod 640 "$RULESET_DIR/$P"
      echo -e "  ${G}[✓]${N} $P  →  $RULESET_DIR/"
    fi
  done
else
  echo -e "  ${Y}[!] $RULESET_DIR not found — skipping ruleset sync.${N}"
fi

# ── restart wazuh ─────────────────────────────────────────────────────────────
echo -e "\n${C}[*] Restarting Wazuh Manager...${N}"
if systemctl list-units --type=service 2>/dev/null | grep -q wazuh-manager; then
  systemctl restart wazuh-manager
  sleep 3
  if systemctl is-active --quiet wazuh-manager; then
    echo -e "${G}[✓] Wazuh Manager restarted successfully${N}"
  else
    echo -e "${R}[✗] Restart failed — check: journalctl -u wazuh-manager -n 30${N}"
    exit 1
  fi
else
  /var/ossec/bin/wazuh-control restart 2>/dev/null \
    || echo -e "${Y}[!] Run manually: /var/ossec/bin/wazuh-control restart${N}"
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo -e "\n${C}${B}╔══════════════════════════════════════════╗"
echo    "║            INSTALLATION SUMMARY          ║"
echo -e "╚══════════════════════════════════════════╝${N}"
echo -e "  Total Policies   : ${B}${#POLICIES[@]}${N}"
echo -e "  Installed        : ${G}${OK}${N}"
echo -e "  Failed           : ${R}${FAIL}${N}"
echo -e "  Install Path     : $INSTALL_DIR"
echo -e "  Ruleset Path     : $RULESET_DIR"
[[ -d "$BACKUP_DIR" ]] && echo -e "  Backups          : $BACKUP_DIR"
echo ""
echo -e "${C}[*] Verify :${N} tail -f /var/ossec/logs/ossec.log | grep -i sca"
echo -e "${C}[*] Agents will receive policies on next check-in (default 10 min)${N}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${G}${B}[✓] All ${OK} SCA policies installed successfully!${N}"
else
  echo -e "${Y}[!] ${FAIL} policy/policies failed. Check connectivity to GitHub.${N}"
  exit 1
fi
