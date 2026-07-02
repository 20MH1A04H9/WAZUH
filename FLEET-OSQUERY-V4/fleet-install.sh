#!/bin/bash
# ============================================================
# Fleet v4 Server Install & Config Script
# Target OS  : Ubuntu 22.04 / 24.04 LTS
# Fleet Ver  : v4.86.1
# Author     : Viswa
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
fail()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section(){ echo -e "\n${CYAN}${BOLD}── $1 ──${NC}"; }
ask()    { echo -e "${BOLD}$1${NC}"; }

# ─────────────────────────────────────────
# ROOT CHECK
# ─────────────────────────────────────────
[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash $0"

# ─────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ███████╗██╗     ███████╗███████╗████████╗"
echo "  ██╔════╝██║     ██╔════╝██╔════╝╚══██╔══╝"
echo "  █████╗  ██║     █████╗  █████╗     ██║   "
echo "  ██╔══╝  ██║     ██╔══╝  ██╔══╝     ██║   "
echo "  ██║     ███████╗███████╗███████╗   ██║   "
echo "  ╚═╝     ╚══════╝╚══════╝╚══════╝   ╚═╝   "
echo -e "${NC}"
echo -e "  ${BOLD}Fleet v4.86.1 — Interactive Install Script${NC}"
echo -e "  Target: $(hostname) | $(lsb_release -ds 2>/dev/null || echo 'Ubuntu')"
echo ""

# ─────────────────────────────────────────
# INTERACTIVE CONFIG
# ─────────────────────────────────────────
section "Server Configuration"

ask "Enter server IP or domain (e.g. 20.244.3.180 or fleet.example.com):"
read -r FLEET_DOMAIN
[[ -z "$FLEET_DOMAIN" ]] && fail "Server IP/domain cannot be empty."

ask "Fleet port [default: 8080]:"
read -r FLEET_PORT_INPUT
FLEET_PORT="${FLEET_PORT_INPUT:-8080}"

ask "TLS certificate type?"
echo "  1) Self-signed (use IP or any domain, no DNS needed)"
echo "  2) Let's Encrypt (requires domain + port 80 open)"
read -r TLS_CHOICE
[[ "$TLS_CHOICE" != "1" && "$TLS_CHOICE" != "2" ]] && TLS_CHOICE="1"

section "MySQL Configuration"

# Detect if MySQL is already installed
MYSQL_ALREADY_INSTALLED=false
if command -v mysql &>/dev/null && systemctl is-active --quiet mysql 2>/dev/null; then
  MYSQL_ALREADY_INSTALLED=true
  warn "MySQL is already installed on this server."
  ask "Enter existing MySQL ROOT password:"
  read -rs MYSQL_ROOT_PASS
  echo ""
  # Verify it works
  mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT 1;" &>/dev/null || fail "MySQL root password incorrect. Aborting."
  log "MySQL root password verified."
else
  ask "Set MySQL root password [default: Fleet@Root123!]:"
  read -rs MYSQL_ROOT_PASS
  echo ""
  MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-Fleet@Root123!}"
fi

ask "Set MySQL fleet user password [default: Fleet@DB123!]:"
read -rs MYSQL_FLEET_PASS
echo ""
MYSQL_FLEET_PASS="${MYSQL_FLEET_PASS:-Fleet@DB123!}"

ask "Fleet MySQL database name [default: fleet]:"
read -r MYSQL_FLEET_DB_INPUT
MYSQL_FLEET_DB="${MYSQL_FLEET_DB_INPUT:-fleet}"

ask "Fleet MySQL username [default: fleet]:"
read -r MYSQL_FLEET_USER_INPUT
MYSQL_FLEET_USER="${MYSQL_FLEET_USER_INPUT:-fleet}"

section "Let's Encrypt"
LETSENCRYPT_EMAIL=""
if [[ "$TLS_CHOICE" == "2" ]]; then
  ask "Enter email for Let's Encrypt notifications:"
  read -r LETSENCRYPT_EMAIL
  [[ -z "$LETSENCRYPT_EMAIL" ]] && fail "Email required for Let's Encrypt."
fi

# ─────────────────────────────────────────
# CONFIRM
# ─────────────────────────────────────────
section "Configuration Summary"
echo ""
echo -e "  Hostname      : $(hostname)"
echo -e "  Fleet domain  : ${FLEET_DOMAIN}"
echo -e "  Fleet port    : ${FLEET_PORT}"
echo -e "  TLS type      : $([ "$TLS_CHOICE" == "2" ] && echo "Let's Encrypt (${LETSENCRYPT_EMAIL})" || echo "Self-signed")"
echo -e "  MySQL exists  : ${MYSQL_ALREADY_INSTALLED}"
echo -e "  MySQL DB      : ${MYSQL_FLEET_DB}"
echo -e "  MySQL user    : ${MYSQL_FLEET_USER}"
echo -e "  MySQL pass    : ********"
echo ""
ask "Proceed with install? (y/n):"
read -r CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted." && exit 0

# ─────────────────────────────────────────
# FIXED VARS
# ─────────────────────────────────────────
FLEET_VERSION="4.86.1"
CERT_DIR="/etc/fleet"
FLEET_BIN="/usr/local/bin/fleet"
FLEETCTL_BIN="/usr/local/bin/fleetctl"
FLEET_CONFIG="/etc/fleet/fleet.yml"
TMP_DIR="/tmp/fleet-install"
mkdir -p "$TMP_DIR"

# ─────────────────────────────────────────
# STEP 1 — MySQL
# ─────────────────────────────────────────
section "Step 1 — MySQL"

if [[ "$MYSQL_ALREADY_INSTALLED" == "false" ]]; then
  log "Installing MySQL 8.0..."
  apt-get update -qq
  apt-get install -y mysql-server > /dev/null
  systemctl start mysql
  systemctl enable mysql

  log "Setting MySQL root password..."
  mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
EOF
else
  log "Skipping MySQL install — already running."
fi

log "Creating Fleet database and user..."
mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_FLEET_DB};
CREATE USER IF NOT EXISTS '${MYSQL_FLEET_USER}'@'localhost' IDENTIFIED BY '${MYSQL_FLEET_PASS}';
GRANT ALL PRIVILEGES ON ${MYSQL_FLEET_DB}.* TO '${MYSQL_FLEET_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

log "MySQL ready — database '${MYSQL_FLEET_DB}' created."

# ─────────────────────────────────────────
# STEP 2 — Redis
# ─────────────────────────────────────────
section "Step 2 — Redis"

if systemctl is-active --quiet redis-server 2>/dev/null; then
  log "Redis already running — skipping install."
else
  log "Installing Redis..."
  apt-get install -y redis-server > /dev/null
  systemctl start redis-server
  systemctl enable redis-server
fi

redis-cli ping | grep -q PONG && log "Redis ready." || fail "Redis not responding."

# ─────────────────────────────────────────
# STEP 3 — Fleet binaries
# ─────────────────────────────────────────
section "Step 3 — Fleet Binaries"

if [[ -f "$FLEET_BIN" ]]; then
  CURRENT_VER=$("$FLEET_BIN" version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
  warn "Fleet binary already exists (v${CURRENT_VER}). Replacing with v${FLEET_VERSION}..."
fi

log "Downloading Fleet v${FLEET_VERSION}..."
cd "$TMP_DIR"

wget -q "https://github.com/fleetdm/fleet/releases/download/fleet-v${FLEET_VERSION}/fleet_v${FLEET_VERSION}_linux.tar.gz" -O fleet.tar.gz
wget -q "https://github.com/fleetdm/fleet/releases/download/fleet-v${FLEET_VERSION}/fleetctl_v${FLEET_VERSION}_linux_amd64.tar.gz" -O fleetctl.tar.gz

tar -xzf fleet.tar.gz
tar -xzf fleetctl.tar.gz

cp fleet_v${FLEET_VERSION}_linux/fleet              "$FLEET_BIN"
cp fleetctl_v${FLEET_VERSION}_linux_amd64/fleetctl  "$FLEETCTL_BIN"
chmod +x "$FLEET_BIN" "$FLEETCTL_BIN"

log "Fleet    : $($FLEET_BIN version | head -1)"
log "Fleetctl : $($FLEETCTL_BIN --version | head -1)"

# ─────────────────────────────────────────
# STEP 4 — TLS
# ─────────────────────────────────────────
section "Step 4 — TLS Certificate"
mkdir -p "$CERT_DIR"

if [[ "$TLS_CHOICE" == "2" ]]; then
  log "Getting Let's Encrypt cert for ${FLEET_DOMAIN}..."
  apt-get install -y certbot > /dev/null
  certbot certonly --standalone \
    -d "$FLEET_DOMAIN" \
    --email "$LETSENCRYPT_EMAIL" \
    --agree-tos --non-interactive
  cp /etc/letsencrypt/live/${FLEET_DOMAIN}/fullchain.pem "${CERT_DIR}/server.cert"
  cp /etc/letsencrypt/live/${FLEET_DOMAIN}/privkey.pem   "${CERT_DIR}/server.key"
  log "Let's Encrypt cert installed."
else
  log "Generating self-signed TLS cert for ${FLEET_DOMAIN}..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${CERT_DIR}/server.key" \
    -out    "${CERT_DIR}/server.cert" \
    -subj   "/CN=${FLEET_DOMAIN}" 2>/dev/null
  warn "Self-signed cert — browser will show 'Not Secure'."
fi

chmod 600 "${CERT_DIR}/server.key"

# ─────────────────────────────────────────
# STEP 5 — Fleet config
# ─────────────────────────────────────────
section "Step 5 — Fleet Config"
log "Writing ${FLEET_CONFIG}..."
cat > "$FLEET_CONFIG" <<EOF
mysql:
  address: 127.0.0.1:3306
  database: ${MYSQL_FLEET_DB}
  username: ${MYSQL_FLEET_USER}
  password: ${MYSQL_FLEET_PASS}

redis:
  address: 127.0.0.1:6379

server:
  address: 0.0.0.0:${FLEET_PORT}
  cert: ${CERT_DIR}/server.cert
  key: ${CERT_DIR}/server.key

logging:
  json: true
EOF

# ─────────────────────────────────────────
# STEP 6 — DB migrations
# ─────────────────────────────────────────
section "Step 6 — Database Migrations"
"$FLEET_BIN" prepare db --config "$FLEET_CONFIG"
log "Migrations complete."

# ─────────────────────────────────────────
# STEP 7 — systemd
# ─────────────────────────────────────────
section "Step 7 — Systemd Service"

# Stop existing fleet service if running
if systemctl is-active --quiet fleet 2>/dev/null; then
  warn "Stopping existing Fleet service..."
  systemctl stop fleet
fi

cat > /etc/systemd/system/fleet.service <<EOF
[Unit]
Description=Fleet v4 MDM
After=network.target mysql.service redis-server.service

[Service]
ExecStart=${FLEET_BIN} serve --config ${FLEET_CONFIG}
Restart=always
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fleet
systemctl start fleet
sleep 5

# ─────────────────────────────────────────
# STEP 8 — Health check
# ─────────────────────────────────────────
section "Step 8 — Health Check"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://127.0.0.1:${FLEET_PORT}/healthz")

if [[ "$HTTP_CODE" == "200" ]]; then
  log "Fleet is healthy (HTTP 200)."
else
  fail "Health check failed (HTTP ${HTTP_CODE}). Run: journalctl -u fleet -n 50"
fi

# ─────────────────────────────────────────
# DONE
# ─────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Fleet v${FLEET_VERSION} install complete!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Dashboard${NC}  : https://${FLEET_DOMAIN}:${FLEET_PORT}/setup"
echo -e "  ${BOLD}Config${NC}     : ${FLEET_CONFIG}"
echo -e "  ${BOLD}Logs${NC}       : journalctl -u fleet -f"
echo -e "  ${BOLD}Status${NC}     : systemctl status fleet"
echo ""
echo -e "${YELLOW}${BOLD}Next steps:${NC}"
echo -e "  1. Open port ${FLEET_PORT} in your firewall/NSG"
echo -e "  2. Complete setup wizard at https://${FLEET_DOMAIN}:${FLEET_PORT}/setup"
echo -e "  3. Create read-only API user:"
echo -e "     fleetctl user create --name 'API ReadOnly' --api-only --global-role observer"
[[ "$TLS_CHOICE" == "1" ]] && echo -e "  4. Replace self-signed cert with Let's Encrypt when ready"
echo ""
