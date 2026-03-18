apt update
apt install -y unbound unbound-anchor dns-root-data \
               libevent-2.1-7t64 libnghttp2-14 libhiredis-dev

               
# 先备份默认配置
cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.bak

cat > /etc/unbound/unbound.conf << 'UNBOUND_EOF'

###############################################################
# Unbound — Standard_B2ats_v2 · 1GB RAM 严格版
# 缓存总量控制在 120MB 以内，防止 OOM
# 【注意：】 默认禁用 IPv6 网络
###############################################################

server:
    # ── 接口 ─────────────────────────────────────────────
    interface: 127.0.0.1
    interface: ::1
    # interface: 172.16.1.x    # ← WireGuard IP（按实际填写）
    port: 53
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    prefer-ip6: no
    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

    # ── 访问控制 ──────────────────────────────────────────
    access-control: 0.0.0.0/0 refuse
    access-control: ::0/0 refuse
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    access-control: 172.16.1.0/24 allow
    deny-any: yes

    # ── 线程（= vCPU = 2）────────────────────────────────
    num-threads: 2
    msg-cache-slabs:   2
    rrset-cache-slabs: 2
    infra-cache-slabs: 2
    key-cache-slabs:   2

    # ── 缓存（1GB 专项：总量 ≤ 120MB）───────────────────
    # msg-cache：存储完整 DNS 响应
    msg-cache-size:   32m      # 原 128MB → 32MB

    # rrset-cache：存储资源记录，= msg-cache × 2
    rrset-cache-size: 64m      # 原 256MB → 64MB

    # key-cache：DNSSEC 密钥
    key-cache-size:   16m      # 原 64MB → 16MB

    # neg-cache：NXDOMAIN 等负结果
    neg-cache-size:    8m      # 原 32MB → 8MB

    # 基础设施缓存（上游 RTT 统计，减少条目数节省内存）
    infra-cache-numhosts: 10000   # 原 100000 → 10000
    infra-host-ttl:       900

    # ── TTL 策略（减少重查，青岛客户端每次冷查耗时 50ms）─
    cache-min-ttl:          300   # 5 分钟最小 TTL
    cache-max-ttl:          86400
    cache-max-negative-ttl: 60

    # 预取（TTL 剩 10% 时后台刷新，避免缓存雪崩）
    prefetch:     yes
    prefetch-key: yes

    # 过期服务（TTL 超期继续响应，后台刷新）
    # 1GB 下极为重要：消除青岛客户端等待刷新的延迟峰值
    serve-expired:                yes
    serve-expired-ttl:            1800   # 30 分钟（原 1h → 减半节内存）
    serve-expired-reply-ttl:      30
    serve-expired-client-timeout: 500    # 500ms 等待最新答案

    # ── Socket 性能（1GB 缩小）────────────────────────────
    outgoing-range:          4096  # 原 8192 → 4096
    num-queries-per-thread:  1024  # 原 4096 → 1024

    # SO_REUSEPORT（多线程 UDP 负载均衡）
    so-reuseport: yes

    # Socket 缓冲（与 sysctl 匹配，1GB 版）
    so-rcvbuf: 1m    # 原 8MB → 1MB
    so-sndbuf: 1m

    # EDNS 缓冲大小（RFC 9210 推荐，避免分片）
    edns-buffer-size: 1232

    # TCP 连接复用
    tcp-reuse-timeout:       30000   # 30s
    max-reuse-tcp-queries:   500     # 原 2000 → 500
    tcp-idle-timeout:        15000
    tcp-upstream:            no

    jostle-timeout:          200
    outgoing-num-tcp:        20     # 原 50 → 20

    # ── DNSSEC ───────────────────────────────────────────
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    harden-dnssec-stripped: yes
    harden-algo-downgrade:  yes
    val-clean-additional:   yes
    val-permissive-mode:    no
    val-sig-skew-min:       3600
    val-sig-skew-max:       86400
    val-nsec3-keysize-iterations: "1024 150 2048 500 4096 2500"

    # ── 安全加固 ─────────────────────────────────────────
    hide-identity:             yes
    hide-version:              yes
    use-caps-for-id:           yes   # 0x20 防缓存投毒
    qname-minimisation:        yes
    qname-minimisation-strict: no
    harden-glue:               yes
    harden-below-nxdomain:     yes
    harden-referral-path:      yes
    harden-short-bufsize:      yes
    harden-large-queries:      yes
    aggressive-nsec:           yes
    unwanted-reply-threshold:  10000000

    # 私有地址防 rebinding
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 100.64.0.0/10
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
    private-domain:  "anima.internal"

    module-config: "validator iterator"

    # ── 日志（PCI-DSS 10.x）─────────────────────────────
    use-syslog: yes
    logfile: ""
    log-time-ascii:      yes
    verbosity:           1
    log-queries:         yes
    log-replies:         yes
    log-tag-queryreply:  yes
    log-local-actions:   yes
    log-servfail:        yes

    # ── 根提示 ───────────────────────────────────────────
    root-hints: "/usr/share/dns/root.hints"

    # ── 本地域名 ─────────────────────────────────────────
    local-zone: "anima.internal." static
    local-data: "vpsa.anima.internal.   3600 IN A 172.16.1.1"
    local-data: "cxi4.anima.internal.   3600 IN A 172.16.1.5"
    local-zone: "16.172.in-addr.arpa."  static
    local-zone: "168.192.in-addr.arpa." static
    local-zone: "10.in-addr.arpa."      static

    # ── 性能 ─────────────────────────────────────────────
    fast-server-permil: 900
    fast-server-num:    3

remote-control:
    control-enable:    yes
    control-interface: 127.0.0.1
    control-port:      8953
    server-key-file:   "/etc/unbound/unbound_server.key"
    server-cert-file:  "/etc/unbound/unbound_server.pem"
    control-key-file:  "/etc/unbound/unbound_control.key"
    control-cert-file: "/etc/unbound/unbound_control.pem"

include-toplevel: "/etc/unbound/conf.d/*.conf"
UNBOUND_EOF

echo "✓ unbound.conf 写入完成"
