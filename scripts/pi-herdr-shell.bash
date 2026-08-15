#!/usr/bin/env bash

set -euo pipefail
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

exec pi --session-id desktop-ai --name "Desktop AI"
