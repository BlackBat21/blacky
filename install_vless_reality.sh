#!/usr/bin/env bash

# ==============================================================================
# Xray-Core VLESS + REALITY Automated Installer
# ------------------------------------------------------------------------------
# This script installs a secure, obfuscated VLESS VPN server using Xray-core’s
# REALITY transport. It mirrors the UX of the other installers in this repo.
#
#   Required parameters:
#     --sni     <domain>          The fake site domain (e.g. www.cloudflare.com)
#
#   Optional parameters:
#     --uuid    <uuid>            Client UUID (defaults to uuidgen)
#     --short   <hex>            Short ID (1-16 hex, defaults random)
#     --fp      <fingerprint>     Client fingerprint (default chrome) – URI only
#
# Example:
#   sudo bash install_vless_reality.sh \
#       --sni www.cloudflare.com \
#       --uuid 11111111-1111-1111-1111-111111111111 \
#       --short abcd
# ------------------------------------------------------------------------------
# Features:
#   • Listens on TCP/443 using REALITY (no public certificate needed)
#   • Randomised private/public key pair (X25519)
#   • Generates shareable VLESS+REALITY URI and QR code
#   • Minimal systemd service under user nobody
#   • Optional Nginx site on port 80 for camouflage
# ==============================================================================

set -euo pipefail

##############################
# 1. Parse user parameters   #
##############################

SNI=""
SERVER=""
UUID=""
SHORT_ID=""
FINGERPRINT="chrome"

usage() {
    echo -e "\nUsage: sudo $0 --sni <fake-site.com> [--server <real-server-domain-or-ip>] [--uuid <uuid>] [--short <hex>] [--fp <fingerprint>]\n" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sni)
            SNI="$2"; shift 2;;
        --server)
            SERVER="$2"; shift 2;;
        --uuid)
            UUID="$2"; shift 2;;
        --short)
            SHORT_ID="$2"; shift 2;;
        --fp)
            FINGERPRINT="$2"; shift 2;;
        -h|--help)
            usage;;
        *)
            echo "Unknown option: $1" >&2; usage;;
    esac
done

if [[ -z "$SNI" ]]; then
    usage
fi

# Determine SERVER if not provided (use public IPv4)
if [[ -z "$SERVER" ]]; then
    SERVER="$(curl -s https://api.ipify.org || true)"
    if [[ -z "$SERVER" ]]; then
        echo "Unable to auto-detect public IP. Please pass --server <ip/domain>." >&2
        exit 1
    fi
fi

# Generate UUID if missing
if [[ -z "$UUID" ]]; then
    if command -v uuidgen &>/dev/null; then
        UUID="$(uuidgen)"
    else
        UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | sha256sum | cut -c1-32 | sed 's/\(..\)/\1-/g; s/-$//')"
    fi
fi

# Generate Short ID (1-16 hex chars) if missing
if [[ -z "$SHORT_ID" ]]; then
    SHORT_ID="$(openssl rand -hex 4 2>/dev/null || echo abcd)"
fi

##############################
# 2. Install dependencies    #
##############################

install_deps() {
    if command -v apt &>/dev/null; then
        apt update -y
        DEBIAN_FRONTEND=noninteractive apt install -y curl unzip tar uuid-runtime nginx qrencode
    elif command -v dnf &>/dev/null; then
        dnf install -y curl unzip tar nginx qrencode
    elif command -v yum &>/dev/null; then
        yum install -y curl unzip tar nginx qrencode
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm curl unzip tar nginx qrencode
    else
        echo "Unsupported package manager. Install curl and unzip manually." >&2
        exit 1
    fi
}

# Enable TCP BBR if not already active
enable_bbr() {
    if sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q '^bbr$'; then
        echo "✓ BBR congestion control already enabled."
    else
        echo -e "\n>>> Enabling TCP BBR congestion control..."
        # Apply settings only if they are not yet present
        grep -qF 'net.core.default_qdisc=fq' /etc/sysctl.conf || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
        grep -qF 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
        sysctl -p
    fi
}

install_deps
enable_bbr

############################################
# 3. Download & install latest Xray-core   #
############################################

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)   ARCH_PKG="xray-linux-64"   ;;
    aarch64|arm64)  ARCH_PKG="xray-linux-arm64-v8a" ;;
    armv7l|armv6l)  ARCH_PKG="xray-linux-arm32-v7a" ;;
    *) echo "Unsupported CPU architecture: $ARCH" >&2; exit 1;;
esac

TMP_DIR=$(mktemp -d)
LATEST_TAG=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep -Po '"tag_name":\s*"\K[^"]+')
TAR_NAME="${ARCH_PKG}.zip"
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_TAG}/${TAR_NAME}"

echo -e "\n>>> Downloading Xray-core ${LATEST_TAG} (${ARCH_PKG})..."
curl -L "$DOWNLOAD_URL" -o "$TMP_DIR/${TAR_NAME}"

install -d /usr/local/bin /etc/xray
unzip -qo "$TMP_DIR/${TAR_NAME}" -d "$TMP_DIR"
install -m 755 "$TMP_DIR/xray" /usr/local/bin/xray
install -m 755 "$TMP_DIR/xray" /usr/local/bin/v2ray  # compatibility symlink name

##############################
# 4. Generate REALITY keys   #
##############################

KEY_OUTPUT=$(xray x25519)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk '/Private/{print $3}')
PUBLIC_KEY=$(echo  "$KEY_OUTPUT" | awk '/Public/{print $3}')

# Persist public key for future user additions
echo "$PUBLIC_KEY" > /etc/xray/public.key

##############################
# 5. Create config.json      #
##############################

CONFIG_PATH="/etc/xray/config.json"
cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 2025,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF

chmod 640 "$CONFIG_PATH"

##############################
# 6. systemd service         #
##############################

SERVICE_FILE="/etc/systemd/system/xray.service"
cat > "$SERVICE_FILE" <<'SERVICE'
[Unit]
Description=Xray Service (VLESS + REALITY)
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

################################
# 7. Optional Nginx on port 80 #
################################

WEBROOT="/var/www/html"
mkdir -p "$WEBROOT"

# Replace the default Nginx site with a redirect to the fake SNI
DEFAULT_SITE="/etc/nginx/sites-available/default"

# Backup original default if not already backed up
if [[ -f "$DEFAULT_SITE" && ! -f "${DEFAULT_SITE}.orig" ]]; then
    cp "$DEFAULT_SITE" "${DEFAULT_SITE}.orig"
fi

cat > "$DEFAULT_SITE" <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    return 301 https://${SNI}\$request_uri;
}
NGINX

# Ensure the symlink exists
if [[ -d /etc/nginx/sites-enabled ]]; then
    ln -sf "$DEFAULT_SITE" /etc/nginx/sites-enabled/default
fi

systemctl enable --now nginx
systemctl reload nginx

################################
# 8. Generate URI + QR code   #
################################

URI="vless://${UUID}@${SERVER}:443?type=tcp&encryption=none&security=reality&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&fp=${FINGERPRINT}&sni=${SNI}#${SHORT_ID}-${SNI}"

cat <<GENERATE

Generated VLESS+REALITY URI (copy or scan):
$URI
GENERATE

# Ensure qrencode is installed (should be from dependencies, but double-check)
if command -v qrencode &>/dev/null; then
    QR_OUTPUT="/etc/xray/vless-${UUID}.png"
    qrencode -o "$QR_OUTPUT" -l H -t png -- "$URI"

    # Show ASCII QR for quick scan
    qrencode -t ANSIUTF8 -- "$URI"

    echo -e "\nQR code saved to: $QR_OUTPUT"
else
    echo -e "\nqrencode not available - QR code generation skipped"
fi

################################
# 9. Completion message        #
################################

cat <<EOF

✔ Xray-core VLESS + REALITY installation completed!

Configuration file : $CONFIG_PATH
Systemd service    : xray (running)
Fake SNI           : $SNI
Connect to host    : $SERVER
Public key         : $PUBLIC_KEY (also saved to /etc/xray/public.key)
Short ID           : $SHORT_ID
UUID               : $UUID

To add more users later run:  sudo bash add_vless_reality_user.sh

Share the above URI or QR with your client.

Check service status with: systemctl status xray
EOF
