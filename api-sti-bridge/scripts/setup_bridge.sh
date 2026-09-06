#!/bin/bash
# RouterBridge setup for UNO Q
# Exposes the MCU's Bridge TCP server to the network so workers on the AP
# can reach the Arduino RouterBridge daemon.
#
# Usage: sudo ./setup_bridge.sh
#
# The MCU's BridgeTCPServer on port 8080 will be exposed as
# 0.0.0.0:8080 on the Linux host.

set -euo pipefail

BRIDGE_PORT=8080

echo "=== RouterBridge Daemon Setup ==="

# Check if arduino-router is installed
if ! command -v arduino-router &> /dev/null; then
    echo "arduino-router not found. Installing..."
    sudo apt-get update && sudo apt-get install -y arduino-router 2>/dev/null || true
fi

# If arduino-router isn't available, create a manual bridge using socat
if ! command -v arduino-router &> /dev/null; then
    echo "Using socat bridge as fallback..."

    if ! command -v socat &> /dev/null; then
        echo "Installing socat..."
        sudo apt-get update && sudo apt-get install -y socat
    fi

    # Find the MCU TTY device
    MCU_TTY=""
    for dev in /dev/ttyRPMSG* /dev/ttyGS* /dev/ttyACM* /dev/ttyUSB*; do
        if [ -e "$dev" ]; then
            MCU_TTY="$dev"
            break
        fi
    done

    if [ -z "$MCU_TTY" ]; then
        echo "WARNING: Could not find MCU TTY device."
        echo "Expected devices: /dev/ttyRPMSG*, /dev/ttyACM*, /dev/ttyUSB*"
        ls -la /dev/tty* 2>/dev/null | head -20
        exit 1
    fi

    echo "MCU TTY: $MCU_TTY"

    # Kill any existing socat bridge
    pkill -f "socat.*$BRIDGE_PORT" 2>/dev/null || true
    sleep 1

    # Create bridge: TCP 8080 ↔ MCU serial
    echo "Starting bridge: 0.0.0.0:$BRIDGE_PORT ↔ $MCU_TTY"
    sudo socat -d -d \
        TCP-LISTEN:$BRIDGE_PORT,reuseaddr,fork \
        FILE:$MCU_TTY,raw,echo=0,b115200 \
        &

    echo "Bridge PID: $!"
else
    echo "Configuring arduino-router..."
    sudo arduino-router --port $BRIDGE_PORT --daemon
fi

echo ""
echo "=== Bridge Active ==="
echo "  Workers connect to: 192.168.4.1:$BRIDGE_PORT"
