FROM ubuntu:14.04
MAINTAINER Viz <viz@linux.com>

RUN apt-get update && apt-get install -y curl supervisor pdnsd dnsmasq iptables
COPY . /app/

CMD ["/app/start.sh"]
