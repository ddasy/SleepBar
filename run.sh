#!/bin/bash
# Dev helper: compile and (re)launch SleepBar. For local development; does not install.
set -e
cd "$(dirname "$0")"

# Kill any previous instance (match by exact process name)
pkill -x SleepBar 2>/dev/null || true
sleep 0.3

echo "Compiling..."
swiftc -O main.swift -o SleepBar -framework AppKit

echo "Launching... (icon appears in the top-right menu bar)"
nohup ./SleepBar >/dev/null 2>&1 &
echo "Started, PID=$!"
