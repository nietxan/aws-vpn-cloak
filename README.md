# aws-vpn-cloak

Connect to **AWS Client VPN** (with SAML/federated auth) over a **Cloak**
([cbeuw/Cloak](https://github.com/cbeuw/Cloak)) relay, so the VPN traffic looks
like ordinary HTTPS and survives DPI / censored networks. Everything runs in one
container; you reach the VPC from your host through a SOCKS5 proxy.

```
 host browser ──Okta/SAML──┐
 host apps ─SOCKS :1080─┐   │
                        ▼   ▼
  ┌───────────────────────────────────────────────────────────────┐
  │ container: ck-client ──(looks like HTTPS:443)──▶ Cloak relay   │
  │              │                                        │        │
  │         openvpn-aws ◀── 127.0.0.1:1194 ───────────────┘        │
  │              ▼                                                 │
  │            tun0 ──▶ AWS Client VPN endpoint ──▶ VPC            │
  └───────────────────────────────────────────────────────────────┘
```

**Why a patched openvpn?** AWS's SAML assertion (~10 KB) exceeds stock openvpn's
`USER_PASS_LEN` and uses a proprietary u32 length wire format. The
[aws-vpn-client](https://github.com/aws-vpn-client/aws-vpn-client) patch fixes
both. It builds and handshakes cleanly on Linux, which is
why this ships as a container.

**Why not the AWS VPN Client app?** It attests the server IP from the SAML
metadata and aborts behind any relay. Community openvpn has no such check.

---

## Prerequisites

1. **Docker** with `/dev/net/tun` (Docker Desktop or Linux).
2. A **Cloak relay** in front of your AWS Client VPN endpoint — a cheap public
   box running `ck-server` that forwards the de-obfuscated stream to the
   endpoint. See [relay/](relay/).
3. Your **AWS Client VPN profile** (`.ovpn`) from the self-service portal.
4. Your Cloak client credentials (PublicKey + UID) from the relay.

## Quick start

```bash
# 1. config
cp config/ckclient.json.example config/ckclient.json   # fill PublicKey, UID, RemoteHost
./scripts/make-vpn-conf.sh ~/Downloads/your-client-config.ovpn config/vpn.conf

# 2. point compose at the published image (or build locally)
export IMAGE=ghcr.io/nietxan/aws-vpn-cloak:latest

# 3. up
docker compose up
```

The logs print an **Okta URL** — open it, log in. The assertion is POSTed back to
`127.0.0.1:35001`, the tunnel comes up (`Initialization Sequence Completed`), and
SOCKS5 is live on `127.0.0.1:1080`.

## Using the tunnel

Only the VPC CIDRs route through `tun0` (split tunnel). Send host traffic through
the SOCKS5 proxy:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://<internal-host>/
export ALL_PROXY=socks5h://127.0.0.1:1080        # many CLIs honor this
psql "host=<rds-endpoint> ..."                   # via a SOCKS wrapper, e.g. `tsocks`, `proxychains4`
```

Reachable resources = whatever your IdP group's AWS authorization rules allow.

## Configuration

| File | What |
|------|------|
| `config/vpn.conf` | AWS profile minus `remote`/`auth-federate`/… (use the script) |
| `config/ckclient.json` | Cloak client config: `PublicKey`, `UID`, `RemoteHost` (relay), `ServerName` (decoy) |

Env overrides (compose): `IMAGE`, `SOCKS_PORT` (1080), `CALLBACK_PORT` (35001).

## Build / publish (multi-arch)

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/nietxan/aws-vpn-cloak:latest --push .
```

CI does this on push to `main` and on `v*` tags — see
[.github/workflows/docker-publish.yml](.github/workflows/docker-publish.yml).
Replace `nietxan` with your own GitHub org/user if you fork this.

## How it works

1. `ck-client` opens a TLS-looking carrier to the relay; openvpn dials
   `127.0.0.1:1194` (the local ck-client listener).
2. openvpn run #1: user `N/A` / pass `ACS::35001` → endpoint replies
   `AUTH_FAILED,CRV1:R:<SID>:<text>:<okta-url>`.
3. Browser logs in; IdP POSTs `SAMLResponse` to the callback server.
4. openvpn run #2: pass `CRV1::<SID>::<urlencoded-assertion>` → tunnel up.

All of it rides the Cloak carrier, so a network observer only sees HTTPS.

## Credits & license

- Patched openvpn + SAML flow: [aws-vpn-client/aws-vpn-client](https://github.com/aws-vpn-client/aws-vpn-client)
- Obfuscation: [cbeuw/Cloak](https://github.com/cbeuw/Cloak)
- SOCKS5: [rofl0r/microsocks](https://github.com/rofl0r/microsocks)

This repo's glue is MIT ([LICENSE](LICENSE)). The image bundles **OpenVPN
(GPL-2.0)** and the above projects under their own licenses; distributing the
image carries those obligations.
