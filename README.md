# VLESS + REALITY Automated Installer

> Automated provisioning of an **Xray-core** VLESS VPN server with REALITY transport – plus a helper script to add extra users.

This repository contains two self-contained Bash scripts:

| Script | Purpose |
|--------|---------|
| `install_vless_reality.sh` | One-shot installer that turns a fresh Linux VPS into a secured VLESS+REALITY server running on TCP/443. |
| `add_vless_reality_user.sh` | Append additional client credentials (UUID / ShortID) to the running server without touching existing users. |

Both scripts borrow the UX of the other installers in this repo and aim for **simplicity & minimal surface area** – no Docker, no 1 000-line configs.

---

## ✨ Features

* **REALITY Transport (TLS-less disguise)** – Avoids buying certificates whilst looking like genuine TLS traffic.
* **Runs under `nobody` via systemd** – Hardens the Xray process by dropping privileges.
* **Automatic key-pair & UUID generation** – Sensible defaults, but everything is overridable.
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

Run the installer (replace the fake SNI with any real, high-reputation domain):

```bash
curl -O https://raw.githubusercontent.com/ndatg/vless-and-reality-quick-install/refs/heads/main/install_vless_reality.sh
sudo bash install_vless_reality.sh --sni www.cloudflare.com
```

Typical successful output ends with something like:

```
Generated VLESS+REALITY URI (copy or scan):
vless://1111...@203.0.113.10:443?type=tcp&encryption=none&security=reality&pbk=...#www.cloudflare.com
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
  --uuid   <uuid>       Pre-set client UUID (defaults to `uuidgen`)
  --short  <hex>        ShortID 1-16 hex chars (default: random)
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
```

* Modifies the `clients` array in the existing Xray config.
* Optionally appends a ShortID to the shared list.
* Reloads the service via `systemctl restart xray`.
* Outputs the ready-to-share URI + QR code for the new user.

---

## 👥 Adding Additional Users

Generate a new UUID and ShortID automatically:

```bash
sudo bash add_vless_reality_user.sh
```

Provide your own values:

```bash
sudo bash add_vless_reality_user.sh \
  --uuid 22222222-2222-2222-2222-222222222222 \
  --short face
```

The script reuses the stored public key and SNI to create a fully-formed URI.

---

## 📑 File & Service Locations

| Path | Purpose |
|------|---------|
| `/usr/local/bin/xray` | Xray-core binary |
| `/etc/xray/config.json` | Main configuration (created by installer) |
| `/etc/xray/public.key` | Saved REALITY public key |
| `/etc/systemd/system/xray.service` | systemd service unit |
| `/etc/xray/vless-*.png` | Generated QR codes |

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
