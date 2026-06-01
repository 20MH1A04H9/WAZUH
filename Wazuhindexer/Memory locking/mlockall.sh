#!/bin/bash
# ============================================================
#  Wazuh Indexer - mlockall / Memory Lock Fix
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── 0. Root check ────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root: sudo bash $0"
fi

echo ""
echo "============================================================"
echo "  Wazuh Indexer - mlockall Fix Script"
echo "============================================================"
echo ""

# ── 1. Enable bootstrap.memory_lock in opensearch.yml ────────
OPENSEARCH_YML="/etc/wazuh-indexer/opensearch.yml"

if [[ ! -f "$OPENSEARCH_YML" ]]; then
  error "File not found: $OPENSEARCH_YML"
fi

log "Checking bootstrap.memory_lock in $OPENSEARCH_YML ..."

if grep -q "^bootstrap.memory_lock:" "$OPENSEARCH_YML"; then
  sed -i 's/^bootstrap.memory_lock:.*/bootstrap.memory_lock: true/' "$OPENSEARCH_YML"
  ok "Updated bootstrap.memory_lock to true"
else
  echo "bootstrap.memory_lock: true" >> "$OPENSEARCH_YML"
  ok "Added bootstrap.memory_lock: true"
fi

# ── 2. systemd override for LimitMEMLOCK ─────────────────────
OVERRIDE_DIR="/etc/systemd/system/wazuh-indexer.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"

log "Creating systemd override for LimitMEMLOCK=infinity ..."
mkdir -p "$OVERRIDE_DIR"

cat > "$OVERRIDE_FILE" <<EOF
[Service]
LimitMEMLOCK=infinity
EOF

ok "Written: $OVERRIDE_FILE"

# ── 3. memlock limits for wazuh-indexer user ─────────────────
LIMITS_D="/etc/security/limits.d/wazuh-indexer.conf"

log "Setting memlock limits for wazuh-indexer user ..."
cat > "$LIMITS_D" <<EOF
wazuh-indexer soft memlock unlimited
wazuh-indexer hard memlock unlimited
EOF
ok "Written: $LIMITS_D"

# Also add to /etc/security/limits.conf if not already present
if ! grep -q "wazuh-indexer.*memlock" /etc/security/limits.conf; then
  echo "wazuh-indexer soft memlock unlimited" >> /etc/security/limits.conf
  echo "wazuh-indexer hard memlock unlimited" >> /etc/security/limits.conf
  ok "Added memlock entries to /etc/security/limits.conf"
else
  ok "memlock entries already exist in /etc/security/limits.conf"
fi

# ── 4. Reload systemd and restart wazuh-indexer ──────────────
log "Reloading systemd daemon ..."
systemctl daemon-reload
ok "systemd daemon reloaded"

log "Restarting wazuh-indexer service ..."
systemctl restart wazuh-indexer
ok "wazuh-indexer restarted"

log "Waiting 15 seconds for indexer to fully start ..."
sleep 15

# ── 5. Verify mlockall ────────────────────────────────────────
echo ""
log "Verifying mlockall status ..."

# Try to get credentials from environment or prompt
if [[ -z "$WAZUH_ADMIN_PASS" ]]; then
  read -rsp "Enter Wazuh admin password: " WAZUH_ADMIN_PASS
  echo ""
fi

RESULT=$(curl -sk -u "admin:${WAZUH_ADMIN_PASS}" \
  "https://localhost:9200/_nodes?filter_path=**.mlockall&pretty")

echo "$RESULT"

if echo "$RESULT" | grep -q '"mlockall" : true'; then
  echo ""
  ok "✅ mlockall is TRUE — memory locking is active!"
else
  echo ""
  warn "mlockall is still false. Check logs:"
  warn "  sudo journalctl -u wazuh-indexer --no-pager | tail -30"
fi

# ── 6. Verify systemd LimitMEMLOCK ───────────────────────────
echo ""
log "Verifying systemd LimitMEMLOCK ..."
systemctl show wazuh-indexer | grep -i memloc

echo ""
echo "============================================================"
echo "  Done. Summary of changes made:"
echo "  1. bootstrap.memory_lock: true  → $OPENSEARCH_YML"
echo "  2. LimitMEMLOCK=infinity        → $OVERRIDE_FILE"
echo "  3. memlock unlimited            → $LIMITS_D"
echo "  4. wazuh-indexer restarted"
echo "============================================================"
echo ""
