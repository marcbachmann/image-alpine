# Alpine Linux image on Scaleway

[![Build Status](https://travis-ci.org/scaleway/image-alpine.svg?branch=master)](https://travis-ci.org/scaleway/image-alpine)
[![](https://badge.imagelayers.io/scaleway/alpine:latest.svg)](https://imagelayers.io/?images=scaleway/alpine:latest 'Get your own badge on imagelayers.io')

Scripts to build the official Alpine image on Scaleway

This image is built using [Image Tools](https://github.com/scaleway/image-tools) and depends on the [armbuild/alpine](https://registry.hub.docker.com/u/armbuild/alpine/) Docker image.

<img src="http://alpinelinux.org/alpinelinux-logo.svg" width="400px" />

---

**This image is meant to be used on a C1 server.**

We use the Docker's building system and convert it at the end to a disk image that will boot on real servers without Docker. Note that the image is still runnable as a Docker container for debug or for inheritance.

[More info](https://github.com/scaleway/image-tools#docker-based-builder)

---

## Install

Build and write the image to /dev/nbd1 (see [documentation](https://doc.cloud.online.net/howto/create_image.html))
```
$ make install
```
Full list of commands available at: [scaleway/image-tools](https://github.com/scaleway/image-tools/tree/master#commands)

set those env variables in /etc/conf.d/docker-container-logs
and /etc/conf.d/system-logs

```
HOST_NAME=foo
HOST_IP=bar
ELASTICSEARCH_HOST=fasdfsdf
ELASTICSEARCH_PORT=fasdf
ELASTICSEARCH_INDEX=fasf
ELASTICSEARCH_TYPE=fasdfsf
ELASTICSEARCH_USER=fasdf
ELASTICSEARCH_PASSWORD=fasdfs

rc-update add system-logs default
rc-service docker-daemon-logs start

```
