# Xray VLESS + REALITY Installer

> **One-click automated installation of Xray-core VLESS proxy with REALITY protocol for secure, censorship-resistant connections.**

A lightweight, production-ready solution that transforms any Linux VPS into a high-performance VLESS proxy server with REALITY transport - no Docker, no complex configs, just two simple Bash scripts.

## 📦 What's Included

This repository contains two self-contained Bash scripts:

| Script | Purpose |
|--------|---------|
| `install_vless_reality.sh` | One-shot installer that turns a fresh Linux VPS into a secured VLESS+REALITY server running on TCP/443. |
| `add_vless_reality_user.sh` | Append additional client credentials (UUID / ShortID) to the running server without touching existing users. |

Both scripts are designed for **simplicity & minimal surface area** – no Docker, no complex configurations, just clean Bash scripts that get the job done.

---

## ✨ Features

* **REALITY Transport (TLS-less disguise)** – Avoids buying certificates whilst looking like genuine TLS traffic.
* **Runs under `nobody` via systemd** – Hardens the Xray process by dropping privileges.
* **Automatic key-pair & UUID generation** – Sensible defaults, but everything is overridable.
* **Unique identifiers per user** – Each user gets a unique UUID and Short ID to prevent conflicts.
* **Generates shareable URI + QR code** – Ready to import into V2RayN/Clash/etc.
* **Optional nginx website on :80** – Redirects all HTTP traffic to the fake SNI for extra camouflage.
* **Enables TCP BBR congestion control** – Boosts throughput on supported kernels.

---

## 🛠  Prerequisites

* A fresh 64-bit Linux server (Debian/Ubuntu/Rocky/Alma/Arch all tested)
* Root privileges (`sudo` will be invoked by the scripts)
* Port **443** and optionally **80** open in your firewall / cloud panel

_That’s it – the installer will pull `curl`, `unzip`, `qrencode`, `nginx`, etc. as required._

---

## 🚀 Quick Start

### One-Command Installation

```bash
curl -O https://raw.githubusercontent.com/ndatg/xray-vless-reality-installer/main/install_vless_reality.sh
sudo bash install_vless_reality.sh --sni www.cloudflare.com
```

### Alternative: Download Both Scripts

```bash
# Download both scripts
curl -O https://raw.githubusercontent.com/ndatg/xray-vless-reality-installer/main/install_vless_reality.sh
curl -O https://raw.githubusercontent.com/ndatg/xray-vless-reality-installer/main/add_vless_reality_user.sh

# Run installation
sudo bash install_vless_reality.sh --sni www.cloudflare.com
```

Typical successful output ends with something like:

```
Generated VLESS+REALITY URI (copy or scan):
vless://1111...@203.0.113.10:443?type=tcp&encryption=none&security=reality&pbk=...#a1b2c3d4-www.cloudflare.com
✔ Xray-core VLESS + REALITY installation completed!
```

Scan or copy that URI into your client of choice.

---

## 🔧 Script Reference

### `install_vless_reality.sh`

```
sudo bash install_vless_reality.sh --sni <fake-site.com> [options]

Required:
  --sni    <domain>     Domain presented to the outside world (must exist!)

Optional:
  --server <ip/host>    Public address clients should connect to (auto-detected)
  --uuid   <uuid>       Pre-set client UUID (defaults to auto-generated)
  --short  <hex>        ShortID 1-16 hex chars (defaults to auto-generated)
  --fp     <name>       TLS fingerprint shown to clients (default: chrome)
```

Behind the scenes the script will:
1. Detect your package manager and install dependencies.  
2. Enable TCP BBR congestion control (if supported).  
3. Fetch the latest Xray-core binary matching the CPU architecture.  
4. Generate an X25519 key-pair (REALITY requirement).  
5. Write `/etc/xray/config.json` with a single VLESS inbound on 443.  
6. Create and start a `systemd` service `xray.service`.  
7. Optionally configure nginx on port 80 to redirect to the fake SNI.  
8. Print the import URI and render a QR code (PNG + ANSI).

### `add_vless_reality_user.sh`

```bash
sudo bash add_vless_reality_user.sh [--uuid <uuid>] [--short <hex>] [--config <path>]

Required:
  (none - all parameters are optional)

Optional:
  --uuid   <uuid>       Pre-set client UUID (defaults to auto-generated)
  --short  <hex>        ShortID 1-16 hex chars (defaults to auto-generated unique ID)
  --config <path>       Custom config file path (defaults to /etc/xray/config.json)
```

Behind the scenes the script will:
1. Generate a unique UUID if not provided (using `uuidgen` or fallback methods).
2. Generate a unique ShortID if not provided (using `openssl rand -hex 4`).
3. Check for duplicate UUIDs and ShortIDs to prevent conflicts.
4. Add the new client to the existing Xray configuration.
5. Restart the Xray service to apply changes.
6. Generate and display the import URI with QR code for the new user.

---

## 👥 Adding Additional Users

### Automatic Generation (Recommended)

Generate a new UUID and ShortID automatically:

```bash
sudo bash add_vless_reality_user.sh
```

This will:
- Generate a unique UUID automatically
- Generate a unique 8-character hex ShortID (e.g., `a1b2c3d4`)
- Check for conflicts with existing users
- Create the connection URI and QR code

### Manual Values

Provide your own UUID and/or ShortID:

```bash
sudo bash add_vless_reality_user.sh \
  --uuid 22222222-2222-2222-2222-222222222222 \
  --short face
```

**Important**: ShortIDs must be 1-16 hexadecimal characters only (`0-9`, `a-f`).

Valid examples: `face`, `dead`, `beef`, `cafe`, `1234`, `abcd`, `f00d`

### What Happens

The script will:
1. Reuse the stored public key and SNI from the original installation
2. Add the new user without affecting existing users
3. Generate a complete VLESS+REALITY URI with all parameters
4. Create both PNG and ASCII QR codes for easy sharing
5. Restart Xray service to apply the changes

### Example Output

Both installation and user addition scripts provide consistent output:

```
Generated VLESS+REALITY URI (copy or scan):
vless://uuid@server:443?type=tcp&encryption=none&security=reality&pbk=key&sid=shortid&fp=chrome&sni=domain#shortid-domain

[ASCII QR CODE displayed here]

QR code saved to: /etc/xray/vless-uuid.png

✔ [Installation completed! / Additional user added!]

Configuration file : /etc/xray/config.json
Systemd service    : xray (running/restarted)
Fake SNI           : domain
Connect to host    : server
Public key         : key (also saved to /etc/xray/public.key)
Short ID           : shortid
UUID               : uuid

Share the above URI or QR with your client.

Check service status with: systemctl status xray
```

---

## 📑 File & Service Locations

| Path | Purpose |
|------|---------|
| `/usr/local/bin/xray` | Xray-core binary |
| `/etc/xray/config.json` | Main configuration (created by installer) |
| `/etc/xray/public.key` | Saved REALITY public key |
| `/etc/systemd/system/xray.service` | systemd service unit |
| `/etc/xray/vless-<UUID>.png` | Generated QR codes (named by user UUID) |

---

## 🔑 Understanding Short IDs

**Short IDs** are hexadecimal identifiers required by the REALITY protocol for client authentication and traffic routing.

### Key Points:
- **Format**: 1-16 hexadecimal characters (`0-9`, `a-f`)
- **Purpose**: Client identification and connection validation
- **Uniqueness**: Each user should have their own unique Short ID
- **Security**: Acts as an additional authentication layer

### Valid Short ID Examples:
```
face    (4 chars)
dead    (4 chars) 
beef    (4 chars)
cafe    (4 chars)
1234    (4 chars)
abcdef  (6 chars)
a1b2c3d4 (8 chars - default auto-generated length)
```

### Invalid Examples:
```
john-laptop  ❌ (contains non-hex characters)
user123      ❌ (contains 'u', 'r', 's')
mobile       ❌ (contains 'm', 'i', 'l')
```

### Usage Tips:
- Connection names combine Short ID and SNI domain for better identification
- Choose memorable hex combinations like `face`, `dead`, `beef` for easy recognition
- Auto-generated Short IDs are 8 characters long for good uniqueness
- Connection will display as "shortid-domain" (e.g., "face-www.cloudflare.com", "a1b2c3d4-www.google.com") in your client

---

## 🔄 Updating Xray-core

Simply re-run the installer – it will download the latest release and perform an in-place upgrade while preserving your config.

---

## ❌ Uninstalling

```bash
sudo systemctl disable --now xray
sudo rm -rf /usr/local/bin/xray /etc/xray /etc/systemd/system/xray.service
sudo systemctl daemon-reload
```

If you enabled nginx solely for camouflage and no longer need it:

```bash
sudo systemctl disable --now nginx
```

---

## 🛡 Disclaimer

These scripts are provided "as is" without warranty. Use them responsibly and respect the laws of your jurisdiction.

