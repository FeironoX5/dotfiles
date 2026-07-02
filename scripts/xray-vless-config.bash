#!/usr/bin/env bash
set -euo pipefail

args_file="${1:-${HOME}/scripts/goxray_cli_args}"

python3 - "$args_file" <<'PY'
import base64
import json
import os
import re
import shlex
import socket
import sys
import urllib.request
from urllib.parse import parse_qs, unquote, urlparse


def getenv_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def getenv_int(name, default):
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return int(value)


def decode_subscription_text(raw):
    candidates = [raw]
    compact = "".join(raw.split())
    if compact:
        padded = compact + "=" * (-len(compact) % 4)
        try:
            decoded = base64.b64decode(padded).decode("utf-8", "replace")
        except Exception:
            decoded = ""
        if decoded:
            candidates.append(decoded)
    return candidates


def fetch_subscription(url):
    timeout = getenv_int("VPN_SUBSCRIPTION_TIMEOUT", 20)
    user_agent = os.environ.get("VPN_SUBSCRIPTION_USER_AGENT", "Xray")
    request = urllib.request.Request(url, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def extract_vless_urls(raw):
    urls = []
    seen = set()
    for text in decode_subscription_text(raw):
        for match in re.finditer(r"vless://[^\s]+", text):
            url = match.group(0).strip()
            if url not in seen:
                seen.add(url)
                urls.append(url)
    return urls


def read_vless_urls(path):
    with open(path, "r", encoding="utf-8") as args:
        raw = args.read().strip()

    urls = extract_vless_urls(raw)
    if urls:
        return urls

    try:
        tokens = shlex.split(raw, comments=False)
    except ValueError:
        tokens = raw.split()

    for token in tokens:
        parsed = urlparse(token)
        if parsed.scheme in {"http", "https"}:
            urls = extract_vless_urls(fetch_subscription(token))
            if urls:
                return urls

    raise SystemExit(f"no vless:// URL found in {path}")


def profile_name(url):
    fragment = urlparse(url).fragment
    return unquote(fragment.replace("+", " "))


def profile_sort_key(url):
    parsed = urlparse(url)
    query = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
    network = query.get("type") or query.get("network") or "tcp"
    security = query.get("security", "none")
    flow = query.get("flow", "")
    host = parsed.hostname or ""

    score = 100
    if security == "reality" and network == "tcp" and flow == "xtls-rprx-vision":
        score = 0
    elif security == "tls" and network == "tcp":
        score = 10
    elif network == "xhttp":
        score = 20
    elif security in {"tls", "none"}:
        score = 30
    return (score, host, profile_name(url))


def select_vless_url(urls):
    index = os.environ.get("VPN_PROFILE_INDEX")
    if index:
        try:
            selected = urls[int(index) - 1]
        except (IndexError, ValueError):
            raise SystemExit(f"VPN_PROFILE_INDEX is out of range: {index}") from None
        return selected

    pattern = os.environ.get("VPN_PROFILE_PATTERN")
    if pattern:
        expression = re.compile(pattern, re.IGNORECASE)
        for url in urls:
            parsed = urlparse(url)
            haystack = "\n".join([profile_name(url), parsed.hostname or "", url])
            if expression.search(haystack):
                return url
        raise SystemExit(f"no subscription profile matched VPN_PROFILE_PATTERN={pattern!r}")

    return sorted(urls, key=profile_sort_key)[0]


def first_ipv4(hostname, port):
    try:
        addresses = socket.getaddrinfo(hostname, port, socket.AF_INET, socket.SOCK_STREAM)
    except OSError:
        return None

    for family, _, _, _, sockaddr in addresses:
        if family == socket.AF_INET:
            return sockaddr[0]
    return None


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


def split_csv(value):
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


url = select_vless_url(read_vless_urls(sys.argv[1]))
parsed = urlparse(url)
if parsed.scheme != "vless":
    raise SystemExit("expected vless:// URL")
if not parsed.hostname:
    raise SystemExit("vless URL is missing host")

query = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
server_port = parsed.port or 443
server_name = query.get("sni") or query.get("serverName") or parsed.hostname
uuid = unquote(parsed.username or "")
if not uuid:
    raise SystemExit("vless URL is missing UUID")

security = query.get("security", "none")
server_address = os.environ.get("VPN_SERVER_ADDRESS") or parsed.hostname
if server_address == parsed.hostname and getenv_bool("VPN_RESOLVE_SERVER_ADDRESS", True):
    server_address = first_ipv4(parsed.hostname, server_port) or server_address

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

direct_domain_rules = [f"domain:{domain}" for domain in github_direct_domains]
direct_domain_rules.append("regexp:(^|\\.)ru$")

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

github_direct_cidrs = sorted(set(github_core_cidrs + resolved_host_cidrs(github_direct_hostnames)))
private_cidrs = [
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "224.0.0.0/4",
    "240.0.0.0/4",
]

tun_iface = os.environ.get("VPN_TUN_IFACE", "xray0")
outbound_mark = getenv_int("VPN_OUTBOUND_MARK", 2)
bind_to_device = os.environ.get("VPN_BIND_TO_DEVICE", "")

sockopt = {
    "tcpFastOpen": getenv_bool("VPN_TCP_FAST_OPEN", False),
    "tcpKeepAliveInterval": getenv_int("VPN_TCP_KEEPALIVE_INTERVAL", 60),
}
if outbound_mark > 0:
    sockopt["mark"] = outbound_mark
if bind_to_device:
    sockopt["bindToDevice"] = bind_to_device

network = query.get("type") or query.get("network") or "tcp"
stream_settings = {
    "network": network,
    "security": security if security in {"tls", "reality"} else "none",
    "sockopt": sockopt,
}

if security == "reality":
    stream_settings["realitySettings"] = {
        "serverName": server_name,
        "fingerprint": query.get("fp", "chrome"),
        "publicKey": query.get("pbk", ""),
        "shortId": query.get("sid", ""),
        "spiderX": query.get("spx", ""),
    }
elif security == "tls":
    tls_settings = {
        "serverName": server_name,
        "allowInsecure": getenv_bool("VPN_TLS_ALLOW_INSECURE", False),
    }
    alpn = split_csv(query.get("alpn", ""))
    if alpn:
        tls_settings["alpn"] = alpn
    stream_settings["tlsSettings"] = tls_settings

if network == "ws":
    headers = {}
    if query.get("host"):
        headers["Host"] = query["host"]
    stream_settings["wsSettings"] = {
        "path": query.get("path", "/"),
        "headers": headers,
    }
elif network in {"http", "h2"}:
    http_settings = {}
    hosts = split_csv(query.get("host", ""))
    if hosts:
        http_settings["host"] = hosts
    if query.get("path"):
        http_settings["path"] = query["path"]
    stream_settings["httpSettings"] = http_settings
elif network == "grpc":
    stream_settings["grpcSettings"] = {
        "serviceName": query.get("serviceName", ""),
        "multiMode": query.get("mode") == "multi",
    }
elif network == "xhttp":
    xhttp_settings = {
        "path": query.get("path", "/"),
        "mode": query.get("mode", "auto"),
    }
    if query.get("host"):
        xhttp_settings["host"] = query["host"]
    stream_settings["xhttpSettings"] = xhttp_settings

vless_user = {
    "id": uuid,
    "encryption": query.get("encryption", "none"),
}
if query.get("flow"):
    vless_user["flow"] = query["flow"]

sniffing = {
    "enabled": True,
    "destOverride": ["http", "tls", "quic"],
    "metadataOnly": False,
}

log = {
    "loglevel": os.environ.get("VPN_LOG_LEVEL", "warning"),
}
if os.environ.get("VPN_ACCESS_LOG"):
    log["access"] = os.environ["VPN_ACCESS_LOG"]
if os.environ.get("VPN_ERROR_LOG"):
    log["error"] = os.environ["VPN_ERROR_LOG"]

config = {
    "log": log,
    "dns": {
        "hosts": {},
        "servers": [
            {
                "address": "localhost",
                "domains": direct_domain_rules,
            },
            "1.1.1.1",
            "8.8.8.8",
        ],
        "queryStrategy": "UseIPv4",
    },
    "inbounds": [
        {
            "tag": "tun-in",
            "protocol": "tun",
            "port": 0,
            "settings": {
                "name": tun_iface,
                "mtu": getenv_int("VPN_TUN_MTU", 1500),
            },
            "sniffing": sniffing,
        },
        {
            "tag": "socks-in",
            "protocol": "socks",
            "listen": "127.0.0.1",
            "port": getenv_int("VPN_SOCKS_PORT", 2080),
            "settings": {
                "auth": "noauth",
                "udp": True,
            },
            "sniffing": sniffing,
        },
        {
            "tag": "http-in",
            "protocol": "http",
            "listen": "127.0.0.1",
            "port": getenv_int("VPN_HTTP_PORT", 2081),
            "sniffing": sniffing,
        },
    ],
    "outbounds": [
        {
            "tag": "proxy",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": server_address,
                        "port": server_port,
                        "users": [vless_user],
                    }
                ]
            },
            "streamSettings": stream_settings,
        },
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4",
            },
            "streamSettings": {
                "sockopt": sockopt,
            },
        },
        {
            "tag": "block",
            "protocol": "blackhole",
        },
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "domainMatcher": "mph",
        "rules": [
            {
                "type": "field",
                "domain": direct_domain_rules,
                "outboundTag": "direct",
            },
            {
                "type": "field",
                "ip": github_direct_cidrs,
                "outboundTag": "direct",
            },
            {
                "type": "field",
                "ip": private_cidrs,
                "outboundTag": "direct",
            },
            {
                "type": "field",
                "protocol": ["bittorrent"],
                "outboundTag": "block",
            },
        ],
    },
}

tun_packet_encoding = os.environ.get("VPN_TUN_PACKET_ENCODING", "")
if tun_packet_encoding:
    config["inbounds"][0]["settings"]["packetEncoding"] = tun_packet_encoding

print(json.dumps(config, indent=2, ensure_ascii=False))
PY
