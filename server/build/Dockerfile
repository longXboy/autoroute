FROM ubuntu:latest
MAINTAINER Viz <viz@linux.com>

ENV DIR_SCRIPTS='/scripts' \
    BPATH='/tmp/build' \
    DPATH='/tmp/dist'

RUN apt-get update \
    && apt-get install -y git build-essential autoconf libtool libssl-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && mkdir "$BPATH"

RUN git clone https://github.com/shadowsocks/shadowsocks-libev.git "$BPATH"

COPY build /
CMD ["/build"]
