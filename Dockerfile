# Stage 1: Build Unbound from source and collect dependencies
FROM --platform=$BUILDPLATFORM debian:trixie AS build

ARG TARGETARCH
ENV UNBOUND_VER=1.24.1 \
    DEBIAN_FRONTEND=noninteractive

# Install build tools and libraries
RUN apt-get update && apt-get install -y \
  build-essential curl ca-certificates \
  libevent-dev libssl-dev libexpat1-dev \
  autoconf automake libtool pkg-config file \
  libcap2-bin openssl

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

# Set capability to bind to port <1024 as non-root
RUN setcap 'cap_net_bind_service=+ep' /opt/unbound/sbin/unbound

# Copy fallback config
COPY unbound.conf /etc/unbound/unbound.conf
RUN curl -o /etc/unbound/root.hints https://www.internic.net/domain/named.cache


# Generate remote-control certs/keys (needed by your unbound.conf)
RUN /opt/unbound/sbin/unbound-control-setup -d /etc/unbound

# Root key
COPY build-rootkey/root.key /tmp/root.key
RUN mkdir -p /build/staging/var-lib-unbound && \
    cp /tmp/root.key /build/staging/var-lib-unbound/root.key && \
    chown -R 65532:65532 /build/staging/var-lib-unbound/root.key && \
    ln -s /build/staging/var-lib-unbound /var/lib/unbound && \
    /opt/unbound/sbin/unbound-checkconf /etc/unbound/unbound.conf

RUN ls -l ./staging/var-lib-unbound && stat ./staging/var-lib-unbound/root.key && \
    ln -s /build/staging/var-lib-unbound /var/lib/unbound && \
    /opt/unbound/sbin/unbound-checkconf /etc/unbound/unbound.conf

# Collect runtime libs as real files with SONAME filenames
RUN set -eux; \
    mkdir -p /deps_bundle/lib; \
    need_libs() { \
      ldd "$1" | awk '{print $3}' | grep -E '^/'; \
      ldd "$1" | awk '/ld-linux/ {print $1}'; \
    }; \
    for b in /opt/unbound/sbin/unbound /opt/unbound/sbin/unbound-control /opt/unbound/sbin/unbound-anchor; do \
      for lib in $(need_libs "$b"); do \
        base="$(basename "$lib")"; \
        # copy the dereferenced target as a *regular file* named by SONAME
        cp -aL "$lib" "/deps_bundle/lib/$base" || true; \
      done; \
    done; \
    # CA bundle for TLS
    mkdir -p /deps_bundle/certs && cp -a /etc/ssl/certs /deps_bundle/certs/

# Stage 2: Distroless runtime
FROM gcr.io/distroless/base-debian13:nonroot

WORKDIR /

COPY --from=build /opt/unbound /usr/local
COPY --from=build /etc/unbound /etc/unbound
COPY --from=build --chown=65532:65532 /build/staging/var-lib-unbound /var/lib/unbound
COPY --from=build /deps_bundle/lib /usr/lib
COPY --from=build /deps_bundle/certs/certs /etc/ssl/certs
ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib

USER nonroot

EXPOSE 53/udp 53/tcp
EXPOSE 8953/tcp

ENTRYPOINT ["/usr/local/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]