# GitHub → Wazuh Integration Guide

This guide covers setting up a GitHub Webhook Receiver that forwards GitHub organization events to Wazuh SIEM for security monitoring.

---

## Prerequisites

- Wazuh Manager installed and running
- Python 3 installed on the Wazuh server
- GitHub Organization admin access
- Port `9700` open on your server firewall

---

## Architecture

```
GitHub Organization
       │
       │  Webhook (HTTP POST)
       ▼
GitHub Webhook Receiver (Port 9700)
       │
       │  Unix Socket
       ▼
Wazuh Manager (/var/ossec/queue/sockets/queue)
       │
       ▼
Wazuh Dashboard (Alerts & Rules)
```

---

## Step 1 — Create the Webhook Receiver Script

```bash
sudo tee /opt/github-webhook-receiver.py << 'EOF'
#!/usr/bin/env python3
import http.server
import json
import socket
import hashlib
import hmac
import os

PORT = 9700
WEBHOOK_SECRET = "wazuh-github-secret-2026"
WAZUH_SOCKET = "/var/ossec/queue/sockets/queue"

def send_to_wazuh(event_type, payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    sender = payload.get("sender", {}).get("login", "unknown")
    org = payload.get("organization", {}).get("login", "")
    action = payload.get("action", event_type)

    event = {
        "integration": "github",
        "github": {
            "actor": sender,
            "org": org,
            "repo": repo,
            "action": f"{event_type}.{action}" if action else event_type,
            "event_type": event_type,
            "repository": repo,
            "sender": sender,
            "organization": org,
            "@timestamp": payload.get("head_commit", {}).get("timestamp", ""),
            "payload": payload
        }
    }
    msg = f"1:github_webhook:{json.dumps(event)}"
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sock.sendto(msg.encode()[:65535], WAZUH_SOCKET)
        sock.close()
        print(f"Sent to Wazuh: {event_type} from {repo} by {sender}")
    except Exception as e:
        print(f"Wazuh socket error: {e}")

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[{self.address_string()}] {fmt % args}")

    def do_POST(self):
        if self.path != "/webhook/github":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        sig_header = self.headers.get("X-Hub-Signature-256", "")
        expected = "sha256=" + hmac.new(
            WEBHOOK_SECRET.encode(), body, hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(sig_header, expected):
            print("Invalid signature - rejected")
            self.send_response(401)
            self.end_headers()
            return

        event_type = self.headers.get("X-GitHub-Event", "unknown")
        try:
            payload = json.loads(body)
            send_to_wazuh(event_type, payload)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        except Exception as e:
            print(f"Error: {e}")
            self.send_response(500)
            self.end_headers()

if __name__ == "__main__":
    print(f"GitHub Webhook Receiver running on port {PORT}")
    print(f"Webhook URL: http://<SERVERIP>:{PORT}/webhook/github")
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()
EOF
sudo systemctl restart github-webhook
```

---

## Step 2 — Update Server IP

Replace `<SERVER_IP>` with your actual Wazuh server IP:

```bash
sed -i 's/<OLDSERVER_IP>/YOUR_SERVER_IP/g' /opt/github-webhook-receiver.py
```

Verify:
```bash
grep "YOUR_SERVER_IP" /opt/github-webhook-receiver.py
```

---

## Step 3 — Create the systemd Service

```bash
sudo tee /etc/systemd/system/github-webhook.service << 'EOF'
[Unit]
Description=GitHub Webhook Receiver for Wazuh
After=network.target wazuh-manager.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/github-webhook-receiver.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start the service:
```bash
systemctl daemon-reload
systemctl enable github-webhook
systemctl start github-webhook
systemctl status github-webhook --no-pager
```

---

## Step 4 — Open Firewall Port

```bash
ufw allow 9700/tcp
ufw status | grep 9700
```

---

## Step 5 — Create Wazuh Decoder

```bash
tee /var/ossec/etc/decoders/github_webhook_decoder.xml << 'EOF'
<decoder name="github_webhook">
  <prematch>{"integration": "github"</prematch>
</decoder>

<decoder name="github_webhook_event">
  <parent>github_webhook</parent>
  <plugin_decoder>JSON_Decoder</plugin_decoder>
</decoder>
EOF
```

Restart Wazuh to load the decoder:
```bash
systemctl restart wazuh-manager
```

---

## Step 6 — Configure GitHub Webhook

1. Go to your GitHub Organization settings:
   ```
   https://github.com/organizations/<YOUR_ORG>/settings/hooks
   ```

2. Click **Add webhook** and fill in:

   | Field | Value |
   |---|---|
   | Payload URL | `http://<SERVER_IP>:9700/webhook/github` |
   | Content type | `application/json` |
   | Secret | `wazuh-github-secret-2026` |
   | Which events | **Send me everything** |

3. Click **Add webhook**

4. Verify — you should see **"Last delivery was successful"** ✅

---

## Step 7 — Verify Events Reaching Wazuh

Check the webhook receiver logs:
```bash
journalctl -u github-webhook -n 20 --no-pager
```

Check Wazuh alerts:
```bash
tail -f /var/ossec/logs/alerts/alerts.json | grep github
```

---

## Viewing Events in Wazuh Dashboard

Go to **Wazuh Dashboard → Security Events** and filter by:
```
rule.groups: github
```

### Key fields available for filtering

| Field | Description |
|---|---|
| `data.github.actor` | User who triggered the event |
| `data.github.org` | GitHub organization name |
| `data.github.repo` | Repository full name |
| `data.github.action` | Event action (e.g. push.created) |
| `data.github.event_type` | GitHub event type |

---

## Troubleshooting

**Webhook shows delivery failed:**
- Check port 9700 is open: `ufw status | grep 9700`
- Check service is running: `systemctl status github-webhook`

**Events not appearing in Wazuh:**
- Check socket permissions: `ls -la /var/ossec/queue/sockets/queue`
- Check Wazuh manager logs: `tail -f /var/ossec/logs/ossec.log`

**Invalid signature errors:**
- Ensure the `WEBHOOK_SECRET` in the script matches exactly what was entered in GitHub webhook settings

---

## Security Notes

- Change the default `WEBHOOK_SECRET` to a strong random value in production
- Consider placing the webhook receiver behind a reverse proxy with TLS for HTTPS
- Restrict port 9700 to GitHub's webhook IP ranges if possible
