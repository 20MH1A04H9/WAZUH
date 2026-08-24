# Wazuh Stack Log Pipeline (Fluent Bit → OpenSearch)

Ships logs from all three Wazuh components into searchable OpenSearch
indices via a single Fluent Bit instance.

Deployed on: AIwazuh.

| Component | Source | Index |
|---|---|---|
| wazuh-dashboard | journald (`wazuh-dashboard.service`) | `osd-access-logs` |
| wazuh-indexer | `/var/log/wazuh-indexer/wazuh-cluster_server.json` | `wazuh-indexer-logs` |
| wazuh-manager | `/var/ossec/logs/ossec.log` | `wazuh-manager-logs` |

---

## Architecture

```
wazuh-dashboard.service (journald)        wazuh-indexer                wazuh-manager
        │                              wazuh-cluster_server.json         ossec.log
        ▼                                       │                          │
  systemd input                             tail input                 tail input
        │                                       │                          │
   JSON parser                            JSON parser                regex parser
   + nest req/res                                                   (date, daemon, level, message)
        │                                       │                          │
        └───────────────────┬───────────────────┴──────────────┬───────────┘
                             ▼                                  ▼
                    Fluent Bit → OpenSearch output (wazuh-indexer, 127.0.0.1:9200)
```

All three pipelines run in **one** Fluent Bit instance/config — separate
`[INPUT]`/`[FILTER]`/`[OUTPUT]` blocks per source, routed by `Tag`/`Match`.

---

## Prerequisites

- Ubuntu server running `wazuh-dashboard`, `wazuh-indexer`, `wazuh-manager`
- Local `wazuh-indexer` (OpenSearch) on `127.0.0.1:9200`
- `wazuh-indexer` admin credentials
- `sudo` access
- Fluent Bit's systemd unit has no `User=` set (runs as root) — confirm
  with `systemctl show fluent-bit -p User`. If it's non-root on your
  build, that user needs read access to `/var/log/wazuh-indexer` and
  `/var/ossec/logs`.

---

## 1. Confirm service/unit names

```bash
systemctl list-units --all | grep -i wazuh-dashboard
systemctl list-units --all | grep -i wazuh-indexer
systemctl list-units --all | grep -i wazuh-manager
```

> journald's `SYSLOG_IDENTIFIER` for the dashboard (`opensearch-dashboards`)
> is **not** the unit name (`wazuh-dashboard.service`) — use the unit name
> in `Systemd_Filter`.

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

[PARSER]
    Name        wazuh_indexer_json
    Format      json
    Time_Key    timestamp
    Time_Format %Y-%m-%dT%H:%M:%S,%L%z
    Time_Keep   On

[PARSER]
    Name        wazuh_manager_ossec
    Format      regex
    Regex       ^(?<log_date>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) (?<daemon>[^:]+): (?<level>\w+): (?<message>.*)$
    Time_Key    log_date
    Time_Format %Y/%m/%d %H:%M:%S
    Time_Keep   On
EOF
```

## 4. Write fluent-bit.conf

Replace `<INDEXER_PASSWORD>` (3 occurrences) with this server's
`wazuh-indexer` admin password.

```bash
sudo tee /etc/fluent-bit/fluent-bit.conf > /dev/null << 'EOF'
[SERVICE]
    Flush           1
    Log_Level       info
    Parsers_File    /etc/fluent-bit/parsers.conf

# wazuh-dashboard (OSD access logs)
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

# wazuh-indexer (cluster server log, JSON)
[INPUT]
    Name              tail
    Tag               indexer.raw
    Path              /var/log/wazuh-indexer/wazuh-cluster_server.json
    Read_from_Head    Off
    Skip_Long_Lines   On
    Refresh_Interval  5

[FILTER]
    Name    parser
    Match   indexer.raw
    Key_Name log
    Parser  wazuh_indexer_json
    Reserve_Data On

[OUTPUT]
    Name            opensearch
    Match           indexer.raw
    Host            127.0.0.1
    Port            9200
    Index           wazuh-indexer-logs
    HTTP_User       admin
    HTTP_Passwd     <INDEXER_PASSWORD>
    Suppress_Type_Name On
    tls             On
    tls.verify      Off

# wazuh-manager (ossec.log, plaintext)
[INPUT]
    Name              tail
    Tag               manager.raw
    Path              /var/ossec/logs/ossec.log
    Read_from_Head    Off
    Skip_Long_Lines   On
    Refresh_Interval  5

[FILTER]
    Name    parser
    Match   manager.raw
    Key_Name log
    Parser  wazuh_manager_ossec
    Reserve_Data On

[OUTPUT]
    Name            opensearch
    Match           manager.raw
    Host            127.0.0.1
    Port            9200
    Index           wazuh-manager-logs
    HTTP_User       admin
    HTTP_Passwd     <INDEXER_PASSWORD>
    Suppress_Type_Name On
    tls             On
    tls.verify      Off
EOF

sudo chmod 640 /etc/fluent-bit/fluent-bit.conf
```

> **`Read_from_Head`/`Read_From_Tail` = `Off`** on all three inputs
> backfills whatever's already in the source (journal or file) on
> startup. Set to `On` later if you'd rather only capture new events
> going forward and avoid re-ingesting history on every restart.

## 5. Verify indexer credentials

```bash
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/_cluster/health?pretty"
```

## 6. Dry-run in foreground

```bash
sudo /opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf
```

Confirm no `[error]` lines across all three tags (`osd.raw`,
`indexer.raw`, `manager.raw`). `Ctrl+C` once satisfied.

## 7. Start as a service

```bash
sudo systemctl enable fluent-bit
sudo systemctl restart fluent-bit
sudo systemctl status fluent-bit
```

## 8. Confirm data is landing

```bash
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/osd-access-logs*/_count?pretty"
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/wazuh-indexer-logs*/_count?pretty"
curl -k -u admin:'<INDEXER_PASSWORD>' "https://127.0.0.1:9200/wazuh-manager-logs*/_count?pretty"
```

`wazuh-indexer-logs` may show a low count at first — the cluster server
log only writes on certain events, unlike the constant dashboard/manager
traffic. That's expected, not broken.

If `wazuh-manager-logs` shows `0` with zero shards, generate an event
first (e.g. `sudo systemctl restart wazuh-manager`) since `ossec.log`
only grows when a module logs something.

## 9. Add index patterns in the Wazuh dashboard UI

**Stack Management → Index Patterns → Create index pattern**, for each:

| Pattern | Time field |
|---|---|
| `osd-access-logs*` | `@timestamp` |
| `wazuh-indexer-logs*` | `@timestamp` |
| `wazuh-manager-logs*` | `@timestamp` |

Then **Discover** → switch the index pattern dropdown to browse each.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Sections 'multiline_parser' and 'parser' are not valid...` | Missing `Parsers_File` in `[SERVICE]` | Add `Parsers_File /etc/fluent-bit/parsers.conf` under `[SERVICE]` |
| `cp: cannot stat 'fluent-bit.conf'` | File doesn't exist on that host | Write configs directly with `tee` heredocs on the target server |
| `Unit opensearch-dashboards.service could not be found` | Wrong unit name assumed | Use `wazuh-dashboard.service`; journald's `SYSLOG_IDENTIFIER` differs from the unit name |
| Dashboard pipeline: service runs but no records land | Parser regex expecting a syslog wrapper that doesn't exist | Parse `MESSAGE` directly as JSON — no unwrap stage needed |
| `curl` returns `Unauthorized` (no JSON) | Wrong indexer password | Verify with `_cluster/health` before wiring into `fluent-bit.conf` |
| `_count` returns `0`, index doesn't exist | No new events since Fluent Bit started, and `Read_From_Tail`/`Read_from_Head` set to `On` | Set to `Off` and restart to backfill |
| Manager index count is `0` right after setup | `ossec.log` hasn't had a new line since Fluent Bit started | Generate a manager event (`sudo systemctl restart wazuh-manager`) or temporarily set `Read_from_Head On` |
| Still running default demo config (`cpu` input, `stdout` output) | Config file was never actually overwritten | `cat /etc/fluent-bit/fluent-bit.conf` to confirm before restarting |
| Fluent Bit can't read `/var/log/wazuh-indexer` or `/var/ossec/logs` | Non-root Fluent Bit user without group membership | Check `systemctl show fluent-bit -p User`; if non-root, add to `wazuh-indexer`/`wazuh` groups |

---

## Files

- `/etc/fluent-bit/fluent-bit.conf` — main pipeline config (contains
  indexer password — kept at `640` permissions)
- `/etc/fluent-bit/parsers.conf` — parser definitions for all three sources
