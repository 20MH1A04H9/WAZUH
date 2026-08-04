#!/usr/bin/env python3

import os
import json
import time
import socket
import hashlib
import argparse
import datetime
import traceback
import requests
from typing import Dict, Any, List

API_KEY = os.environ.get("SHODAN_API_KEY", "PASTE_YOUR_SHODAN_API_KEY_HERE")

ASSET_FILE = "/var/ossec/etc/lists/critical_servers"
LOG_FILE = "/var/log/wazuh-shodan-critical.log"
STATE_FILE = "/var/ossec/integrations/shodan_asset_state.json"
HEALTH_FILE = "/var/ossec/integrations/shodan_last_run.json"

SHODAN_HOST_URL = "https://api.shodan.io/shodan/host/{}"
SHODAN_INFO_URL = "https://api.shodan.io/api-info"

REQUEST_TIMEOUT = 30
REQUEST_SLEEP_SECONDS = 1
MISSING_RUN_THRESHOLD_HOURS = 26

HIGH_RISK_PORTS = {
    21, 22, 23, 25, 110, 135, 139, 143, 389, 445,
    1433, 1521, 2049, 3306, 3389, 5432, 5900,
    5985, 5986, 6379, 9200, 9300, 27017
}


def utc_now():
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def write_event(event):
    event["integration"] = "shodan"
    event["event_time"] = utc_now()
    with open(LOG_FILE, "a") as f:
        f.write(json.dumps(event, sort_keys=True) + "\n")


def load_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return {}


def save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


def sha256_json(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def diff_lists(old, new):
    old_set = set(old or [])
    new_set = set(new or [])
    return {
        "added": sorted(list(new_set - old_set)),
        "removed": sorted(list(old_set - new_set))
    }


def auto_asset_type(target):
    try:
        socket.inet_aton(target)
        return "ip"
    except Exception:
        return "fqdn"


def parse_assets():
    assets = []
    with open(ASSET_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            if ":" not in line:
                write_event({
                    "event_type": "config_error",
                    "severity": "high",
                    "message": "Invalid asset line",
                    "raw_line": line
                })
                continue

            target, meta = line.split(":", 1)
            parts = meta.split("|")
            asset_type = parts[5].strip().lower() if len(parts) > 5 else auto_asset_type(target)

            assets.append({
                "target": target.strip(),
                "asset_ip": target.strip() if asset_type == "ip" else None,
                "fqdn": target.strip() if asset_type == "fqdn" else None,
                "asset_name": parts[0].strip() if len(parts) > 0 else "unknown",
                "business_unit": parts[1].strip() if len(parts) > 1 else "unknown",
                "environment": parts[2].strip() if len(parts) > 2 else "unknown",
                "criticality": parts[3].strip() if len(parts) > 3 else "unknown",
                "owner": parts[4].strip() if len(parts) > 4 else "unknown",
                "asset_type": asset_type
            })
    return assets


def base_asset_event(asset):
    return {
        "target": asset.get("target"),
        "asset_ip": asset.get("asset_ip"),
        "fqdn": asset.get("fqdn"),
        "asset_type": asset.get("asset_type"),
        "asset_name": asset.get("asset_name"),
        "business_unit": asset.get("business_unit"),
        "environment": asset.get("environment"),
        "criticality": asset.get("criticality"),
        "owner": asset.get("owner")
    }


def check_api_info():
    try:
        r = requests.get(SHODAN_INFO_URL, params={"key": API_KEY}, timeout=REQUEST_TIMEOUT)

        if r.status_code == 200:
            data = r.json()
            query_credits = data.get("query_credits")

            write_event({
                "event_type": "integration_health",
                "severity": "info",
                "status": "api_key_valid",
                "plan": data.get("plan"),
                "query_credits": query_credits,
                "scan_credits": data.get("scan_credits"),
                "monitored_ips": data.get("monitored_ips"),
                "message": "Shodan API key is valid"
            })

            if isinstance(query_credits, int) and query_credits <= 10:
                write_event({
                    "event_type": "api_quota_low",
                    "severity": "high",
                    "query_credits": query_credits,
                    "message": "Shodan API quota is low"
                })
            return

        write_event({
            "event_type": "integration_health",
            "severity": "critical",
            "status": "expired_or_invalid_api_key" if r.status_code in [401, 403] else "api_key_check_failed",
            "http_status": r.status_code,
            "message": "Shodan API key check failed",
            "shodan_api_failed": True
        })

    except Exception as e:
        write_event({
            "event_type": "integration_health",
            "severity": "critical",
            "status": "api_check_exception",
            "error": str(e),
            "message": "Shodan API health check exception",
            "shodan_api_failed": True
        })


def shodan_host_lookup(ip):
    try:
        r = requests.get(
            SHODAN_HOST_URL.format(ip),
            params={"key": API_KEY, "minify": "false"},
            timeout=REQUEST_TIMEOUT
        )

        if r.status_code == 200:
            return "found", r.json()

        if r.status_code == 404:
            return "not_found", {}

        return f"api_error_{r.status_code}", {
            "http_status": r.status_code,
            "response": r.text[:300]
        }

    except Exception as e:
        return "exception", {"error": str(e)}


def resolve_fqdn(fqdn):
    try:
        results = socket.getaddrinfo(fqdn, None)
        return sorted(list(set([r[4][0] for r in results])))
    except Exception as e:
        write_event({
            "event_type": "dns_resolution_error",
            "severity": "high",
            "fqdn": fqdn,
            "error": str(e),
            "message": "Failed to resolve FQDN"
        })
        return []


def empty_snapshot():
    return {
        "exposed": False,
        "open_ports": [],
        "vulnerabilities": [],
        "service_fingerprints": [],
        "ssl_fingerprints": [],
        "hostnames": [],
        "domains": []
    }


def extract_ssl_cert(service):
    ssl_data = service.get("ssl", {})
    if not isinstance(ssl_data, dict):
        return {}

    cert = ssl_data.get("cert", {})
    if not isinstance(cert, dict):
        return {}

    fingerprint = cert.get("fingerprint", {}) or {}

    return {
        "port": service.get("port"),
        "serial": cert.get("serial"),
        "fingerprint_sha256": fingerprint.get("sha256"),
        "expired": cert.get("expired"),
        "expires": cert.get("expires"),
        "self_signed": ssl_data.get("self_signed")
    }


def normalize_host_data(data):
    open_ports = sorted(list(set(data.get("ports", []))))

    raw_vulns = data.get("vulns", {})
    if isinstance(raw_vulns, dict):
        vulnerabilities = sorted(raw_vulns.keys())
    elif isinstance(raw_vulns, list):
        vulnerabilities = sorted(raw_vulns)
    else:
        vulnerabilities = []

    service_fingerprints = []
    ssl_fingerprints = []

    for item in data.get("data", []):
        service_fingerprints.append(sha256_json({
            "port": item.get("port"),
            "transport": item.get("transport"),
            "product": item.get("product"),
            "version": item.get("version"),
            "module": item.get("_shodan", {}).get("module")
        }))

        cert = extract_ssl_cert(item)
        if cert:
            cert_fp = cert.get("fingerprint_sha256") or cert.get("serial")
            if cert_fp:
                ssl_fingerprints.append(f"{cert.get('port')}:{cert_fp}")

    return {
        "exposed": True,
        "open_ports": open_ports,
        "vulnerabilities": vulnerabilities,
        "service_fingerprints": sorted(service_fingerprints),
        "ssl_fingerprints": sorted(ssl_fingerprints),
        "hostnames": data.get("hostnames", []),
        "domains": data.get("domains", []),
        "org": data.get("org"),
        "isp": data.get("isp"),
        "asn": data.get("asn"),
        "country": data.get("country_name"),
        "city": data.get("city"),
        "last_update": data.get("last_update")
    }


def exposure_fingerprint(snapshot):
    return sha256_json({
        "exposed": snapshot.get("exposed"),
        "open_ports": snapshot.get("open_ports", []),
        "vulnerabilities": snapshot.get("vulnerabilities", []),
        "service_fingerprints": snapshot.get("service_fingerprints", []),
        "ssl_fingerprints": snapshot.get("ssl_fingerprints", [])
    })


def calculate_risk(asset, snapshot):
    if snapshot.get("vulnerabilities"):
        return "critical"

    if any(p in HIGH_RISK_PORTS for p in snapshot.get("open_ports", [])):
        return "critical"

    if snapshot.get("exposed") and str(asset.get("criticality", "")).lower() in ["tier1", "critical", "high"]:
        return "high"

    if snapshot.get("exposed"):
        return "medium"

    return "low"


def process_ip(asset, ip, state_key, old_state):
    previous = old_state.get(state_key, {})
    previous_snapshot = previous.get("snapshot", empty_snapshot())

    base = base_asset_event(asset)
    base.update({
        "event_type": "asset_exposure_check",
        "lookup_ip": ip
    })

    status, data = shodan_host_lookup(ip)
    base["shodan_status"] = status

    if status == "found":
        snapshot = normalize_host_data(data)
    elif status == "not_found":
        snapshot = empty_snapshot()
    else:
        event = dict(base)
        event.update({
            "severity": "critical",
            "exposed": "unknown",
            "risk": "unknown",
            "message": "Shodan API lookup failed",
            "shodan_api_failed": True
        })
        write_event(event)
        return previous

    current_fp = exposure_fingerprint(snapshot)
    previous_fp = previous.get("fingerprint")

    first_appeared = previous_fp is None and snapshot.get("exposed") is True
    became_exposed = previous_snapshot.get("exposed") is False and snapshot.get("exposed") is True
    became_not_exposed = previous_snapshot.get("exposed") is True and snapshot.get("exposed") is False
    exposure_changed = previous_fp is not None and previous_fp != current_fp

    first_seen_exposed = previous.get("first_seen_exposed")
    last_seen_exposed = previous.get("last_seen_exposed")

    if snapshot.get("exposed") and not first_seen_exposed:
        first_seen_exposed = utc_now()

    if snapshot.get("exposed"):
        last_seen_exposed = utc_now()

    port_diff = diff_lists(previous_snapshot.get("open_ports", []), snapshot.get("open_ports", []))
    cve_diff = diff_lists(previous_snapshot.get("vulnerabilities", []), snapshot.get("vulnerabilities", []))
    svc_diff = diff_lists(previous_snapshot.get("service_fingerprints", []), snapshot.get("service_fingerprints", []))
    ssl_diff = diff_lists(previous_snapshot.get("ssl_fingerprints", []), snapshot.get("ssl_fingerprints", []))

    risk = calculate_risk(asset, snapshot)

    event = dict(base)
    event.update(snapshot)
    event.update({
        "severity": "critical" if risk == "critical" or first_appeared or became_exposed or cve_diff["added"] else "high" if snapshot.get("exposed") or exposure_changed else "info",
        "risk": risk,
        "first_seen_exposed": first_seen_exposed,
        "last_seen_exposed": last_seen_exposed,
        "first_appeared_in_shodan": first_appeared,
        "became_exposed": became_exposed,
        "became_not_exposed": became_not_exposed,
        "exposure_changed": exposure_changed,
        "new_ports": port_diff["added"],
        "closed_ports": port_diff["removed"],
        "new_vulnerabilities": cve_diff["added"],
        "resolved_vulnerabilities": cve_diff["removed"],
        "new_services": svc_diff["added"],
        "removed_services": svc_diff["removed"],
        "new_ssl_certificates": ssl_diff["added"],
        "removed_ssl_certificates": ssl_diff["removed"],
        "services_changed": bool(svc_diff["added"] or svc_diff["removed"]),
        "ssl_changed": bool(ssl_diff["added"] or ssl_diff["removed"]),
        "has_new_ports": bool(port_diff["added"]),
        "has_closed_ports": bool(port_diff["removed"]),
        "has_new_vulnerabilities": bool(cve_diff["added"]),
        "has_resolved_vulnerabilities": bool(cve_diff["removed"]),
        "has_new_services": bool(svc_diff["added"]),
        "has_removed_services": bool(svc_diff["removed"]),
        "has_new_ssl_certificates": bool(ssl_diff["added"]),
        "has_removed_ssl_certificates": bool(ssl_diff["removed"]),
        "shodan_api_failed": False,
        "message": f"Shodan check completed for {asset.get('asset_name')} / {ip}"
    })

    write_event(event)

    return {
        "fingerprint": current_fp,
        "first_seen_exposed": first_seen_exposed,
        "last_seen_exposed": last_seen_exposed,
        "last_checked": utc_now(),
        "snapshot": snapshot
    }


def process_fqdn(asset, old_state, new_state):
    fqdn = asset["fqdn"]
    fqdn_key = f"fqdn:{fqdn}"

    previous = old_state.get(fqdn_key, {})
    previous_ips = previous.get("resolved_ips", [])

    resolved_ips = resolve_fqdn(fqdn)
    dns_diff = diff_lists(previous_ips, resolved_ips)

    event = base_asset_event(asset)
    event.update({
        "event_type": "dns_monitoring",
        "severity": "high" if dns_diff["added"] or dns_diff["removed"] else "info",
        "resolved_ips": resolved_ips,
        "new_dns_ips": dns_diff["added"],
        "removed_dns_ips": dns_diff["removed"],
        "dns_changed": bool(dns_diff["added"] or dns_diff["removed"]),
        "has_new_dns_ips": bool(dns_diff["added"]),
        "has_removed_dns_ips": bool(dns_diff["removed"]),
        "message": f"DNS monitoring completed for {fqdn}"
    })
    write_event(event)

    for ip in resolved_ips:
        ip_asset = dict(asset)
        ip_asset["asset_ip"] = ip
        ip_state_key = f"fqdn:{fqdn}:ip:{ip}"
        new_state[ip_state_key] = process_ip(ip_asset, ip, ip_state_key, old_state)
        time.sleep(REQUEST_SLEEP_SECONDS)

    new_state[fqdn_key] = {
        "resolved_ips": resolved_ips,
        "first_seen": previous.get("first_seen") or utc_now(),
        "last_checked": utc_now()
    }


def update_health(status):
    save_json(HEALTH_FILE, {"last_run": utc_now(), "status": status})


def check_missing_daily_execution():
    health = load_json(HEALTH_FILE)
    last_run = health.get("last_run")

    if not last_run:
        write_event({
            "event_type": "missing_daily_execution",
            "severity": "critical",
            "message": "No previous Shodan run found"
        })
        return

    last_dt = datetime.datetime.strptime(last_run.replace("Z", ""), "%Y-%m-%dT%H:%M:%S")
    age_hours = (datetime.datetime.utcnow() - last_dt).total_seconds() / 3600

    if age_hours > MISSING_RUN_THRESHOLD_HOURS:
        write_event({
            "event_type": "missing_daily_execution",
            "severity": "critical",
            "last_run": last_run,
            "age_hours": round(age_hours, 2),
            "message": "Shodan integration missed daily execution"
        })
    else:
        write_event({
            "event_type": "integration_health",
            "severity": "info",
            "status": "daily_execution_ok",
            "last_run": last_run,
            "age_hours": round(age_hours, 2),
            "message": "Daily execution is healthy"
        })


def run_monitoring():
    old_state = load_json(STATE_FILE)
    new_state = {}

    write_event({
        "event_type": "integration_run_start",
        "severity": "info",
        "message": "Shodan critical asset monitoring started"
    })

    check_api_info()

    assets = parse_assets()
    if not assets:
        write_event({
            "event_type": "config_error",
            "severity": "critical",
            "message": "No assets found"
        })
        update_health("failed_no_assets")
        return

    for asset in assets:
        if asset["asset_type"] == "fqdn":
            process_fqdn(asset, old_state, new_state)
        else:
            ip = asset["asset_ip"]
            new_state[f"ip:{ip}"] = process_ip(asset, ip, f"ip:{ip}", old_state)

        time.sleep(REQUEST_SLEEP_SECONDS)

    save_json(STATE_FILE, new_state)
    update_health("success")

    write_event({
        "event_type": "integration_run_complete",
        "severity": "info",
        "assets_checked": len(assets),
        "message": "Shodan critical asset monitoring completed"
    })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-health", action="store_true")
    args = parser.parse_args()

    try:
        if args.check_health:
            check_missing_daily_execution()
        else:
            run_monitoring()
    except Exception as e:
        write_event({
            "event_type": "script_execution_failure",
            "severity": "critical",
            "error": str(e),
            "traceback": traceback.format_exc()[-2000:],
            "message": "Shodan script failed"
        })
        update_health("failed_exception")


if __name__ == "__main__":
    main()
