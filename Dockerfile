FROM ubuntu:14.04
MAINTAINER Viz <viz@linux.com>

RUN apt-get update && apt-get install -y curl supervisor dnsmasq iptables
COPY . /app/

EXPOSE 53/udp 18123/tcp
CMD ["/app/start.sh"]
