#!/usr/bin/env python3
"""
Network configuration — one place for WiFi credentials.
Stores SSID and password with 0600 permissions.
"""

import json
import os
import stat
from pathlib import Path

NET_CONFIG_FILE = Path.home() / "ap_sti_bridge" / "keys" / "network.json"

_FALLBACK = {"ssid": "", "password": "", "notes": "auto-created; set real values"}


def _ensure_perms(path: Path) -> None:
    try:
        path.chmod(stat.S_IRUSR | stat.S_IWUSR)  # 0600
    except Exception:
        pass


def load_network_config() -> dict:
    """Return {'ssid':..., 'password':...}. Creates a stub file if absent."""
    if NET_CONFIG_FILE.exists():
        try:
            data = json.loads(NET_CONFIG_FILE.read_text())
            _ensure_perms(NET_CONFIG_FILE)
            return {
                "ssid": data.get("ssid", ""),
                "password": data.get("password", ""),
            }
        except Exception:
            pass
    else:
        try:
            NET_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
            NET_CONFIG_FILE.write_text(json.dumps(_FALLBACK, indent=2))
            _ensure_perms(NET_CONFIG_FILE)
        except Exception:
            pass
    return {"ssid": _FALLBACK["ssid"], "password": _FALLBACK["password"]}


def save_network_config(ssid: str, password: str) -> bool:
    """Persist credentials with 0600 permissions."""
    try:
        NET_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        NET_CONFIG_FILE.write_text(json.dumps(
            {"ssid": ssid, "password": password}, indent=2))
        _ensure_perms(NET_CONFIG_FILE)
        return True
    except Exception:
        return False


def is_configured() -> bool:
    cfg = load_network_config()
    return bool(cfg.get("ssid"))


def status() -> dict:
    """Safe for reporting: reports whether creds exist, never the password."""
    cfg = load_network_config()
    return {
        "configured": bool(cfg.get("ssid")),
        "ssid": cfg.get("ssid", ""),
        "has_password": bool(cfg.get("password")),
        "path": str(NET_CONFIG_FILE),
    }


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 3:
        ok = save_network_config(sys.argv[1], sys.argv[2])
        print("saved" if ok else "failed")
    print(json.dumps(status(), indent=2))
