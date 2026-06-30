#!/usr/bin/env bash
set -euo pipefail

args_file="${1:-${HOME}/scripts/goxray_cli_args}"

python3 - "$args_file" <<'PY'
import json
import os
import socket
import sys
from urllib.parse import parse_qs, unquote, urlparse

with open(sys.argv[1], "r", encoding="utf-8") as f:
    url = f.read().strip()

parsed = urlparse(url)
if parsed.scheme != "vless":
    raise SystemExit("expected vless:// URL")

query = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
server_name = query.get("sni") or parsed.hostname
short_id = query.get("sid", "")

server_address = os.environ.get("VPN_SERVER_ADDRESS") or parsed.hostname
if server_address == parsed.hostname:
    try:
        for family, _, _, _, sockaddr in socket.getaddrinfo(parsed.hostname, parsed.port or 443, socket.AF_INET, socket.SOCK_STREAM):
            if family == socket.AF_INET:
                server_address = sockaddr[0]
                break
    except OSError:
        pass

github_direct_domains = [
    "github.com",
    "github.blog",
    "github.dev",
    "github.io",
    "githubapp.com",
    "githubassets.com",
    "githubcopilot.com",
    "githubstatus.com",
    "githubusercontent.com",
]

direct_domain_suffixes = github_direct_domains + [
    "ru",
]

github_direct_hostnames = [
    "api.github.com",
    "avatars.githubusercontent.com",
    "codeload.github.com",
    "gist.github.com",
    "gist.githubusercontent.com",
    "github.com",
    "github.githubassets.com",
    "objects.githubusercontent.com",
    "raw.githubusercontent.com",
]

github_core_cidrs = [
    "4.208.26.192/28",
    "4.225.11.192/28",
    "4.228.31.144/28",
    "4.237.22.32/28",
    "13.107.5.93/32",
    "20.26.156.208/28",
    "20.27.177.112/28",
    "20.29.134.16/28",
    "20.87.245.0/29",
    "20.175.192.144/28",
    "20.199.39.224/28",
    "20.200.245.240/28",
    "20.201.28.144/28",
    "20.205.243.160/28",
    "20.207.73.80/28",
    "20.217.135.0/29",
    "20.233.83.144/28",
    "20.250.119.64/32",
    "52.140.63.241/32",
    "52.175.140.176/32",
    "138.91.182.224/32",
    "140.82.112.0/20",
    "143.55.64.0/20",
    "185.199.108.0/22",
    "192.30.252.0/22",
]


def resolved_host_cidrs(hostnames):
    cidrs = set()
    for hostname in hostnames:
        try:
            addresses = socket.getaddrinfo(hostname, 443, socket.AF_INET, socket.SOCK_STREAM)
        except OSError:
            continue
        for family, _, _, _, sockaddr in addresses:
            if family == socket.AF_INET:
                cidrs.add(f"{sockaddr[0]}/32")
    return sorted(cidrs)


github_direct_cidrs = sorted(set(github_core_cidrs + resolved_host_cidrs(github_direct_hostnames)))

config = {
    "log": {
        "level": "warn"
    },
    "dns": {
        "servers": [
            {
                "type": "local",
                "tag": "local"
            },
            {
                "type": "https",
                "tag": "cloudflare",
                "server": "1.1.1.1",
                "server_port": 443,
                "path": "/dns-query",
                "detour": "proxy"
            }
        ],
        "rules": [
            {
                "domain": [
                    parsed.hostname
                ],
                "action": "route",
                "server": "local"
            }
        ],
        "final": "cloudflare",
        "strategy": "prefer_ipv4"
    },
    "inbounds": [
        {
            "type": "tun",
            "tag": "tun-in",
            "interface_name": "tun0",
            "address": [
                "198.18.0.1/30"
            ],
            "mtu": 1500,
            "auto_route": True,
            "auto_redirect": True,
            "strict_route": True,
            "stack": "system",
            "sniff": False
        },
        {
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "127.0.0.1",
            "listen_port": 2080
        }
    ],
    "outbounds": [
        {
            "type": "vless",
            "tag": "proxy",
            "server": server_address,
            "server_port": parsed.port or 443,
            "uuid": unquote(parsed.username or ""),
            "flow": query.get("flow", "xtls-rprx-vision"),
            "network": query.get("type", "tcp"),
            "packet_encoding": "xudp",
            "domain_resolver": "local",
            "tls": {
                "enabled": True,
                "server_name": server_name,
                "utls": {
                    "enabled": True,
                    "fingerprint": query.get("fp", "chrome")
                },
                "reality": {
                    "enabled": query.get("security") == "reality",
                    "public_key": query.get("pbk", ""),
                    "short_id": short_id
                }
            }
        },
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ],
    "route": {
        "auto_detect_interface": True,
        "rules": [
            {
                "port": 53,
                "action": "hijack-dns"
            },
            {
                "protocol": "dns",
                "action": "hijack-dns"
            },
            {
                "domain": github_direct_domains,
                "domain_suffix": direct_domain_suffixes,
                "action": "route",
                "outbound": "direct"
            },
            {
                "ip_cidr": github_direct_cidrs,
                "action": "route",
                "outbound": "direct"
            },
            {
                "ip_cidr": [
                    "10.0.0.0/8",
                    "172.16.0.0/12",
                    "192.168.0.0/16",
                    "127.0.0.0/8",
                    "169.254.0.0/16",
                    "224.0.0.0/4",
                    "::1/128",
                    "fc00::/7",
                    "fe80::/10"
                ],
                "action": "route",
                "outbound": "direct"
            }
        ],
        "final": "proxy"
    }
}

print(json.dumps(config, indent=2, ensure_ascii=False))
PY
