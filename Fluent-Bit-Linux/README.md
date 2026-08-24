# Wazuh Dashboard (OSD) Access Log Pipeline

Ships `wazuh-dashboard` (OpenSearch Dashboards) HTTP access logs from
`journald` into OpenSearch as a searchable index, using Fluent Bit.

Object Storage Daemon (Ceph OSD):Refers to the daemon process in distributed storage systems (like Ceph) that stores data, handles data replication, recovery, and scrubbing, and feeds cluster health/performance metrics into log and telemetry pipelines.

Deployed on: AIwazuh.

---

## Architecture

```
wazuh-dashboard.service (journald, SYSLOG_IDENTIFIER=opensearch-dashboards)
        │
        ▼
  Fluent Bit systemd input
        │  parser filter (JSON)
        │  nest filter (lift req.* → req_*)
        │  nest filter (lift res.* → res_*)
        ▼
  OpenSearch output → wazuh-indexer (127.0.0.1:9200)
        │
        ▼
  Index: osd-access-logs
```

---

## Prerequisites

- Ubuntu server running `wazuh-dashboard.service`
- Local `wazuh-indexer` (OpenSearch) on `127.0.0.1:9200`
- `wazuh-indexer` admin credentials
- `sudo` access

---

## 1. Confirm the dashboard unit name

Don't assume — verify on each server, since journald's `SYSLOG_IDENTIFIER`
(`opensearch-dashboards`) is **not** the same as the systemd unit name
(`wazuh-dashboard.service`).

```bash
systemctl list-units --all | grep -i wazuh-dashboard
```

## 2. Install Fluent Bit

```bash
curl https://packages.fluentbit.io/fluentbit.key | gpg --dearmor | sudo tee /usr/share/keyrings/fluentbit-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/ubuntu/$(lsb_release -cs) $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/fluent-bit.list
sudo apt-get update && sudo apt-get install -y fluent-bit
```

## 3. Write parsers.conf

```bash
sudo tee /etc/fluent-bit/parsers.conf > /dev/null << 'EOF'
[PARSER]
    Name        opensearch_dashboards_json
    Format      json
    Time_Key    @timestamp
    Time_Format %Y-%m-%dT%H:%M:%SZ
    Time_Keep   On
EOF
```

> The `systemd` input already delivers bare JSON in `MESSAGE` (no syslog
> wrapper to strip) — parse it directly.

## 4. Write fluent-bit.conf

Replace `<INDEXER_PASSWORD>` with this server's `wazuh-indexer` admin
password.

```bash
sudo tee /etc/fluent-bit/fluent-bit.conf > /dev/null << 'EOF'
[SERVICE]
    Flush           1
    Log_Level       info
    Parsers_File    /etc/fluent-bit/parsers.conf

[INPUT]
    Name              systemd
    Tag               osd.raw
    Systemd_Filter    _SYSTEMD_UNIT=wazuh-dashboard.service
    Read_From_Tail    Off

[FILTER]
    Name    parser
    Match   osd.raw
    Key_Name MESSAGE
    Parser  opensearch_dashboards_json
    Reserve_Data On

[FILTER]
    Name    nest
    Match   osd.raw
    Operation lift
    Nested_under req
    Add_prefix req_

[FILTER]
    Name    nest
    Match   osd.raw
    Operation lift
    Nested_under res
    Add_prefix res_

[OUTPUT]
    Name            opensearch
    Match           osd.raw
    Host            127.0.0.1
    Port            9200
    Index           osd-access-logs
    HTTP_User       admin
    HTTP_Passwd     <INDEXER_PASSWORD>
    Suppress_Type_Name On
    tls             On
    tls.verify      Off
EOF

sudo chmod 640 /etc/fluent-bit/fluent-bit.conf
```

> **`Read_From_Tail Off`** backfills existing journal entries on start —
> confirmed necessary on a fresh deploy, since `On` with no new dashboard
> traffic yields zero indexed docs. Switch to `On` later if you'd rather
> not re-ingest journal history on every restart.

## 5. Verify indexer credentials

```bash
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/_cluster/health?pretty"
```

Should return cluster JSON, not `Unauthorized`.

## 6. Dry-run in foreground

```bash
sudo /opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf
```

Confirm no `[error]` lines. `Ctrl+C` once satisfied.

## 7. Start as a service

```bash
sudo systemctl enable fluent-bit
sudo systemctl restart fluent-bit
sudo systemctl status fluent-bit
```

## 8. Confirm data is landing

```bash
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/osd-access-logs*/_count?pretty"
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/osd-access-logs*/_search?pretty&size=1&sort=@timestamp:desc"
```

Look for flattened fields: `req_url`, `req_method`, `req_remoteAddress`,
`res_statusCode`, `res_responseTime`, `res_contentLength`.

## 9. Add index pattern in the Wazuh dashboard UI

1. **Stack Management → Index Patterns → Create index pattern**
2. Name: `osd-access-logs*`
3. Time field: `@timestamp`
4. **Discover** → switch index pattern to `osd-access-logs*`

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Sections 'multiline_parser' and 'parser' are not valid...` | Missing `Parsers_File` in `[SERVICE]` | Add `Parsers_File /etc/fluent-bit/parsers.conf` under `[SERVICE]` |
| `cp: cannot stat 'fluent-bit.conf'` | File doesn't exist on that host | Write configs directly with `tee` heredocs on the target server |
| `Unit opensearch-dashboards.service could not be found` | Wrong unit name assumed | Use `wazuh-dashboard.service`; journald's `SYSLOG_IDENTIFIER` differs from the unit name |
| Service runs but no records land | Parser regex expecting a syslog wrapper that doesn't exist | Parse `MESSAGE` directly as JSON — no unwrap stage needed |
| `curl` returns `Unauthorized` (no JSON) | Wrong indexer password | Verify with `_cluster/health` before wiring into `fluent-bit.conf` |
| `_count` returns `0`, index doesn't exist | No dashboard traffic since Fluent Bit started, and `Read_From_Tail On` | Set `Read_From_Tail Off` and restart to backfill from journal |
| Still running default demo config (`cpu` input, `stdout` output) | Config file was never actually overwritten | `cat /etc/fluent-bit/fluent-bit.conf` to confirm before restarting |

---

## Files

- `/etc/fluent-bit/fluent-bit.conf` — main pipeline config (contains
  indexer password — kept at `640` permissions)
- `/etc/fluent-bit/parsers.conf` — JSON parser definition
