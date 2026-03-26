#!/usr/bin/env bash

SSID=${1:-$(nmcli -t -f SSID device wifi list | grep -E 'ITMO' | head -1)}
