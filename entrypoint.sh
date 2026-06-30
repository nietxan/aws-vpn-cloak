#!/usr/bin/env bash
# Orchestrates the obfuscated AWS Client VPN (SAML) connection inside the container:
#   ck-client (UDP 127.0.0.1:1194 -> Cloak relay:443) + saml-server(:35001) + openvpn-aws
# Config is mounted read-only at /config: vpn.conf, ckclient.json.
set -uo pipefail

VPN_CONF="${VPN_CONF:-/config/vpn.conf}"
CKCFG="${CKCFG:-/config/ckclient.json}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
CALLBACK_PORT="${CALLBACK_PORT:-35001}"
LOCAL_OVPN_PORT="${LOCAL_OVPN_PORT:-1194}"
WORK=/run/aws-vpn
cd "$WORK"
export SAML_FILE="$WORK/saml-response.txt"

[ -f "$VPN_CONF" ] || { echo "!! missing $VPN_CONF — mount your AWS profile (see README)"; exit 1; }
[ -f "$CKCFG" ]   || { echo "!! missing $CKCFG — mount your Cloak ckclient.json"; exit 1; }

echo "[*] ck-client: UDP 127.0.0.1:${LOCAL_OVPN_PORT} -> Cloak relay"
ck-client -u -c "$CKCFG" -i 127.0.0.1 -l "$LOCAL_OVPN_PORT" &

echo "[*] SAML callback server on 0.0.0.0:${CALLBACK_PORT}"
ADDR="0.0.0.0:${CALLBACK_PORT}" saml-server &

echo "[*] SOCKS5 on 0.0.0.0:${SOCKS_PORT} (reach the VPC from the host through this)"
microsocks -i 0.0.0.0 -p "$SOCKS_PORT" &

sleep 2
rm -f "$SAML_FILE"

echo "[1/3] requesting SAML challenge via Cloak..."
OUT=$(openvpn-aws --config "$VPN_CONF" --verb 3 --proto udp --remote 127.0.0.1 "$LOCAL_OVPN_PORT" \
        --auth-user-pass <(printf "%s\n%s\n" "N/A" "ACS::${CALLBACK_PORT}") 2>&1)
CHAL=$(echo "$OUT" | grep 'AUTH_FAILED,CRV1' || true)
if [ -z "$CHAL" ]; then
  echo "!! no AUTH_FAILED,CRV1 challenge. Last openvpn lines:"; echo "$OUT" | tail -15; exit 1
fi
URL=$(echo "$CHAL" | grep -Eo 'https://.+')
SID=$(echo "$CHAL" | sed -E "s/.*CRV1:R:([^:]+):.*/\1/")

echo "============================================================"
echo "  OPEN THIS URL IN YOUR BROWSER, then log in:"
echo
echo "  $URL"
echo
echo "============================================================"

echo "[2/3] waiting for SAML assertion (POST to host 127.0.0.1:${CALLBACK_PORT})..."
for _ in $(seq 120); do [ -f "$SAML_FILE" ] && break; sleep 1; done
[ -f "$SAML_FILE" ] || { echo "!! SAML timed out"; exit 1; }

echo "[3/3] connecting tunnel..."
exec openvpn-aws --config "$VPN_CONF" --verb 3 --auth-nocache --inactive 3600 \
    --proto udp --remote 127.0.0.1 "$LOCAL_OVPN_PORT" \
    --script-security 2 --route-up "/usr/bin/env rm -f $SAML_FILE" \
    --auth-user-pass <(printf "%s\n%s\n" "N/A" "CRV1::${SID}::$(cat "$SAML_FILE")")
