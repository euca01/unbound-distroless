# Stage 1: Build Unbound from source and collect dependencies
FROM --platform=$BUILDPLATFORM debian:bookworm AS build

ARG TARGETARCH
ENV UNBOUND_VER=1.23.0 \
    DEBIAN_FRONTEND=noninteractive

# Install build tools and libraries
RUN apt-get update && apt-get install -y \
  build-essential curl ca-certificates \
  libevent-dev libssl-dev libexpat1-dev \
  autoconf automake libtool pkg-config file

# Download and build Unbound
WORKDIR /build

RUN curl -LO https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VER}.tar.gz && \
    tar xzf unbound-${UNBOUND_VER}.tar.gz && \
    cd unbound-${UNBOUND_VER} && \
    ./configure \
      --prefix=/opt/unbound \
      --with-libevent=/usr \
      --with-ssl=/usr \
      --sysconfdir=/etc/unbound \
      --disable-chroot && \
    make -j"$(nproc)" && make install

# Copy fallback config
COPY unbound.conf /etc/unbound/unbound.conf
RUN curl -o /etc/unbound/root.hints https://www.internic.net/domain/named.cache

# Root key
COPY build-rootkey/root.key /tmp/root.key
RUN mkdir -p /build/staging/var-lib-unbound && \
    mv /tmp/root.key /build/staging/var-lib-unbound/root.key && \
    chown -R 65532:65532 /build/staging/var-lib-unbound && \
    ln -s /build/staging/var-lib-unbound /var/lib/unbound && \
    /opt/unbound/sbin/unbound-checkconf /etc/unbound/unbound.conf

# Collect dynamic libs using ldd
RUN mkdir -p /deps && \
    ldd /opt/unbound/sbin/unbound | awk '{print $3}' | grep -E '^/' | xargs -r -I{} cp --parents {} /deps && \
    ldd /opt/unbound/sbin/unbound | awk '/ld-linux/ {print $1}' | xargs -r -I{} cp --parents {} /deps && \
    cp --parents -r /etc/ssl/certs /deps

# Stage 2: Distroless runtime
FROM gcr.io/distroless/base-debian12:nonroot

WORKDIR /

COPY --from=build /opt/unbound /usr/local
COPY --from=build /etc/unbound /etc/unbound
COPY --from=build --chown=65532:65532 /build/staging/var-lib-unbound /var/lib/unbound
COPY --from=build /deps /

USER nonroot

EXPOSE 53/udp 53/tcp

ENTRYPOINT ["/usr/local/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]