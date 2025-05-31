# Stage 1: Build Unbound and prepare runtime files
FROM debian:bookworm AS build

ENV UNBOUND_VER=1.23.0 \
    DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
  build-essential curl ca-certificates \
  libevent-dev libssl-dev libexpat1-dev \
  bind9-dnsutils iputils-ping strace lsof less \
  autoconf automake libtool pkg-config

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

# Copy Unbound config
COPY unbound.conf /etc/unbound/unbound.conf

RUN curl -o /etc/unbound/root.hints https://www.internic.net/domain/named.cache

# Copy DNSSEC root key and prepare correct permissions
COPY build-rootkey/root.key /tmp/root.key

# ✅ Staging area inside WORKDIR (to preserve ownership)
RUN mkdir -p ./staging/var-lib-unbound && \
    mv /tmp/root.key ./staging/var-lib-unbound/root.key && \
    chown -R 65532:65532 ./staging/var-lib-unbound

# ✅ Debugging (optional, can be removed in final builds)
RUN ls -l ./staging/var-lib-unbound && stat ./staging/var-lib-unbound/root.key && \
    ln -s /build/staging/var-lib-unbound /var/lib/unbound && \
    /opt/unbound/sbin/unbound-checkconf /etc/unbound/unbound.conf

# Stage 2: Distroless minimal runtime
FROM gcr.io/distroless/base-debian12:nonroot

# Copy Unbound binaries
COPY --from=build /opt/unbound /usr/local

# Copy config and runtime dirs
COPY --from=build /etc/unbound /etc/unbound
COPY --from=build --chown=65532:65532 /build/staging/var-lib-unbound /var/lib/unbound
COPY --from=build /etc/unbound/root.hints /etc/unbound/root.hints

# Copy required shared libraries
COPY --from=build /lib/x86_64-linux-gnu/libdl.so.2 /lib/x86_64-linux-gnu/
COPY --from=build /lib/x86_64-linux-gnu/libpthread.so.0 /lib/x86_64-linux-gnu/
COPY --from=build /lib/x86_64-linux-gnu/libm.so.6 /lib/x86_64-linux-gnu/
COPY --from=build /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/
COPY --from=build /lib64/ld-linux-x86-64.so.2 /lib64/
COPY --from=build /usr/lib/x86_64-linux-gnu/libevent*.so* /usr/lib/
COPY --from=build /usr/lib/x86_64-linux-gnu/libssl.so.* /usr/lib/
COPY --from=build /usr/lib/x86_64-linux-gnu/libcrypto.so.* /usr/lib/
COPY --from=build /etc/ssl/certs /etc/ssl/certs

USER nonroot

EXPOSE 53/udp 53/tcp

ENTRYPOINT ["/usr/local/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]