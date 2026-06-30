# Cloak ck-server — the obfuscation relay. Runs on a cheap PUBLIC box (e.g.
# Lightsail/EC2) placed in front of your AWS Client VPN endpoint. It forwards the
# de-obfuscated stream to the endpoint; it needs no access to any VPC.
FROM debian:bookworm-slim
ARG CLOAK_VERSION=v2.12.0
ARG TARGETARCH=amd64
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL "https://github.com/cbeuw/Cloak/releases/download/${CLOAK_VERSION}/ck-server-linux-${TARGETARCH}-${CLOAK_VERSION}" \
      -o /usr/local/bin/ck-server \
 && chmod +x /usr/local/bin/ck-server \
 && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["/usr/local/bin/ck-server", "-c", "/etc/cloak/ckserver.json"]
