# FLEET-OSQUERY

**Server Setup · Endpoint Enrollment · SQL Queries · Service Management**

![Kolide Fleet](https://img.shields.io/badge/KOLIDE-FLEET-555555?style=for-the-badge)
![Osquery Manager](https://img.shields.io/badge/OSQUERY-MANAGER-0052CC?style=for-the-badge)
![Osquery](https://img.shields.io/badge/OSQUERY-333333?style=for-the-badge)
![Endpoint Monitoring](https://img.shields.io/badge/ENDPOINT-MONITORING-E8590C?style=for-the-badge)
![Log Aggregation](https://img.shields.io/badge/LOG-AGGREGATION-D32F2F?style=for-the-badge)
![Log Shipper](https://img.shields.io/badge/LOG-SHIPPER-26A69A?style=for-the-badge)
![Platform](https://img.shields.io/badge/PLATFORM-UBUNTU%20%7C%20CENTOS%20%7C%20WINDOWS-555555?style=for-the-badge)

`Fleet v3.2.0` · `osquery v5.23.0`

---

## 1. Architecture Overview

This guide covers the complete setup of Kolide Fleet as an osquery management server, with Ubuntu and Windows endpoint enrollment.

| Component | OS | Role |
|---|---|---|
| Fleet Server | Ubuntu 24.04 | Primary Fleet server |
| Combined Server | Ubuntu 24.04 | Fleet + SIEM combined |
| Linux Endpoint | Ubuntu 24.04 | osquery agent |
| Windows Endpoint | Windows 11 | osquery agent |

> Replace IPs, hostnames, and secrets below with your own environment values.

---

## 2. Prerequisites

### 2.1 Server Requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 4 cores |
| RAM | 2 GB | 4 GB |
| Storage | 10 GB | 50 GB |
| OS | Ubuntu 18.04+ | Ubuntu 22.04+ |

### 2.2 Required Ports

| Port | Service | Purpose |
|---|---|---|
| 8080 | Fleet UI | Web interface & API |
| 3306 | MySQL | Database |
| 6379 | Redis | Cache & pub-sub |
| 5985 | WinRM | Ansible Windows management |

---

## 3. Fleet Server Installation (Ubuntu)

### 3.1 Install Fleet Binary

```bash
wget https://github.com/kolide/fleet/releases/latest/download/fleet.zip
unzip fleet.zip 'linux/*' -d fleet
sudo cp fleet/linux/fleet /usr/bin/fleet
sudo cp fleet/linux/fleetctl /usr/bin/fleetctl
fleet version
```

### 3.2 Install MySQL

```bash
sudo apt-get install mysql-server -y
sudo systemctl start mysql && sudo systemctl enable mysql
```

Fix MySQL root authentication for TCP connections:

```bash
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'YourPassword';
FLUSH PRIVILEGES; EXIT;
```

Create the Fleet database:

```bash
mysql -u root -pYourPassword -e "CREATE DATABASE kolide;"
```

### 3.3 Install Redis

```bash
sudo apt-get install redis-server -y
sudo systemctl start redis-server && sudo systemctl enable redis-server
redis-cli ping   # Should return PONG
```

### 3.4 Generate TLS Certificate

```bash
sudo mkdir -p /etc/fleet

cat > /tmp/cert.conf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = YOUR_SERVER_IP

[v3_req]
subjectAltName = IP:YOUR_SERVER_IP
EOF

openssl req -x509 -nodes -days 366 -newkey rsa:4096 \
  -keyout /etc/fleet/server.key \
  -out /etc/fleet/server.cert \
  -config /tmp/cert.conf

sudo chmod 600 /etc/fleet/server.key
```

### 3.5 Prepare Database & Start Fleet

```bash
/usr/bin/fleet prepare db \
  --mysql_address=127.0.0.1:3306 \
  --mysql_database=kolide \
  --mysql_username=root \
  --mysql_password=YourPassword
# Expected output: Migrations completed.

/usr/bin/fleet serve \
  --mysql_address=127.0.0.1:3306 \
  --mysql_database=kolide \
  --mysql_username=root \
  --mysql_password=YourPassword \
  --redis_address=127.0.0.1:6379 \
  --server_cert=/etc/fleet/server.cert \
  --server_key=/etc/fleet/server.key \
  --auth_jwt_key=YOUR_JWT_KEY \
  --server_address=0.0.0.0:8080 \
  --logging_json
```

> Tip: On first run, Fleet will suggest a random `--auth_jwt_key`. Copy it and add it to the command above.

### 3.6 Create systemd Service

```bash
sudo tee /etc/systemd/system/fleet.service << EOF
[Unit]
Description=Kolide Fleet
After=network.target mysql.service redis.service

[Service]
ExecStart=/usr/bin/fleet serve \
  --mysql_address=127.0.0.1:3306 \
  --mysql_database=kolide \
  --mysql_username=root \
  --mysql_password=YourPassword \
  --redis_address=127.0.0.1:6379 \
  --server_cert=/etc/fleet/server.cert \
  --server_key=/etc/fleet/server.key \
  --auth_jwt_key=YOUR_JWT_KEY \
  --server_address=0.0.0.0:8080 \
  --logging_json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable fleet
sudo systemctl start fleet
sudo systemctl status fleet
```

---

## 4. Ubuntu Endpoint Enrollment

### 4.1 Install osquery

```bash
export OSQUERY_KEY=1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $OSQUERY_KEY
sudo add-apt-repository 'deb [arch=amd64] https://pkg.osquery.io/deb deb main'
sudo apt-get update && sudo apt-get install osquery
```

### 4.2 Configure Enrollment Files

Create the enroll secret (get from Fleet UI → Add New Host → Reveal Secret):

```bash
sudo mkdir -p /var/osquery
echo 'YOUR_ENROLL_SECRET' | sudo tee /var/osquery/enroll_secret
```

Save the Fleet TLS certificate (get from Fleet UI → Add New Host → Fetch Fleet Certificate):

```bash
sudo tee /var/osquery/server.pem << 'EOF'
-----BEGIN CERTIFICATE-----
(paste certificate content here)
-----END CERTIFICATE-----
EOF
```

### 4.3 Create osqueryd systemd Service

```bash
sudo tee /etc/systemd/system/osqueryd.service << EOF
[Unit]
Description=osquery daemon
After=network.target

[Service]
ExecStart=/usr/bin/osqueryd \
  --enroll_secret_path=/var/osquery/enroll_secret \
  --tls_server_certs=/var/osquery/server.pem \
  --tls_hostname=YOUR_FLEET_IP:8080 \
  --host_identifier=hostname \
  --enroll_tls_endpoint=/api/v1/osquery/enroll \
  --config_plugin=tls \
  --config_tls_endpoint=/api/v1/osquery/config \
  --config_refresh=10 \
  --disable_distributed=false \
  --distributed_plugin=tls \
  --distributed_interval=3 \
  --distributed_tls_max_attempts=3 \
  --distributed_tls_read_endpoint=/api/v1/osquery/distributed/read \
  --distributed_tls_write_endpoint=/api/v1/osquery/distributed/write \
  --logger_plugin=tls \
  --logger_tls_endpoint=/api/v1/osquery/log \
  --logger_tls_period=10
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable osqueryd
sudo systemctl start osqueryd
```

---

## 5. Windows Endpoint Enrollment

### 5.1 Install osquery on Windows

Download from [osquery.io/downloads](https://osquery.io/downloads) and install the MSI, or via winget:

```powershell
winget install osquery
```

### 5.2 Create Required Files

Run in PowerShell as Administrator:

```powershell
New-Item -Path 'C:\osquery' -ItemType Directory -Force
Set-Content -Path 'C:\osquery\enroll_secret.txt' -Value 'YOUR_ENROLL_SECRET'
```

Save the Fleet certificate:

```powershell
$cert = @'
-----BEGIN CERTIFICATE-----
(paste certificate content here)
-----END CERTIFICATE-----
'@
Set-Content -Path 'C:\osquery\server.pem' -Value $cert
```

### 5.3 Create osquery Flags File

```powershell
$flags = @'
--enroll_secret_path=C:\osquery\enroll_secret.txt
--tls_server_certs=C:\osquery\server.pem
--tls_hostname=YOUR_FLEET_IP:8080
--host_identifier=hostname
--enroll_tls_endpoint=/api/v1/osquery/enroll
--config_plugin=tls
--config_tls_endpoint=/api/v1/osquery/config
--config_refresh=10
--disable_distributed=false
--distributed_plugin=tls
--distributed_interval=3
--distributed_tls_max_attempts=3
--distributed_tls_read_endpoint=/api/v1/osquery/distributed/read
--distributed_tls_write_endpoint=/api/v1/osquery/distributed/write
--logger_plugin=tls
--logger_tls_endpoint=/api/v1/osquery/log
--logger_tls_period=10
'@
Set-Content -Path 'C:\Program Files\osquery\osquery.flags' -Value $flags

Restart-Service osqueryd
```

---

## 6. Useful osquery SQL Queries

**System Information**
```sql
SELECT hostname, cpu_brand, physical_memory FROM system_info;
```

**OS Version**
```sql
SELECT name, version, platform FROM os_version;
```

**Running Processes**
```sql
SELECT pid, name, path, cmdline FROM processes LIMIT 20;
```

**Logged In Users**
```sql
SELECT user, host, time FROM logged_in_users;
```

**Open Network Connections**
```sql
SELECT pid, local_address, local_port, remote_address, remote_port, state
FROM process_open_sockets WHERE state = 'ESTABLISHED';
```

**Installed Software (Linux)**
```sql
SELECT name, version, arch FROM deb_packages ORDER BY name;
```

**Installed Software (Windows)**
```sql
SELECT name, version, publisher, install_date FROM programs ORDER BY install_date DESC;
```

**Listening Ports**
```sql
SELECT pid, port, protocol, address FROM listening_ports WHERE address != '127.0.0.1';
```

**Local Users**
```sql
SELECT username, uid, gid, directory, shell FROM users;
```

**Windows Services**
```sql
SELECT name, display_name, status, start_type FROM services WHERE status = 'RUNNING';
```

**Search Files**
```sql
SELECT path, size, datetime(mtime, 'unixepoch') AS modified
FROM file WHERE path LIKE 'C:\%keyword%';
```

---

## 7. Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Access denied for user root` | MySQL uses auth_socket | `ALTER USER` with `mysql_native_password` |
| Migrations completed (no output) | Fleet can't reach MySQL | Check password & port 3306 |
| `certificate verify failed` | Self-signed cert mismatch | Regenerate cert with SAN IP |
| Connection refused port 5985 | WinRM not started | `Start-Service WinRM` |
| Address already in use `:6379` | Redis already running | Run `redis-cli ping` to verify |
| `No such column os_version` | osquery v5+ schema change | Use `os_version` table instead |

---

## 8. Quick Reference

### Fleet UI URLs

| Page | URL |
|---|---|
| Setup | `https://YOUR_IP:8080/setup` |
| Hosts | `https://YOUR_IP:8080/hosts/manage` |
| Queries | `https://YOUR_IP:8080/queries` |
| Add Host | `https://YOUR_IP:8080/hosts/manage` → Add New Host |

### Service Commands

| Action | Command |
|---|---|
| Start Fleet | `sudo systemctl start fleet` |
| Stop Fleet | `sudo systemctl stop fleet` |
| Fleet Status | `sudo systemctl status fleet` |
| Start osqueryd | `sudo systemctl start osqueryd` |
| osquery logs | `sudo journalctl -u osqueryd -f` |
| Fleet logs | `sudo journalctl -u fleet -f` |

> **Note:** Kolide Fleet v3.2.0 is archived. For active development and support, consider migrating to [FleetDM](https://github.com/fleetdm/fleet).

---

## License

MIT
