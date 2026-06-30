#!/usr/bin/env bash
# Turn an AWS Client VPN profile (.ovpn from the self-service portal) into the
# vpn.conf this tool needs: strip the AWS-VPN-Client-only directives and the
# remote (the container dials the local Cloak listener instead).
#
#   ./scripts/make-vpn-conf.sh ~/Downloads/downloaded-client-config.ovpn config/vpn.conf
set -euo pipefail
SRC="${1:?usage: make-vpn-conf.sh <input.ovpn> [output vpn.conf]}"
OUT="${2:-config/vpn.conf}"

grep -vE '^(remote |remote-random-hostname|auth-federate|auth-user-pass|auth-retry|inactive)' "$SRC" > "$OUT"
echo "Wrote $OUT"
echo "Kept the CA + 'verify-x509-name'. The container supplies remote/auth at runtime."
