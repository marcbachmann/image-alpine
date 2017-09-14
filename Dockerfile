FROM multiarch/alpine:x86_64-v3.6 as node-exporter
ARG VERSION=0.14.0

RUN apk --no-cache add wget ca-certificates \
    && mkdir -p /tmp/install /tmp/dist \
    && wget -O /tmp/install/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v$VERSION/node_exporter-$VERSION.linux-amd64.tar.gz \
    && apk add --no-cache libc6-compat \
    && cd /tmp/install \
    && tar --strip-components=1 -xzf node_exporter.tar.gz \
    && mv node_exporter /bin/node_exporter

FROM multiarch/alpine:x86_64-v3.6 as fluent-bit
ENV FLB_MAJOR 0
ENV FLB_MINOR 12
ENV FLB_PATCH 1
ENV FLB_VERSION 0.12.1

RUN apk --no-cache --update add build-base ca-certificates cmake && \
    wget -O "/tmp/fluent-bit-$FLB_VERSION.tar.gz" "http://fluentbit.io/releases/$FLB_MAJOR.$FLB_MINOR/fluent-bit-$FLB_VERSION.tar.gz" && \
    cd /tmp && \
    tar zxfv "fluent-bit-$FLB_VERSION.tar.gz" && \
    cd "fluent-bit-$FLB_VERSION/build/" && \
    cmake -DFLB_DEBUG=On -DFLB_TRACE=On ../ \
      -DCMAKE_INSTALL_PREFIX=/fluent-bit/ && \
    make && make install && \
    rm -rf /tmp/* /fluent-bit/include /fluent-bit/lib* && \
    apk del build-base

RUN mkdir -p /fluent-bit/log


FROM multiarch/alpine:x86_64-v3.6

# Environment
ENV SCW_BASE_IMAGE scaleway/alpine:latest


# Adding and calling builder-enter
COPY ./overlay-image-tools/usr/local/sbin/scw-builder-enter /usr/local/sbin/
RUN /bin/sh -e /usr/local/sbin/scw-builder-enter


# Install packages
RUN apk update \
 && apk add \
    bash \
    busybox-suid \
    curl \
    openssh \
    tar \
    wget \
 && apk upgrade \
    openssl \
 && rm -rf /var/cache/apk/*


# Patch rootfs
COPY ./overlay/ ./overlay-image-tools/ /


# Configure autostart packages
RUN rc-update add sshd default\
 && rc-update add scw-ssh-keys default \
 && rc-update add ntpd default \
 && rc-update add hostname default \
 && rc-update add update-motd default \
 && rc-update add sysctl default \
 && rc-update add scw-sync-kernel-extra default \
 && rc-update add scw-initramfs-shutdown shutdown \
 && rc-status

# Update permissions
RUN chmod 700 /root

# Custom dependencies
COPY --from=node-exporter /bin/node_exporter /bin/node_exporter
COPY --from=fluent-bit /fluent-bit /fluent-bit
RUN apk add --no-cache \
  libc6-compat git docker

# Clean rootfs from image-builder
RUN /usr/local/sbin/scw-builder-leave
