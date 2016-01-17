#!/bin/sh

set -e

# set -x for debug mode
[ -n "$DEBUG" ] && set -x

# check environment variables
echo "Check environment variables..."
[ -z "$SERVER_ADDR" ] \
  && { echo 'Fatal: Server address was not set!'; exit 1; }
[ -z "$SERVER_PORT" ] \
  && { echo 'Fatal: Server port was not set!'; exit 1; }
[ -z "$PASSWORD" ] \
  && { echo 'Fatal: Password was not set!'; exit 1; }
[ -z "$ENCRYPT_METHOD" ] \
  && { echo 'Fatal: Encrypt method was not set!'; exit 1; }
iptables -nL 2> /dev/null > /dev/null \
  || { echo 'Fatal: Please run the container in privileged mode!'; exit 1; }

# setup constants
CONFIG_DIR='/app/config'
GITHUB_RAW='https://raw.githubusercontent.com'

echo "Write configurations..."

# reset pdnsd configuration
cat << EOF > /etc/pdnsd.conf
global {
  perm_cache=2048;
  cache_dir="/var/cache/pdnsd";
  run_as="pdnsd";
  server_port = 5553;
  server_ip = any;
  status_ctl = on;
  paranoid=on;
  query_method=tcp_only;
  min_ttl=15m;
  max_ttl=1w;
  timeout=10;
}

server {
  label= "remotedns";
  ip = 8.8.8.8;
  root_server = on;
  uptest = none;
}
EOF

# reset dnsmasq configuration
[ -f "${CONFIG_DIR}/bypass.txt" ] \
  && BYPASS_LIST="$(cat "${CONFIG_DIR}/bypass.txt" | xargs | sed 's/ /\//g')"
DEFAULT_DNS='114.114.114.114'
if [ -n "$BYPASS_LIST" ]; then
  cat << EOF > /etc/dnsmasq.conf
no-resolv
strict-order
cache-size=2048
server=/${BYPASS_LIST}/${DEFAULT_DNS}
server=127.0.0.1#5453
EOF
else
  cat << EOF > /etc/dnsmasq.conf
no-resolv
cache-size=2048
server=127.0.0.1#5453
EOF
fi

echo "Initialize configuration..."

# prepare config directory
[ ! -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && mkdir -p "$CONFIG_DIR"

# initialize IP blacklist
[ ! -f "${CONFIG_DIR}/iplist.txt" ] \
  && curl -s "${GITHUB_RAW}/shadowsocks/ChinaDNS/master/iplist.txt" \
    > "${CONFIG_DIR}/iplist.txt"

# initialize china route
[ ! -f "${CONFIG_DIR}/chnroute.txt" ] \
  && curl -s 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' \
    | grep ipv4 \
    | grep CN \
    | awk -F\| '{ printf("%s/%d\n", $4, 32-log($5)/log(2)) }' \
      > "${CONFIG_DIR}/chnroute.txt"

########## start applying iptables rules ##########

# save old dns list
OLD_DNS="$(cat /etc/resolv.conf | grep '^nameserver [0-9.]*$' \
                                | grep -o '[0-9.]*' | xargs | sed 's/ /,/g')"
[ -n "$OLD_DNS" ] && OLD_DNS="${OLD_DNS},"

# backup current resolv.conf
cp /etc/resolv.conf /tmp/resolv.conf

# define helper
cleanup() {
  # restore resolv.conf
  cp /tmp/resolv.conf /etc/resolv.conf

  # clean up changes made to iptables
  iptables -t nat -D PREROUTING -p tcp -j SHADOWSOCKS 2> /dev/null || true
  iptables -t nat -D OUTPUT -p tcp -j SHADOWSOCKS 2> /dev/null || true
  iptables -t nat -F SHADOWSOCKS 2> /dev/null || true
  iptables -t nat -X SHADOWSOCKS 2> /dev/null || true

  # kill supervisord if found
  pkill supervisord || true
}

echo "Setup the trap..."

# clean up before exit
trap "cleanup; kill -9 $$; printf '\nexiting...\n'; exit 0" HUP INT TERM

# also clean up now if needed
cleanup

echo "Setup iptables..."

# create new chain for shadowsocks
iptables -t nat -N SHADOWSOCKS

# connect directly for the shadowsocks port
iptables -t nat -A SHADOWSOCKS -d "$SERVER_ADDR" \
         -p tcp --dport "$SERVER_PORT" -j RETURN

# connect directly for local network address
iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 169.254.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 224.0.0.0/4 -j RETURN
iptables -t nat -A SHADOWSOCKS -d 240.0.0.0/4 -j RETURN

# connect directly for IPs that belong to China
cat "${CONFIG_DIR}/chnroute.txt" | while read range; do
  iptables -t nat -A SHADOWSOCKS -d "$range" -j RETURN
done

# for other connections, go through the shadowsocks redirection service
[ -z "$INTERFACE" ] && INTERFACE=docker0
[ -z "$GATEWAY_PORT" ] && GATEWAY_PORT="$SERVER_PORT"
GATEWAY_IP="$(ip r | grep "$INTERFACE" | xargs -n1 | tail -n1)"
iptables -t nat -A SHADOWSOCKS -p tcp \
         -j DNAT --to-destination "${GATEWAY_IP}:${GATEWAY_PORT}"

# insert chain to the front of PREROUTING & OUTPUT chains
iptables -t nat -I PREROUTING -p tcp -j SHADOWSOCKS
iptables -t nat -I OUTPUT -p tcp -j SHADOWSOCKS

echo "Load runtime configurations..."

[ -d /scripts ] && find /scripts -type f -executable | sort | xargs -n1 sh -c

echo "Apply DNS server..."

# update resolv.conf
echo "nameserver ${GATEWAY_IP}" > /etc/resolv.conf

########## finish applying iptables rules ##########

echo "Start up the service..."

# export environment variables and start the supervisord
export PASSWORD
export SERVER_ADDR
export SERVER_PORT
export ENCRYPT_METHOD
export OLD_DNS
/usr/bin/supervisord -c /app/supervisord.conf &

# wait until stopped
while true; do
  sleep 5
done
