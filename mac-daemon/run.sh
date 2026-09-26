#!/usr/bin/env bash
# Creates the venv on first run, then starts the daemon. Args pass through,
# e.g. ./run.sh --display 1
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
    echo "Setting up .venv (first run)..."
    python3 -m venv .venv
    .venv/bin/pip install -q -r requirements.txt
fi

exec .venv/bin/python3 tablet_server.py "$@"
