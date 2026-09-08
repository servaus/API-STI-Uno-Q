# AP/STI Bridge — Concurrent WiFi on UNO Q

The Arduino UNO Q has one WiFi radio. This setup makes it do two things at once:

1. **Stay connected to home WiFi** (Station mode) — internet, SSH, remote access
2. **Broadcast its own access point** (AP mode) — worker devices connect here

Both run simultaneously on different channels. SSH stays alive the whole time.

---

## Quick Start (GUI Tool)

The easiest way to set this up is the **web-based GUI**:

1. Open `index.html` in any browser (Chrome, Firefox, Safari, Edge)
2. Enter your WiFi credentials and AP settings
3. Click "Generate Config Files"
4. Download the files or copy them to your UNO Q
5. Follow the deployment instructions at the bottom of the page

The GUI generates all the files you need with your specific settings baked in — no manual editing required.

---

## Manual Setup

## How It Works

The UNO Q's WCN3990 radio supports virtual interfaces. We create `ap0` as a second interface on the same physical radio (`phy0`). The two interfaces run on different channels — the AP doesn't care what channel the home router uses.

```
                          ┌──────────────────────────────────────────────┐
                          │              UNO Q (Linux)                     │
                          │                                                │
    Home WiFi ────────────┤  wlan0 (ch6) ── Internet, SSH, Tailscale       │
    (192.168.0.x)         │                                                │
                          │  ap0 (ch11) ──── AP for workers                │
                          │  192.168.4.1     DHCP: 192.168.4.100-199      │
                          └──────────────────────────────────────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
              Worker #1             Worker #2             Worker #3
              192.168.4.101         192.168.4.102         192.168.4.103
```

---

## What You Need

- Arduino UNO Q running Linux
- `nmcli` (NetworkManager)
- SSH access to the UNO Q
- Home WiFi SSID and password
- A way to copy files to the UNO Q (SCP, USB, etc.)

---

## Step 1: Copy Files

Copy the `scripts/` folder from this project to the UNO Q:

```bash
scp -r scripts/ arduino@uno-q:/home/arduino/ap_sti_bridge/
```

---

## Step 2: Connect to Home WiFi

If the UNO Q isn't already on your WiFi:

```bash
nmcli device wifi list
nmcli device wifi connect YOUR_SSID password YOUR_PASSWORD
```

Verify:

```bash
ping -c 3 8.8.8.8
```

---

## Step 3: Create the AP Profile

This profile defines the AP that `ap0` will broadcast. Run on the UNO Q:

```bash
nmcli connection add \
    type wifi \
    ifname ap0 \
    con-name "AP-bridge-ap0" \
    autoconnect no \
    wifi.mode ap \
    wifi.ssid AP-bridge \
    wifi.band bg \
    wifi.channel 11 \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk YOUR_AP_PASSWORD \
    ipv4.method shared \
    ipv4.addresses 192.168.4.1/24 \
    802-11-wireless.cloned-mac-address stable
```

**Critical settings explained:**

| Setting | Value | Why |
|---------|-------|-----|
| `ifname ap0` | ap0 | Creates a virtual interface, doesn't touch wlan0 |
| `autoconnect no` | no | Prevents NM from stealing wlan0 |
| `wifi.channel 11` | 11 | Different from wlan0's channel — intentional |
| `ipv4.method shared` | shared | Gives workers DHCP addresses |

Save the UUID that `nmcli` outputs — you'll need it in Step 4.

---

## Step 4: Bring Up the AP

The script `ap0-up.sh` creates the virtual interface and activates the AP. **Do NOT use `setup_wifi_ap.sh` or `setup_ap.sh`** — those are for single-AP mode and will tear down your station link.

Edit `scripts/ap0-up.sh` and set these two values:

```bash
# MAC address — use any MAC, but the LAST BYTE must differ from wlan0's MAC
# Find wlan0's MAC with: ip link show wlan0
/sbin/iw phy phy0 interface add ap0 type __ap aa:bb:cc:dd:ee:ff

# NM profile UUID from Step 3
NM_PROFILE="your-uuid-here"
```

Then run:

```bash
sudo bash /home/arduino/ap_sti_bridge/scripts/ap0-up.sh
```

The script:
1. Waits up to 60s for `wlan0` to be connected
2. Deletes any stale `ap0` from a previous run
3. Creates `ap0` with your MAC
4. Activates the NM profile
5. Verifies `ap0` is UP with 192.168.4.1

**Your SSH connection stays alive.** If it drops, something went wrong — see Troubleshooting.

---

## Step 5: Verify

```bash
# Both interfaces up
ip link show wlan0 ap0

# AP is broadcasting
iw dev ap0 info

# Internet still works
ping -c 3 8.8.8.8

# Check the AP IP
ip -4 addr show ap0
```

From a phone or laptop: connect to "AP-bridge" WiFi (password: `YOUR_AP_PASSWORD`), then:

```bash
ping 192.168.4.1
```

If that passes, the bridge is working.

---

## Step 6: Start the Bridge (Optional)

The bridge exposes the MCU's TCP server to the network. Only needed if you're running firmware that uses the Arduino RouterBridge.

```bash
sudo bash /home/arduino/ap_sti_bridge/scripts/setup_bridge.sh
```

---

## Step 7: Boot Persistence

To make the AP come up automatically on boot:

1. Install the `ap0-up.sh` as a service or call it from a systemd unit
2. The NM profile (`autoconnect no`) must stay disabled — it should only start when the script runs

Simple systemd unit (`/etc/systemd/system/ap0-bridge.service`):

```ini
[Unit]
Description=Concurrent AP (ap0) for UNO Q
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /home/arduino/ap_sti_bridge/scripts/ap0-up.sh
ExecStop=/sbin/iw dev ap0 del
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable ap0-bridge.service
```

---

## Troubleshooting

### SSH drops after creating ap0
The NM profile has `interface-name=wlan0` instead of `ap0`. Fix:

```bash
nmcli connection modify "AP-bridge-ap0" connection.interface-name ap0
```

Then reboot or restart networking.

### "ERROR: wlan0 did not associate within 60s"
Home WiFi isn't connected. Fix:

```bash
nmcli device wifi connect YOUR_SSID password YOUR_PASSWORD
```

Then re-run the script.

### ap0 won't create (EBUSY)
Stale interface. Fix:

```bash
sudo /sbin/iw dev ap0 del
sudo bash /home/arduino/ap_sti_bridge/scripts/ap0-up.sh
```

### Duplicate MAC address
The script's MAC matches wlan0's. Change the last byte in the script to something different.

### Workers can't reach the AP
Check the AP is up:

```bash
ip link show ap0
sudo ss -tlnp | grep 8080
```

If the AP is up but workers can't connect, check the NM profile is activated:

```bash
nmcli connection show --active
```

---

## Reference

### Interface Summary

| Interface | Role | Channel | IP | Purpose |
|-----------|------|---------|-----|---------|
| `wlan0` | Station | Follows router | DHCP (192.168.0.x) | Internet + SSH |
| `ap0` | AP | 11 | 192.168.4.1/24 | Workers |

### Script Summary

| File | Use This? | Purpose |
|------|-----------|---------|
| `ap0-up.sh` | **YES** | Creates ap0, activates AP — the concurrent mode script |
| `setup_bridge.sh` | Optional | Exposes MCU TCP to network (only for Arduino RouterBridge) |
| `setup_wifi_ap.sh` | NO | Legacy single-AP mode — kills station link |
| `setup_ap.sh` | NO | Configurable single-AP mode — kills station link |

### Hardware Limits

- **Max 32 clients** on the AP (ath10k firmware limit)
- **Single internal antenna** — time-sliced between channels
- **No USB WiFi dongle** — both vifs are on the internal phy0
- **Client power-save** causes latency spikes to sleeping devices (normal WiFi behavior, not a bug)
