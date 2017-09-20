FROM multiarch/alpine:x86_64-v3.6 as node-exporter
ENV VERSION=0.14.0

RUN apk --no-cache add wget ca-certificates libc6-compat && \
    mkdir -p /tmp/install && cd /tmp/install && \
    wget -O /tmp/install/node_exporter.tar.gz "https://github.com/prometheus/node_exporter/releases/download/v$VERSION/node_exporter-$VERSION.linux-amd64.tar.gz" && \
    tar --strip-components=1 -xzf node_exporter.tar.gz && \
    mv node_exporter /bin/node_exporter && \
    rm -Rf /tmp/install


FROM multiarch/alpine:x86_64-v3.6 as grok-exporter
ENV VERSION=0.2.1
ENV GOPATH=/tmp/install
ENV GOMODULE=github.com/fstab/grok_exporter
ENV CGO_LDFLAGS=/usr/lib/libonig.a

RUN apk add --no-cache musl-dev go git oniguruma-dev && \
    mkdir -p $GOPATH /etc/grok_exporter && \
    go get -d $GOMODULE && \
    cd $GOPATH/src/$GOMODULE && \
    git checkout v$VERSION && git checkout -b v$VERSION && \
    go build -ldflags "-X $GOMODULE/exporter.Version=$VERSION -X $GOMODULE/exporter.BuildDate=$(date +%Y-%m-%d) -X $GOMODULE/exporter.Branch=$(git rev-parse --abbrev-ref HEAD) -X $GOMODULE/exporter.Revision=$(git rev-parse --short HEAD)" -o /bin/grok_exporter && \
    mv $GOPATH/src/$GOMODULE/logstash-patterns-core/patterns /etc/grok_exporter/patterns


FROM multiarch/alpine:x86_64-v3.6 as fluent-bit
ENV FLB_MAJOR 0
ENV FLB_MINOR 12
ENV FLB_PATCH 2
ENV FLB_VERSION 0.12.2

RUN apk --no-cache add gcc linux-headers musl-dev file build-base ca-certificates cmake libressl && \
    wget -O "/tmp/fluent-bit-$FLB_VERSION.tar.gz" "http://fluentbit.io/releases/$FLB_MAJOR.$FLB_MINOR/fluent-bit-$FLB_VERSION.tar.gz" && \
    cd /tmp && \
    tar zxfv "fluent-bit-$FLB_VERSION.tar.gz" && \
    cd "fluent-bit-$FLB_VERSION/build/" && \
    cmake -DBUILD_SHARED_LIBS=OFF -DITK_DYNAMIC_LOADING=OFF -DFLB_DEBUG=On -DFLB_TRACE=On -DFLB_JEMALLOC=On -DFLB_BUFFERING=On -DCMAKE_INSTALL_PREFIX=/ ../ && \
    make && make install


FROM multiarch/alpine:x86_64-v3.6
ENV SCW_BASE_IMAGE scaleway/alpine:latest

# Adding and calling builder-enter
COPY ./overlay-image-tools/usr/local/sbin/scw-builder-enter /usr/local/sbin/
RUN /bin/sh -e /usr/local/sbin/scw-builder-enter

# Install scaleway packages
RUN apk update && apk upgrade && \
    apk add bash busybox-suid curl openssh tar wget libressl

# Update permissions
RUN chmod 700 /root

# Install custom dependencies
RUN apk add --no-cache nano util-linux e2fsprogs

# Logging
RUN apk add --no-cache logrotate && mv /etc/periodic/daily/logrotate /etc/periodic/15min/
COPY --from=fluent-bit /usr/bin/fluent-bit /usr/bin/fluent-bit

# Prometheus
COPY --from=node-exporter /bin/node_exporter /bin/node_exporter
COPY --from=grok-exporter /bin/grok_exporter /bin/grok_exporter
COPY --from=grok-exporter /etc/grok_exporter /etc/grok_exporter
RUN apk add --no-cache libc6-compat

# Docker
RUN apk add --no-cache git docker


# Patch rootfs
COPY ./overlay/ ./overlay-image-tools/ /

# Configure scaleway autostart packages
RUN rc-update add sshd default && \
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
    rc-update add cgroupfs-volumes default && \
    rc-update add nbd-volumes default && \
    rc-update add docker default && \
    rc-update add prometheus-node-exporter default  && \
    rc-update add prometheus-openrc-exporter default  && \
    rc-update add fluent-bit-system default  && \
    rc-update add fluent-bit-containers default


# Clean rootfs from image-builder
RUN /usr/local/sbin/scw-builder-leave
