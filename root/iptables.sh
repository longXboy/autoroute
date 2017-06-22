curl -sL http://f.ip.cn/rt/chnroutes.txt | egrep -v '^$|^#' > cidr_cn

ipset -N cidr_cn hash:net
for i in `cat cidr_cn`; do echo ipset -A cidr_cn $i >> ipset.sh; done
chmod +x ipset.sh && ./ipset.sh
ipset -A cidr_cn 54.223.0.0/16

iptables -t nat -N shadowsocks

iptables -t nat -A shadowsocks -d 0/8 -j RETURN
iptables -t nat -A shadowsocks -d 127/8 -j RETURN
iptables -t nat -A shadowsocks -d 10/8 -j RETURN
iptables -t nat -A shadowsocks -d 169.254/16 -j RETURN
iptables -t nat -A shadowsocks -d 172.16/12 -j RETURN
iptables -t nat -A shadowsocks -d 192.168/16 -j RETURN
iptables -t nat -A shadowsocks -d 224/4 -j RETURN
iptables -t nat -A shadowsocks -d 240/4 -j RETURN


iptables -t nat -A shadowsocks -d 45.76.218.58 -j RETURN
iptables -t nat -A shadowsocks -d 107.191.52.71 -j RETURN
iptables -t nat -A shadowsocks -d 45.77.19.163 -j RETURN
iptables -t nat -A shadowsocks -d 45.76.204.75 -j RETURN
iptables -t nat -A shadowsocks -d 47.52.58.159 -j RETURN

iptables -t nat -A shadowsocks -d 54.223.211.84 -j RETURN
iptables -t nat -A shadowsocks -d 54.223.54.95 -j RETURN


iptables -t nat -A shadowsocks -m set --match-set cidr_cn dst -j RETURN
iptables -t nat -A shadowsocks ! -p icmp -j REDIRECT --to-ports 1080

iptables -t nat -A OUTPUT ! -p icmp -j shadowsocks
iptables -t nat -A PREROUTING ! -p icmp -j shadowsocks

iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ipforward

docker-compose -f nginx/docker-compose.yml up -d
docker-compose -f shadowsocks/docker-compose.yml up -d
docker-compose -f dns/docker-compose.yml up -d 
