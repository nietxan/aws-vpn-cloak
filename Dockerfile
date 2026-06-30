# aws-vpn-cloak — AWS Client VPN (SAML) client, obfuscated through a Cloak relay.
# Generic image: NO site config baked in. Mount vpn.conf + ckclient.json at /config.
# Multi-arch: build with `docker buildx build --platform linux/amd64,linux/arm64`.

# ---- stage 1: AWS-patched openvpn --------------------------------------------
# Stock openvpn can't carry AWS's ~10KB SAML password (USER_PASS_LEN=128, u16
# length field). The aws-vpn-client patch bumps the buffers and switches to the
# u32 wire format AWS expects. Builds/handshakes reliably on Linux.
FROM debian:bookworm-slim AS ovpn-build
ARG OVPN_VER=2.6.12
ARG PATCH_URL=https://raw.githubusercontent.com/aws-vpn-client/aws-vpn-client/master/openvpn-v2.6.12-aws.patch
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential curl ca-certificates pkg-config \
      libssl-dev liblzo2-dev liblz4-dev libcap-ng-dev patch \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSL "https://swupdate.openvpn.org/community/releases/openvpn-${OVPN_VER}.tar.gz" -o o.tgz \
 && tar xf o.tgz && curl -fsSL "${PATCH_URL}" -o aws.patch
WORKDIR /src/openvpn-${OVPN_VER}
RUN patch -p1 < ../aws.patch \
 && ./configure --disable-pkcs11 --disable-plugin-auth-pam --disable-debug \
      --disable-dependency-tracking --disable-dco --with-crypto-library=openssl \
 && make -j"$(nproc)" && cp src/openvpn/openvpn /openvpn-aws

# ---- stage 2: SAML callback server -------------------------------------------
FROM golang:1.22-bookworm AS go-build
WORKDIR /s
COPY server.go .
RUN go mod init samlsrv >/dev/null 2>&1 || true; CGO_ENABLED=0 go build -o /saml-server server.go

# ---- stage 3: microsocks (SOCKS5 so the host reaches the VPC) -----------------
FROM debian:bookworm-slim AS socks-build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && git clone --depth 1 https://github.com/rofl0r/microsocks /m && make -C /m && cp /m/microsocks /microsocks

# ---- final --------------------------------------------------------------------
FROM debian:bookworm-slim
ARG CLOAK_VERSION=v2.12.0
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libssl3 liblzo2-2 liblz4-1 libcap-ng0 iproute2 dnsutils \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://github.com/cbeuw/Cloak/releases/download/${CLOAK_VERSION}/ck-client-linux-${TARGETARCH}-${CLOAK_VERSION}" \
      -o /usr/local/bin/ck-client && chmod +x /usr/local/bin/ck-client
COPY --from=ovpn-build  /openvpn-aws  /usr/local/sbin/openvpn-aws
COPY --from=go-build    /saml-server  /usr/local/bin/saml-server
COPY --from=socks-build /microsocks   /usr/local/bin/microsocks
COPY entrypoint.sh                     /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /run/aws-vpn
WORKDIR /run/aws-vpn
ENTRYPOINT ["/entrypoint.sh"]
