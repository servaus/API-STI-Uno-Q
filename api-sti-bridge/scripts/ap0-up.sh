#!/bin/bash
# Concurrent AP + Station setup for UNO Q
# Creates ap0 vif, waits for wlan0 to associate, then activates AP.
#
# Usage: sudo ./ap0-up.sh
#
# Prerequisites:
#   - NetworkManager running
#   - NM profile "AP-bridge-ap0" exists (interface-name=ap0, autoconnect=no)
#   - wlan0 connected to home WiFi
#
# This script:
#   1. Waits for wlan0 to associate (up to 60s)
#   2. Deletes stale ap0 vif if present
#   3. Creates ap0 vif with unique MAC (last byte differs from wlan0)
#   4. Activates NM profile on ap0
#   5. Verifies ap0 is UP with 192.168.4.1/24

set -euo pipefail

LOG="/home/arduino/ap_sti_bridge/logs/ap0-up.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== ap0 bring-up ==="

# 1. Wait for wlan0 to associate (up to 60s)
log "Waiting for wlan0 association..."
for i in $(seq 1 60); do
    if nmcli device show wlan0 2>/dev/null | grep -q "GENERAL.STATE.*100 (connected)"; then
        log "wlan0 associated"
        break
    fi
    if [ "$i" -eq 60 ]; then
        log "ERROR: wlan0 did not associate within 60s"
        exit 1
    fi
    sleep 1
done

# 2. Delete existing ap0 (if stale from previous run)
if /sbin/iw dev 2>/dev/null | grep -q "Interface ap0"; then
    log "Deleting stale ap0 vif..."
    /sbin/iw dev ap0 del 2>/dev/null || true
    sleep 1
fi

# 3. Create ap0 vif with a unique MAC
#    Change the MAC below — last byte must differ from wlan0's MAC
#    Find wlan0's MAC with: ip link show wlan0
log "Creating ap0 vif on phy0..."
/sbin/iw phy phy0 interface add ap0 type __ap addr 14:b5:cd:ea:e6:90
sleep 1
log "ap0 created"

# 4. Bring up ap0 via NM profile (applies IP, SSID, etc.)
#    Replace with the UUID from Step 3 of AP_STI_BRIDGE.md
NM_PROFILE="YOUR-NM-PROFILE-UUID"
if nmcli connection show "$NM_PROFILE" &>/dev/null; then
    log "Activating NM profile $NM_PROFILE on ap0..."
    nmcli connection up "$NM_PROFILE" ifname ap0
    log "AP activated"
else
    log "ERROR: NM profile $NM_PROFILE not found"
    exit 1
fi

# 5. Verify
sleep 2
if ip link show ap0 2>/dev/null | grep -q "UP"; then
    log "ap0 is UP"
    IP=$(ip -4 addr show ap0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "unknown")
    log "ap0 IP: $IP"
else
    log "WARNING: ap0 may not be fully up yet"
fi

log "=== ap0 bring-up complete ==="
