# FLEET-OSQUERY (v4)

**MySQL Backend · Redis · Windows Enrollment · SOC Queries**

![Osquery Manager](https://img.shields.io/badge/OSQUERY-MANAGER-0052CC?style=for-the-badge)
![Osquery](https://img.shields.io/badge/OSQUERY-333333?style=for-the-badge)
![Endpoint Monitoring](https://img.shields.io/badge/ENDPOINT-MONITORING-E8590C?style=for-the-badge)
![MySQL](https://img.shields.io/badge/MYSQL-8.0-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![Redis](https://img.shields.io/badge/REDIS-CACHE-D32F2F?style=for-the-badge&logo=redis&logoColor=white)
![TLS](https://img.shields.io/badge/TLS-LETSENCRYPT-26A69A?style=for-the-badge)
![Platform](https://img.shields.io/badge/PLATFORM-UBUNTU%20%7C%20WINDOWS-555555?style=for-the-badge)

`Fleet v4.86.1` · `fleetctl v4.86.1`

---

## 1. Architecture

| Component | Purpose |
|---|---|
| MySQL 8.0 | Fleet's primary datastore |
| Redis | Cache & live query pub/sub |
| Fleet Server | Management UI + API (port 8080) |
| Let's Encrypt | TLS certificate for the Fleet endpoint |
| fleetctl | CLI for config, enroll secrets, packaging |
| osquery (MSI) | Windows endpoint agent |

> Replace all domains, IPs, emails, and passwords below with your own values. None of the values in this guide are real.

---

## 2. Install MySQL 8.0

```bash
apt-get update
apt-get install -y mysql-server
systemctl start mysql
systemctl enable mysql
```

---

## 3. Secure MySQL & Create Fleet Database

```bash
mysql -u root << 'EOF'
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'YOUR_MYSQL_ROOT_PASSWORD';
CREATE DATABASE fleet;
CREATE USER 'fleet'@'localhost' IDENTIFIED BY 'YOUR_FLEET_DB_PASSWORD';
GRANT ALL PRIVILEGES ON fleet.* TO 'fleet'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF
```

Verify:

```bash
mysql -u fleet -pYOUR_FLEET_DB_PASSWORD -e "SHOW DATABASES;"
```

---

## 4. Install Redis

```bash
apt-get install -y redis-server
systemctl start redis-server
systemctl enable redis-server
redis-cli ping   # Expect: PONG
```

---

## 5. Download Fleet & fleetctl Binaries

```bash
cd /tmp

# Fleet server binary
wget https://github.com/fleetdm/fleet/releases/download/fleet-v4.86.1/fleet_v4.86.1_linux.tar.gz
tar -xzf fleet_v4.86.1_linux.tar.gz
cp fleet_v4.86.1_linux/fleet /usr/local/bin/fleet

# fleetctl CLI (note the _amd64 suffix)
wget https://github.com/fleetdm/fleet/releases/download/fleet-v4.86.1/fleetctl_v4.86.1_linux_amd64.tar.gz
tar -xzf fleetctl_v4.86.1_linux_amd64.tar.gz
cp fleetctl_v4.86.1_linux_amd64/fleetctl /usr/local/bin/fleetctl
chmod +x /usr/local/bin/fleetctl

fleet version
fleetctl --version
```

---

## 6. TLS Certificate (Let's Encrypt)

Ensure port 80 is open in your firewall / cloud NSG before running:

```bash
apt-get install -y certbot
certbot certonly --standalone \
  -d fleet.yourdomain.com \
  --email you@yourdomain.com \
  --agree-tos --non-interactive
```

> Alternatively, generate a self-signed cert for lab/test environments (see Fleet v3 guide for the `openssl` example).

---

## 7. Fleet Configuration File

```bash
mkdir -p /etc/fleet

cat > /etc/fleet/fleet.yml << 'EOF'
mysql:
  address: 127.0.0.1:3306
  database: fleet
  username: fleet
  password: YOUR_FLEET_DB_PASSWORD

redis:
  address: 127.0.0.1:6379

server:
  address: 0.0.0.0:8080
  cert: /etc/fleet/server.cert
  key: /etc/fleet/server.key

logging:
  json: true
EOF
```

> Point `server.cert` / `server.key` to your Let's Encrypt files (`/etc/letsencrypt/live/<domain>/fullchain.pem` and `privkey.pem`) or your self-signed pair.

---

## 8. Run Database Migrations

```bash
fleet prepare db --config /etc/fleet/fleet.yml
```

---

## 9. systemd Service

```bash
cat > /etc/systemd/system/fleet.service << 'EOF'
[Unit]
Description=Fleet v4
After=network.target mysql.service redis-server.service

[Service]
ExecStart=/usr/local/bin/fleet serve --config /etc/fleet/fleet.yml
Restart=always
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fleet
systemctl start fleet
systemctl status fleet
```

Verify the server is healthy:

```bash
curl -sk https://127.0.0.1:8080/healthz
```

Access the setup wizard at:

```
https://YOUR_FLEET_IP:8080/setup
```

---

## 10. fleetctl Login & Enroll Secret

```bash
fleetctl config set --address https://127.0.0.1:8080 --tls-skip-verify
fleetctl login
fleetctl get enroll-secret
```

---

## 11. Build Windows Installer (MSI)

Requires Docker on the Fleet server.

```bash
fleetctl package \
  --type=msi \
  --fleet-url=https://YOUR_FLEET_IP:8080 \
  --enroll-secret=YOUR_ENROLL_SECRET \
  --insecure
```

This pulls a Docker image and builds `fleet-osquery.msi` (~2-3 min on first run).

---

## 12. Deploy & Install on Windows Endpoint

**On the Fleet server**, serve the MSI temporarily:

```bash
cd /tmp
python3 -m http.server 9999
```

**On the Windows endpoint**, in an elevated PowerShell session:

```powershell
Invoke-WebRequest -Uri "http://YOUR_FLEET_IP:9999/fleet-osquery.msi" -OutFile "$env:TEMP\fleet-osquery.msi"

msiexec /i "$env:TEMP\fleet-osquery.msi" /quiet /l*v "$env:TEMP\fleet-install.log"
```

Stop the Python server (`Ctrl+C`) once the download completes.

Confirm enrollment on the Fleet server (allow ~30s):

```bash
fleetctl get hosts
```

---

## 13. SOC Query Pack (Windows Hosts)

**Logged-in users**
```sql
SELECT * FROM logged_in_users;
```

**Local users**
```sql
SELECT username, type, uid, description FROM users;
```

**Installed software**
```sql
SELECT name, version, publisher, install_date FROM programs ORDER BY install_date DESC;
```

**Running processes**
```sql
SELECT pid, name, path, cmdline, parent FROM processes;
```

**Startup items (persistence)**
```sql
SELECT name, path, source, status FROM startup_items;
```

**Running services**
```sql
SELECT name, display_name, status, start_type, path FROM services WHERE status = 'RUNNING';
```

**Scheduled tasks (persistence / LOLBin abuse)**
```sql
SELECT name, action, path, enabled, last_run_time FROM scheduled_tasks;
```

**Established network connections**
```sql
SELECT pid, local_address, local_port, remote_address, remote_port, state
FROM process_open_sockets WHERE state = 'ESTABLISHED';
```

**Listening ports**
```sql
SELECT pid, port, address, protocol FROM listening_ports;
```

**Local administrators (privilege check)**
```sql
SELECT * FROM users WHERE uid IN (
  SELECT uid FROM user_groups WHERE gid = (
    SELECT gid FROM groups WHERE groupname = 'Administrators'
  )
);
```

**Patch level / hotfixes**
```sql
SELECT hotfix_id, installed_on FROM patches ORDER BY installed_on DESC;
```

**Firewall status**
```sql
SELECT name, enabled, default_inbound_action, default_outbound_action
FROM windows_firewall_rules LIMIT 20;
```

**Defender / AV status**
```sql
SELECT name, state, product_state FROM windows_security_products;
```

**Recently modified files in sensitive paths (basic FIM check)**
```sql
SELECT path, mtime, size FROM file
WHERE path LIKE 'C:\Windows\System32\%'
ORDER BY mtime DESC LIMIT 20;
```

**USB / removable device history**
```sql
SELECT * FROM usb_devices;
```

**Autoruns (registry persistence)**
```sql
SELECT name, path, source FROM autoexec;
```

---


## License

MIT
