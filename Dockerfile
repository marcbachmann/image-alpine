ARG ARCH=amd64

FROM ${ARCH}/golang:1.8 as exporters
ARG ARCH=amd64

RUN go get -d github.com/prometheus/node_exporter
WORKDIR /go/src/github.com/prometheus/node_exporter
RUN git checkout v0.15.2 && GOARCH=$ARCH go build -o /bin/node_exporter

RUN apk --no-cache add wget ca-certificates libc6-compat && \
    mkdir -p /tmp/install && cd /tmp/install && \
    wget -O /tmp/install/process-exporter.tar.gz "https://github.com/ncabatoff/process-exporter/releases/download/v0.1.0/process-exporter-$VERSION.linux-$ARCH.tar.gz" && \
    tar --strip-components=1 -xzf process-exporter.tar.gz && \
    mv process-exporter /bin/process_exporter

# For some reason this only works when executing the build manually
# RUN go get -d github.com/ncabatoff/process-exporter
# WORKDIR /go/src/github.com/ncabatoff/process-exporter
# RUN git checkout v0.2.0 && GOARCH=$ARCH go build -o /bin/process_exporter -a -tags netgo

RUN go get -d github.com/google/cadvisor
WORKDIR /go/src/github.com/google/cadvisor
RUN git checkout v0.29.1
RUN GO_CMD=build GOARCH=$ARCH ./build/build.sh && cp cadvisor /bin/cadvisor


FROM multiarch/alpine:${ARCH}-v3.7
COPY ./overlay/etc/apk /etc/apk

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
COPY --from=exporters /bin/node_exporter /usr/local/sbin/node_exporter
COPY --from=exporters /bin/process_exporter /usr/local/sbin/process_exporter
COPY --from=exporters /bin/cadvisor /usr/local/sbin/cadvisor

# Patch rootfs
COPY ./overlay/ ./overlay-image-tools/ /

# libc6-compat needed for node_exporter
RUN apk add --no-cache libc6-compat

# findutils is needed for cadvisor
RUN apk add --no-cache findutils

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
RUN rc-update add local default && \
    rc-update add loopback default && \
    rc-update add syslog-ng default && \
    rc-update add cgroupfs-volumes default && \
    rc-update add nbd-volumes default && \
    rc-update add docker default && \
    rc-update add prometheus-node-exporter default && \
    rc-update add prometheus-process-exporter default && \
    rc-update add cadvisor default

# Clean cache and logs
RUN rm -rf /var/cache/apk/* && rm -Rf /root/.history /root/.bash_history /var/log/*
