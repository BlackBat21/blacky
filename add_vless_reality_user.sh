#!/usr/bin/env bash

# ============================================================================
# add_vless_reality_user.sh
# ----------------------------------------------------------------------------
# Add a new VLESS client (UUID) to an existing Xray REALITY server set up by
# install_vless_reality.sh. The script appends the UUID to the clients array in
# /etc/xray/config.json and optionally appends a ShortID. Finally it reloads
# Xray and prints the import URI/QR parameters for the new user.
# ----------------------------------------------------------------------------
# Usage examples
#   1) Auto-generate UUID:
#        sudo bash add_vless_reality_user.sh
#   2) Provide custom UUID and Short-ID:
#        sudo bash add_vless_reality_user.sh --uuid 1111... --short abcd
#   3) Specify custom config path:
#        sudo bash add_vless_reality_user.sh --config /path/to/config.json
# ============================================================================

set -euo pipefail

CONFIG="/etc/xray/config.json"
UUID=""
SHORT=""

usage() {
    cat <<USAGE
Add an extra VLESS client to Xray REALITY.

sudo $0 [--uuid <uuid>] [--short <hex>] [--config <config.json>]
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uuid)  UUID="$2";   shift 2;;
        --short) SHORT="$2";  shift 2;;
        --config) CONFIG="$2"; shift 2;;
        -h|--help) usage;;
        *) echo "Unknown option: $1"; usage;;
    esac
done

if [[ ! -f "$CONFIG" ]]; then
    echo "Config not found: $CONFIG" >&2; exit 1
fi

# Generate UUID if missing
if [[ -z "$UUID" ]]; then
    if command -v uuidgen &>/dev/null; then
        UUID="$(uuidgen)"
    else
        UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N | sha256sum | cut -c1-32 | sed 's/\(..\)/\1-/g; s/-$//')"
    fi
fi

# Ensure jq is installed
if ! command -v jq &>/dev/null; then
    echo "Installing jq ..."
    if command -v apt &>/dev/null; then
        apt update -y && DEBIAN_FRONTEND=noninteractive apt install -y jq
    elif command -v dnf &>/dev/null; then
        dnf install -y jq
    elif command -v yum &>/dev/null; then
        yum install -y epel-release && yum install -y jq
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm jq
    else
        echo "Please install 'jq' manually." >&2; exit 1
    fi
fi

TMP=$(mktemp)
cp "$CONFIG" "$TMP"

# Add client UUID
jq --arg uuid "$UUID" '(.inbounds[0].settings.clients //= []) | (.inbounds[0].settings.clients |= (if (map(.id) | index($uuid)) then . else . + [{"id":$uuid}] end))' "$TMP" > "$TMP.new"

# Add ShortID if provided
if [[ -n "$SHORT" ]]; then
    jq --arg sid "$SHORT" '(.inbounds[0].streamSettings.realitySettings.shortIds //= []) | (.inbounds[0].streamSettings.realitySettings.shortIds |= (if index($sid) then . else . + [$sid] end))' "$TMP.new" > "$TMP"
    mv "$TMP" "$TMP.new"
fi

mv "$TMP.new" "$CONFIG"
rm "$TMP" || true

# Restart Xray to apply changes
systemctl restart xray

# Compose import URI using stored public key and SNI
PBK="$(cat /etc/xray/public.key 2>/dev/null || echo)"
SNI="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$CONFIG")"
# Fallback: derive from dest if serverNames empty
if [[ -z "$SNI" ]]; then
    SNI="$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "$CONFIG" | cut -d':' -f1)"
fi
SERVER="$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')"

if [[ -n "$PBK" && -n "$SNI" ]]; then
    SID_VAL="${SHORT:-$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG")}"
    URI="vless://${UUID}@${SERVER}:443?type=tcp&encryption=none&security=reality&pbk=${PBK}&sid=${SID_VAL}&sni=${SNI}#${SNI}"

    ################################
    # Show URI before generating QR #
    ################################

    cat <<GENERATE

Generated VLESS+REALITY URI (copy or scan):
$URI
GENERATE

    ############################
    # Generate QR code (PNG)   #
    ############################

    # Ensure qrencode is installed
    if ! command -v qrencode &>/dev/null; then
        echo "Installing qrencode ..."
        if command -v apt &>/dev/null; then
            apt update -y && DEBIAN_FRONTEND=noninteractive apt install -y qrencode
        elif command -v dnf &>/dev/null; then
            dnf install -y qrencode
        elif command -v yum &>/dev/null; then
            yum install -y qrencode
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm qrencode
        else
            echo "Please install 'qrencode' manually to generate QR codes." >&2
        fi
    fi

    if command -v qrencode &>/dev/null; then
        PNG="/etc/xray/vless-${UUID}.png"
        qrencode -o "$PNG" -l H -t png -- "$URI"

        # Show ASCII QR for quick scan
        qrencode -t ANSIUTF8 -- "$URI"

        echo -e "\nQR code saved to: $PNG"
    fi

    # Final summary without duplicate URI/QR path
    cat <<SUMMARY

✔ Additional VLESS + REALITY user added!

Configuration file : $CONFIG
Systemd service    : xray (restarted)
Fake SNI           : $SNI
Connect to host    : $SERVER
Public key         : $PBK (also saved to /etc/xray/public.key)
Short ID           : $SID_VAL
UUID               : $UUID

SUMMARY
fi 