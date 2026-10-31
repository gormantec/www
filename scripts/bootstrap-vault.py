#!/usr/bin/env python3
"""Build the docker-iot bootstrap vault from the current env.json + .env.

Writes KEY=value lines to ~/.config/iot/bootstrap.env with mode 0600.
Never prints values - only key names and a sha256 prefix for comparison.
"""
import json
import os
import sys

KEYS = [
    "TUNNEL_TOKEN",
    "NODE_AUTH_TOKEN",
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "READ_PACKAGES_GITHUB_PAT",
    "DOCDB_NAS_PASSWORD",
    "GATEKEEPER_SECRET",
    "DOCDB_IOT_PASS",
    "SYNOLOGY_DB_PASS",
]

envjson_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/envjson.json"
dotenv_path = sys.argv[2] if len(sys.argv) > 2 else "/home/docker/build/docker-iot/.env"
out_path = os.path.expanduser("~/.config/iot/bootstrap.env")

vals = {}

if os.path.exists(envjson_path):
    try:
        with open(envjson_path) as fh:
            data = json.load(fh)
        items = data if isinstance(data, list) else [
            {"Name": k, "Value": v} for k, v in data.items()
        ]
        for entry in items:
            name = entry.get("Name")
            if name:
                vals[name] = entry.get("Value", "")
    except Exception as exc:  # noqa: BLE001 - report and continue
        print("  env.json unreadable:", exc)

# The operator's .env wins for any key it defines: it is the file they edit.
if os.path.exists(dotenv_path):
    try:
        with open(dotenv_path) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key in KEYS:
                    vals[key] = value
    except Exception as exc:  # noqa: BLE001
        print("  .env unreadable:", exc)

os.makedirs(os.path.dirname(out_path), exist_ok=True)

lines = [
    "# docker-iot bootstrap credentials - the ONLY maintained copy.",
    "# mode 0600. Not in git, not on the NAS share, not inside a Docker volume.",
    "#",
    "# Read by install-iot.sh, which treats this file as authoritative and",
    "# treats env.json as non-secret config only. A disaster-recovery restore",
    "# means putting this file back on the host (or IOT_VAULT=/path/to/file)",
    "# and re-running the installer.",
]

fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as fh:
    for line in lines:
        fh.write(line + "\n")
    for key in KEYS:
        value = vals.get(key)
        if value and value not in ("null", "undefined", key):
            fh.write("%s=%s\n" % (key, value))

os.chmod(out_path, 0o600)

print("  vault written:", out_path)
for key in KEYS:
    value = vals.get(key)
    state = "set" if value else "MISSING"
    print("    %-26s %s" % (key, state))
