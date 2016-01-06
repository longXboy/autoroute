# Viz Autoroute

路由优化；自动翻墙

> 提示：这个服务是无状态的 :)

## 组件

* [shadowsocks-libev][1]
* [ChinaDNS][2]
* [pdnsd][3]
* [dnsmasq][4]
* [netfilter/iptables][5]
* [supervisord][6]

## 原理

GFW 墙一个网站一般有两种策略：

1. DNS 污染，使得域名无法解析到正确的 IP 地址。
2. 地址过滤，对于特定地址池的连接进行重置。

### 应对 DNS 污染

DNS 污染使用 ISP 节点对用户 DNS 请求的 UDP 封包进行劫持篡改，
使得用户获取错误的 IP 地址，这个 IP 通常是 GFW 的服务器，用来侦测翻墙服务。

对此这里首先使用 pdnsd 进行 TCP 而不是 UDP 的域名解析，由于解析时使用
shadowsocks-libev 通讯，可以获得可靠的国外 DNS 服务器解析结果。

接下来 ChinaDNS 使用多组 DNS 服务器（包括上述的一个可靠的国外 DNS
服务器）进行比对，优先解析到国内的 IP，同时过滤 GFW 的服务器。

为了保证解析速度，使用 dnsmasq 对结果进行缓存。

> 注意：一个可靠的国外 DNS 服务器通过 shadowsocks-libev 提供的 tunnel 映射。

### 应对地址过滤

地址过滤为 GFW 在国家之间的网关设置的过滤器，重置特定的来源和目标 IP 的数据包。

对此，使用 shadowsocks-libev 提供的 redir 服务将可能被重置的数据包重定向到
redir 服务并且通过 shadowsocks 传至出口进行请求。

### 自动翻墙策略

为了使自动翻墙成为可能，首先需要把 /etc/resolv.conf 中的 DNS 服务器指定为本地的
dnsmasq 服务器（也就是为什么需要
`-v /etc/resolv.conf:/etc/resolv.conf`）。接下来对于所有的出站流量使用 iptables
进行过滤，如果为国内 IP 则进行直连，否则通过 DNAT 定向到 redir
服务的地址和端口（因为要操作 `iptables`，容器需要 `--privileged --net=host`）。

> 注意：这里无法使用 REDIRECT 是因为容器内部没法以本地方式连接宿主中的
redir 服务。

### 国内 IP 列表以及 GFW 服务器黑名单

`viz-autoroute` 使用 `/app/config` 目录下的 `chnroute.txt` 作为国内 IP 列表、
`iplist.txt` 作为 GFW 服务器黑名单。

它们的初始内容为

* `chnroute.txt` 取自[亚太互联网络信息中心][7]，使用下列命令生成：

```
curl -s 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' \
        | grep ipv4 \
        | grep CN \
        | awk -F\| '{ printf("%s/%d\n", $4, 32-log($5)/log(2)) }' \
            > "${CONFIG_DIR}/chnroute.txt"
```

* `iplist.txt` 取自 [ChinaDNS 的默认列表][8]

> 注意：有些情况下 ISP 也会对 DNS 进行污染，解析至不在 `iplist.txt`
黑名单上的主机，这种情况请手动添加此 IP 到 `iplist.txt`。同理，如果一个 IP
可以直连，可以添加至 `chnroute.txt` 内以防止通过 shadowsocks 连接。

## 国外出口节点配置

出口节点需要使用 Docker Hub 上的 `shadowsocks/shadowsocks-libev` 这个镜像。

启动命令：

```bash
docker run \
       -p 18123:8338 \
       shadowsocks/shadowsocks-libev \
       -k <Shadowsocks Password> \
       -m <Shadowsocks Encryption Method> \
       -t 300 -u -v
```

## 国内客户节点配置

构建命令：

```bash
docker build -t viz-autoroute .
```

启动命令：

```bash
docker run --privileged --net=host \
       -e PASSWORD=<Shadowsocks Password> \
       -e SERVER_ADDR=<Shadowsocks Server Address> \
       -e SERVER_PORT=<Shadowsocks Server Port> \
       -e ENCRYPT_METHOD=<Shadowsocks Encryption Method> \
       -v /etc/viz-autoroute:/app/config \
       -v /etc/resolv.conf:/etc/resolv.conf \
       viz-autoroute
```

> 提示：可以通过设置环境变量 `INTERFACE`（默认为
`docker0`）来指定转发服务所绑定的网口。

> 提示：可以通过设置环境变量 `GATEWAY_PORT`（默认为 `SERVER_PORT`
的值）来指定转发服务所绑定的端口。

> 提示：可以绑定运行时配置文件目录到容器的 `/scripts`
目录下以执行额外的配置文件。

## TODO

* 监听 /etc/resolv.conf 的修改以及设置成目标 DNS 地址。
* 实现清空 DNS 缓存。
* 实现 obfsproxy 混淆的版本。

[1]:https://github.com/shadowsocks/shadowsocks-libev
[2]:https://github.com/shadowsocks/ChinaDNS
[3]:http://members.home.nl/p.a.rombouts/pdnsd/
[4]:http://www.thekelleys.org.uk/dnsmasq/doc.html
[5]:http://www.netfilter.org/
[6]:http://supervisord.org/
[7]:https://www.apnic.net/
[8]:https://raw.githubusercontent.com/shadowsocks/ChinaDNS/master/iplist.txt
