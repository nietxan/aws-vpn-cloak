# Cloak relay (ck-server)

The public-facing obfuscation relay. Put it on a cheap box (Lightsail/EC2) with a
stable public IP; it only needs inbound `443/tcp` and outbound to your AWS Client
VPN endpoint. **It needs no VPC access.**

## Generate credentials

```bash
docker build -t cloak-relay .
docker run --rm --entrypoint /usr/local/bin/ck-server cloak-relay -k     # -> <public>,<private>
docker run --rm --entrypoint /usr/local/bin/ck-server cloak-relay -uid   # admin UID
docker run --rm --entrypoint /usr/local/bin/ck-server cloak-relay -uid   # user (bypass) UID
```

> `ck-server -k` prints `public,private` (deterministic). Avoid `-key` — its
> human-readable output uses ALL-CAPS labels that trip naive parsers.

## Configure

```bash
cp ckserver.json.example ckserver.json
```
Fill in:
- `ProxyBook.openvpn[1]` — your endpoint host:port. For a UDP endpoint use the
  endpoint hostname (a fixed-prefix variant, since AWS publishes `*.cvpn-...`),
  e.g. `relay.cvpn-endpoint-xxxx.prod.clientvpn.<region>.amazonaws.com:443`.
- `PrivateKey` — the private half from `-k`.
- `AdminUID` / `BypassUID` — the UIDs from `-uid`.
- `RedirAddr` — a real HTTPS site; active probes to `:443` see that, not an open proxy.

Give the **public key** and the **bypass UID** to clients (their `ckclient.json`).

## Run

```bash
docker compose up -d
docker compose logs -f      # healthy = "Listening on :443"; warnings about
                            # malformed probes are just internet scanners
```

> Your AWS Client VPN endpoint must use **UDP/443** to match `ProxyBook` here
> (the default when `transportProtocol` is unset).
