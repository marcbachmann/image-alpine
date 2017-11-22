FROM multiarch/alpine:x86_64-v3.6 as node-exporter
ENV VERSION=0.14.0

# available linux-386, linux-arm64, linux-amd64, linux-armv7, linux-armv6
RUN apk --no-cache add wget ca-certificates libc6-compat && \
    mkdir -p /tmp/install && cd /tmp/install && \
    wget -O /tmp/install/node_exporter.tar.gz "https://github.com/prometheus/node_exporter/releases/download/v$VERSION/node_exporter-$VERSION.linux-amd64.tar.gz" && \
    tar --strip-components=1 -xzf node_exporter.tar.gz && \
    mv node_exporter /bin/node_exporter

FROM multiarch/alpine:x86_64-v3.6 as process-exporter
ENV VERSION=0.1.0

RUN apk --no-cache add wget ca-certificates libc6-compat && \
    mkdir -p /tmp/install && cd /tmp/install && \
    wget -O /tmp/install/process-exporter.tar.gz "https://github.com/ncabatoff/process-exporter/releases/download/v$VERSION/process-exporter-$VERSION.linux-amd64.tar.gz" && \
    tar --strip-components=1 -xzf process-exporter.tar.gz && \
    mv process-exporter /bin/process_exporter

FROM multiarch/alpine:x86_64-v3.6 as cadvisor
ENV VERSION=0.28.1

RUN apk --no-cache add wget ca-certificates && \
    wget -O /bin/cadvisor "https://github.com/google/cadvisor/releases/download/v$VERSION/cadvisor" && \
    chmod +x /bin/cadvisor

FROM multiarch/alpine:x86_64-v3.6
ENV SCW_BASE_IMAGE scaleway/alpine:latest
COPY ./overlay/etc/apk /etc/apk

# Adding and calling builder-enter
COPY ./overlay-image-tools/usr/local/sbin/scw-builder-enter /usr/local/sbin/
RUN /bin/sh -e /usr/local/sbin/scw-builder-enter

# Install scaleway packages
RUN apk update && apk upgrade && \
    apk add bash busybox-suid curl openssh tar wget libressl

# Update permissions
RUN chmod 700 /root

# Install custom dependencies
RUN apk add --no-cache nano util-linux e2fsprogs fail2ban

# Logging
RUN apk add --no-cache syslog-ng logrotate && mv /etc/periodic/daily/logrotate /etc/periodic/15min/

# Prometheus
COPY --from=node-exporter /bin/node_exporter /usr/local/sbin/node_exporter
COPY --from=process-exporter /bin/process_exporter /usr/local/sbin/process_exporter
COPY --from=cadvisor /bin/cadvisor /usr/local/sbin/cadvisor

# Patch rootfs
COPY ./overlay/ ./overlay-image-tools/ /

# libc6-compat needed for node_exporter
RUN apk add --no-cache libc6-compat

# Docker
RUN apk add --no-cache git docker=17.10.0-r0

# Configure scaleway autostart packages
RUN rc-update add sshd default && \
    rc-update add fail2ban default && \
    rc-update add scw-ssh-keys default && \
    rc-update add ntpd default && \
    rc-update add hostname default && \
    rc-update add update-motd default && \
    rc-update add sysctl default && \
    rc-update add scw-sync-kernel-extra default && \
    rc-update add scw-initramfs-shutdown shutdown && \
    rc-status

# Configure custom autostart packages
RUN \
    rc-update add loopback default && \
    rc-update add syslog-ng default && \
    rc-update add cgroupfs-volumes default && \
    rc-update add nbd-volumes default && \
    rc-update add docker default && \
    rc-update add prometheus-node-exporter default && \
    rc-update add prometheus-process-exporter default && \
    rc-update add cadvisor default

# Clean rootfs from image-builder
RUN /usr/local/sbin/scw-builder-leave
