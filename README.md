# 🛡️ Unbound DNS Resolver (Distroless, Hardened, DNSSEC, Docker)

This Docker container provides a minimal, secure, and high-performance [Unbound](https://nlnetlabs.nl/projects/unbound/about/) DNS resolver built from source and running on a [Distroless](https://github.com/GoogleContainerTools/distroless) base image.

## 🔒 Key Features

- Based on `distroless/base-debian12:nonroot`
- Built from Unbound **v1.23.0** source
- Hardened configuration with:
  - DNSSEC validation
  - Limited access control
  - Privacy optimizations
  - No root user
- Includes:
  - Root hints
  - DNSSEC trust anchor
- Debug-friendly Stage 1

## 🚀 Build

```bash
docker build -t unbound-dns:latest .
```

## 🧪 Test Locally

Run the container and bind port 53 (UDP/TCP):

```bash
docker run -d --name unbound \ 
  --cap-drop=ALL   
  --cap-add=NET_BIND_SERVICE   
  --security-opt no-new-privileges   
  -p 53:53/udp 
  -p 53:53/tcp
  unbound-dns:latest
```


## ⚙️ Configuration

The `unbound.conf` is optimized for:

- Local caching
- DNSSEC validation
- IPv4 and IPv6
- Security and performance

You can customize it in the Dockerfile stage or mount an override via `-v`.

## 📦 Runtime Environment

This image includes only necessary shared libraries and Unbound binaries.

- No shell
- No package manager
- No extra tools

Perfect for production environments focused on minimal attack surface.

## 🛠️ Debugging

To debug, rebuild the image from the `build` stage with:

```bash
docker build --target build -t unbound-dns-dev .
docker run -it --rm unbound-dns-dev /bin/bash
```

## 📁 Persistent DNSSEC Root Key

The trust anchor is stored at `/var/lib/unbound/root.key` with correct ownership (`nonroot:nonroot`, UID/GID 65532).

To update it periodically, bind-mount the directory and run a cron job outside the container.

## 📜 License

This project packages [Unbound](https://nlnetlabs.nl/projects/unbound/about/) under its BSD license.
