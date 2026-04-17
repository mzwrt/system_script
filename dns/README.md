# Azure Japan DNS 服务器完整建设教程
## Standard_B2ats_v2 · Debian 13 · CIS + PCI-DSS · 青岛→日本

---

> **环境概览**
> | 项目 | 值 |
> |------|-----|
> | 主机型号 | Standard_B2ats_v2（2 vCPU AMD EPYC / 1 GB RAM / 64 GB SSD） |
> | 系统 | Debian 13 (Trixie) |
> | 机房 | Azure Japan East |
> | 使用位置 | 青岛（约 900 km，RTT ≈ 50–70 ms） |
> | 已有组件 | Nginx + ModSecurity OWASP CRS · UFW |
> | DNS 软件 | **Unbound**（轻量递归缓存 DNS，最适合 1 GB 内存） |
> | 合规要求 | CIS Benchmark Level 2 · PCI-DSS v4.0 |

---

## 目录

1. [系统基线准备](#1-系统基线准备)
2. [内核与网络深度调优](#2-内核与网络深度调优)
3. [Unbound 安装与核心配置](#3-unbound-安装与核心配置)
4. [CIS 合规加固](#4-cis-合规加固)
5. [PCI-DSS 合规配置](#5-pci-dss-合规配置)
6. [UFW 防火墙规则集成](#6-ufw-防火墙规则集成)
7. [DNSSEC 验证配置](#7-dnssec-验证配置)
8. [DNS-over-TLS 加密传输](#8-dns-over-tls-加密传输)
9. [缓存与性能极限调优](#9-缓存与性能极限调优)
10. [监控与日志审计](#10-监控与日志审计)
11. [自动化维护脚本](#11-自动化维护脚本)
12. [验证与测试完整流程](#12-验证与测试完整流程)
13. [故障排查速查表](#13-故障排查速查表)

---

## 1. 系统基线准备

### 1.1 确认系统版本与资源

```bash
# 确认 Debian 版本
cat /etc/os-release | grep -E "NAME|VERSION"

# 确认 CPU 信息（B2ats_v2 = AMD EPYC）
lscpu | grep -E "Architecture|CPU\(s\)|Model name"

# 确认内存（必须 ~1 GB）
free -h

# 确认磁盘
df -h /

# 确认内核版本（Debian 13 应为 6.x）
uname -r
```

### 1.2 系统完整更新

```bash
# 更新所有软件包
apt update && apt full-upgrade -y

# 安装必要工具
apt install -y \
  unbound \
  unbound-anchor \
  dns-root-data \
  dnsutils \
  curl \
  wget \
  iproute2 \
  fail2ban \
  logrotate \
  systemd-timesyncd \
  libpam-pwquality \
  acl \
  rkhunter \
  htop \
  iotop \
  tcpdump \
  jq \
  bc \
  dnsutils \
  unbound-host

# 清理无用包
apt autoremove -y && apt autoclean -y
```

### 1.3 时间同步（PCI-DSS 10.6 要求）

```bash
# 配置 systemd-timesyncd 时间同步（日本NTP服务器）
{
   a_settings=("NTP=time.nist.gov" "FallbackNTP=time-a-g.nist.gov time-b-g.nist.gov time-c-g.nist.gov")
   [ ! -d /etc/systemd/timesyncd.conf.d/ ] && mkdir /etc/systemd/timesyncd.conf.d/
   if grep -Psq -- '^\h*\[Time\]' /etc/systemd/timesyncd.conf.d/60-timesyncd.conf; then
      printf '%s\n' "" "${a_settings[@]}" >> /etc/systemd/timesyncd.conf.d/60-timesyncd.conf
   else
      printf '%s\n' "" "[Time]" "${a_settings[@]}" >> /etc/systemd/timesyncd.conf.d/60-timesyncd.conf
   fi
}

systemctl reload systemd-timesyncd
systemctl restart systemd-timesyncd

```

---

## 2. 内核与网络深度调优

> **关键点：** Standard_B2ats_v2 是 Burstable 机型，1 GB 内存极为有限。
> 所有参数均针对「低内存 + 高 I/O 效率 + 跨海低延迟」场景精心计算。

### 2.1 TCP BBR + 网络栈全面调优

```bash
# 创建专用网络优化配置文件
cat > /etc/sysctl.d/99-dns-performance.conf << 'EOF'
###############################################################
# Azure Standard_B2ats_v2 网络优化 - DNS 服务器专用
# Debian 13 · CIS Level 2 · PCI-DSS v4.0
###############################################################

#==============================================================
# TCP 拥塞控制 - BBR（Google 算法，跨海场景最优）
#==============================================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

#==============================================================
# Socket 缓冲区（1GB 内存下的安全值）
# DNS 请求小包为主，不需要超大缓冲
#==============================================================
# 核心接收/发送缓冲（4MB 最大，适合 1GB RAM）
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 4194304

# TCP 接收/发送缓冲（min / default / max）
net.ipv4.tcp_rmem = 4096 131072 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304

# UDP 缓冲（DNS 主要用 UDP，适当加大）
net.core.netdev_max_backlog = 8192
net.core.somaxconn = 4096

#==============================================================
# TCP 连接优化（跨海长延迟优化）
#==============================================================
# TCP Fast Open（减少握手延迟）
net.ipv4.tcp_fastopen = 3

# 减少 TIME_WAIT（高并发 DNS 请求）
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 32768

# keepalive 优化（减少重连开销）
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# SYN 优化
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 4096


# 窗口扩展（必须，跨海 BDP 补偿）
net.ipv4.tcp_window_scaling = 1

# SACK（丢包重传优化）
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1

# MTU 探测（Azure 网络 MTU=1500）
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024

# 时间戳（改善延迟测量）
net.ipv4.tcp_timestamps = 1

#==============================================================
# UDP 优化（DNS 主要协议）
#==============================================================
net.ipv4.udp_mem = 8192 16384 65536
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

#==============================================================
# 文件描述符限制（高并发 DNS）
#==============================================================
fs.file-max = 1000000
fs.nr_open = 1048576

#==============================================================
# 内存管理（1 GB 特别优化）
#==============================================================
# 减少 swap 使用（DNS 实时性要求高，不能 swap）
vm.swappiness = 5

# 脏页刷新（SSD 优化）
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.dirty_expire_centisecs = 1000
vm.dirty_writeback_centisecs = 100

# 过度提交（Unbound 需要）
vm.overcommit_memory = 0
vm.overcommit_ratio = 50

# 内核大页（1GB内存不适合启用 hugepages）
vm.nr_hugepages = 0

#==============================================================
# CIS Level 2 安全加固 - 网络部分
#==============================================================
# 禁止 IP 转发（纯 DNS 服务器不需要路由）
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 禁止源路由
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 禁止 ICMP 重定向接受
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 禁止发送 ICMP 重定向
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 记录可疑包（审计用）
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 反向路径过滤（防 IP 欺骗）
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 禁止响应广播 ping（Smurf 防护）
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 忽略虚假 ICMP 错误（防 ICMP 洪泛）
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN Cookie（防 SYN 洪泛）
net.ipv4.tcp_syncookies = 1

# 禁止 IPv6 路由通告自动配置（服务器不需要）
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

#==============================================================
# 内核安全加固
#==============================================================
# ASLR（地址随机化）最高级别
kernel.randomize_va_space = 2

# 禁止 dmesg 泄露（CIS 要求）
kernel.dmesg_restrict = 1

# 禁止 kptr 泄露
kernel.kptr_restrict = 2

# 限制 ptrace（防提权）
kernel.yama.ptrace_scope = 1

# 核心转储限制
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# perf_event 限制
kernel.perf_event_paranoid = 3
EOF

# 应用所有配置
sysctl -p /etc/sysctl.d/99-dns-performance.conf

# 验证 BBR 已启用
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr
```

### 2.2 系统文件描述符与进程限制

```bash
# 配置系统级限制
cat > /etc/security/limits.d/99-dns-limits.conf << 'EOF'
# Unbound DNS 服务器进程限制
unbound  soft  nofile  65536
unbound  hard  nofile  65536
unbound  soft  nproc   512
unbound  hard  nproc   512
unbound  soft  memlock unlimited
unbound  hard  memlock unlimited

# Root 用户
root     soft  nofile  65536
root     hard  nofile  65536
EOF

# PAM limits 模块确认启用
grep -q "pam_limits" /etc/pam.d/common-session || \
  echo "session required pam_limits.so" >> /etc/pam.d/common-session
```

### 2.3 IRQ 亲和性与 CPU 调优

```bash
# 检查 CPU 调速器（Azure VM 通常已是 performance 模式）
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || \
  echo "虚拟机无 cpufreq 控制，Azure 已托管"

# 安装 irqbalance（多核 IRQ 均衡）
apt install -y irqbalance
systemctl enable --now irqbalance

# 检查网卡队列（Azure 虚拟网卡）
ls /sys/class/net/eth0/queues/ 2>/dev/null || \
  ls /sys/class/net/*/queues/ 2>/dev/null

# 如果有多队列，设置接收散列
ethtool -K eth0 rx-hashing on 2>/dev/null || true
ethtool -K eth0 tx-nocache-copy off 2>/dev/null || true
```

### 2.4 磁盘 I/O 调优（SSD 优化）

```bash
# Azure Premium SSD 调度器优化
# Debian 13 默认 mq-deadline，对 SSD 改用 none 或 kyber
DISK=$(lsblk -d -n -o NAME | grep -E "^sd|^vd|^nvme" | head -1)
echo "检测到磁盘: $DISK"

# 设置 SSD 调度器
echo "none" > /sys/block/${DISK}/queue/scheduler 2>/dev/null || \
echo "mq-deadline" > /sys/block/${DISK}/queue/scheduler

# 持久化
cat > /etc/udev/rules.d/60-scheduler.rules << 'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|nvme[0-9]n[0-9]", \
  ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
EOF

# 降低 read-ahead（DNS 数据库文件随机访问为主）
blockdev --setra 256 /dev/${DISK} 2>/dev/null || true
```

---

## 3. Unbound 安装与核心配置

> **选择 Unbound 的理由：**
> - 内存占用约 30–80 MB（适合 1 GB 限制）
> - 递归 + 缓存一体，无需分离
> - 原生 DNSSEC 验证
> - CIS/PCI-DSS 友好架构

### 3.1 创建目录结构

```bash
# 创建必要目录
mkdir -p /etc/unbound/conf.d
mkdir -p /var/log/unbound
mkdir -p /var/cache/unbound
mkdir -p /etc/unbound/keys

# 设置权限
chown -R unbound:unbound /var/log/unbound
chown -R unbound:unbound /var/cache/unbound
chown -R root:unbound /etc/unbound/keys
chmod 750 /etc/unbound/keys

# 查看 Unbound 版本
unbound -V
```

### 3.2 下载 Root Hints（根域名服务器列表）

```bash
# 下载最新根服务器列表
curl -sS https://www.internic.net/domain/named.cache \
  -o /var/cache/unbound/root.hints

# 验证文件
head -20 /var/cache/unbound/root.hints
chown unbound:unbound /var/cache/unbound/root.hints
```

### 3.3 DNSSEC 根信任锚

```bash
# 初始化 DNSSEC 根信任锚（必须在配置前完成）
unbound-anchor -a /var/cache/unbound/root.key -v

# 设置权限
chown unbound:unbound /var/cache/unbound/root.key
chmod 640 /var/cache/unbound/root.key

# 验证
cat /var/cache/unbound/root.key | head -5
```

### 3.4 主配置文件

```bash
# 备份原始配置
cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.bak

# 创建主配置文件
cat > /etc/unbound/unbound.conf << 'EOF'
###############################################################
# Unbound DNS 主配置文件
# Standard_B2ats_v2 | Debian 13 | Azure Japan East
# CIS Benchmark Level 2 | PCI-DSS v4.0
###############################################################

server:
    ###########################################################
    # 基础设置
    ###########################################################
    
    # 详细程度（1=normal, 2=verbose; 生产用 1）
    verbosity: 1
    
    # 统计信息输出间隔（秒，0=禁用）
    statistics-interval: 3600
    statistics-cumulative: yes
    extended-statistics: yes
    
    # 日志配置
    use-syslog: no
    logfile: "/var/log/unbound/unbound.log"
    log-queries: no          # 生产环境关闭（PCI-DSS 减少敏感日志）
    log-replies: no
    log-servfail: yes        # 记录服务失败（审计必要）
    log-local-actions: yes
    log-tag-queryreply: no
    
    ###########################################################
    # 监听配置
    ###########################################################
    
    # 监听所有 IPv4 接口（DNS 标准端口）
    interface: 0.0.0.0
    interface: ::0
    port: 53
    
    # DNS-over-TLS 端口（加密传输，851 端口保留 853 给 DoT）
    # 详见第 8 节
    
    # 协议启用
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    
    # TCP MSS（避免分片，Azure 网络 MTU=1500）
    tcp-mss: 1220
    
    ###########################################################
    # 访问控制（CIS + PCI-DSS 最小权限）
    ###########################################################
    
    # 默认拒绝所有（白名单模式）
    access-control: 0.0.0.0/0 refuse
    access-control: ::0/0 refuse
    
    # 仅允许本地回环（Nginx/本地服务查询）
    access-control: 127.0.0.0/8 allow
    access-control: ::1/128 allow
    
    # 【重要】在此添加你的中国客户端 IP
    # 示例：允许青岛固定 IP（请替换为你的实际 IP）
    # access-control: 1.2.3.4/32 allow
    # access-control: 5.6.7.0/24 allow
    
    # 允许 Azure VNET 内部访问（按需开启）
    # access-control: 10.0.0.0/8 allow
    
    # 拒绝时返回 REFUSED（不泄露信息）
    access-control: 192.168.0.0/16 refuse
    access-control: 172.16.0.0/12 refuse
    
    ###########################################################
    # 用户与权限（安全加固）
    ###########################################################
    
    # 以 unbound 用户运行（非 root）
    username: "unbound"
    
    # chroot 沙箱（CIS 强制）
    chroot: ""
    
    # PID 文件
    pidfile: "/run/unbound.pid"
    
    # 工作目录
    directory: "/var/cache/unbound"
    
    ###########################################################
    # 性能调优（针对 2 vCPU / 1 GB RAM）
    ###########################################################
    
    # 工作线程数 = vCPU 数量（B2ats_v2 = 2）
    num-threads: 2
    
    # 每线程查询滑动窗口（内存 = num-threads × msg-cache-slabs × 大小）
    # 1 GB 内存下安全值
    msg-cache-slabs: 4
    rrset-cache-slabs: 4
    infra-cache-slabs: 4
    key-cache-slabs: 4
    
    # 缓存大小（总计约 256 MB，为系统保留 512 MB）
    msg-cache-size: 64m
    rrset-cache-size: 128m
    key-cache-size: 16m
    neg-cache-size: 8m
    infra-cache-numhosts: 20000
    
    # 每线程 outgoing 连接槽（上游 DNS 并发连接）
    outgoing-range: 256
    
    # 并发查询队列
    num-queries-per-thread: 1024
    
    # jostle 超时（防止慢查询阻塞）
    jostle-timeout: 200
    
    # 连接 backlog
    so-rcvbuf: 4m
    so-sndbuf: 4m
    so-reuseport: yes
    
    # UDP 端口随机化（安全 + 性能）
    outgoing-num-tcp: 16
    incoming-num-tcp: 100
    
    # 端口范围（随机化防缓存投毒）
    outgoing-port-permit: 1024-65535
    outgoing-port-avoid: 0-1023
    
    ###########################################################
    # 缓存策略（低延迟优化）
    ###########################################################
    
    # 缓存最小 TTL（防止极短 TTL 导致频繁回源）
    cache-min-ttl: 60
    
    # 缓存最大 TTL（24 小时）
    cache-max-ttl: 86400
    
    # 负向缓存 TTL（NXDOMAIN 等）
    cache-max-negative-ttl: 3600
    
    # 预取（TTL 剩余 10% 时后台刷新，减少首次延迟）
    prefetch: yes
    prefetch-key: yes
    
    # 缓存过期响应（网络故障时继续服务，PCI-DSS 允许）
    serve-expired: yes
    serve-expired-ttl: 86400
    serve-expired-client-timeout: 1800
    
    # 最小响应（降低带宽，无需发送大型附加 section）
    minimal-responses: yes
    
    # qname 最小化（隐私保护，减少上游暴露）
    qname-minimisation: yes
    qname-minimisation-strict: no
    
    ###########################################################
    # DNSSEC 配置（PCI-DSS 4.0 要求数据完整性）
    ###########################################################
    
    # 根信任锚
    auto-trust-anchor-file: "/var/cache/unbound/root.key"
    
    # DNSSEC 剥离保护
    harden-dnssec-stripped: yes
    
    # 验证失败时 SERVFAIL（不降级）
    val-clean-additional: yes
    val-permissive-mode: no
    
    # 允许 DNSSEC bogus 数据超时（避免单点故障）
    val-bogus-ttl: 60
    val-sig-skew-min: -3600
    val-sig-skew-max: 3600
    
    ###########################################################
    # 安全加固（CIS Level 2 + PCI-DSS）
    ###########################################################
    
    # 禁止版本查询（防信息泄露）
    hide-version: yes
    hide-identity: yes
    identity: "dns"
    version: "dns"
    
    # 禁止 chaos 查询（版本探测防御）
    hide-trustanchor: yes
    
    # 随机 ID（防预测攻击）
    use-caps-for-id: yes
    
    # 防止 DNS 放大攻击
    access-control-tag: 0.0.0.0/0 "deny"
    
    # 拒绝私有地址解析（防 DNS 重绑定攻击）
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
    private-address: ::ffff:0:0/96
    
    # 防止 NXDOMAIN 劫持
    harden-referral-path: yes
    
    # 禁止 glue 记录域外解析（防止 cache poisoning）
    harden-glue: yes
    
    # 强制 DNSSEC 签名验证
    harden-large-queries: yes
    
    # 阻止子域 NXDOMAIN（减少 lookup 链）
    harden-short-bufsize: yes
    
    # 额外安全
    harden-below-nxdomain: yes
    harden-algo-downgrade: yes
    
    # 禁止 ID 0 响应
    harden-unknown-additional: yes
    
    # 最大迭代次数（防止 DNS 循环）
    max-iter-stop-depth: 11
    
    # 防止 DNS 劫持（上游必须权威响应）
    unwanted-reply-threshold: 10000000
    
    # 大型 EDNS 缓冲（减少 UDP 分片）
    edns-buffer-size: 1232
    
    # 禁止 ANY 查询（防止 DNS 放大）
    deny-any: yes
    
    # 禁止本地区域递归外泄
    do-not-query-localhost: yes
    
    # root hints 文件
    root-hints: "/var/cache/unbound/root.hints"
    
    ###########################################################
    # 本地区域配置（内部解析）
    ###########################################################
    
    # 拒绝 RFC 6761 特殊域名
    local-zone: "localhost." static
    local-zone: "127.in-addr.arpa." static
    local-zone: "invalid." refuse
    local-zone: "test." refuse
    local-zone: "example." refuse
    local-zone: "local." refuse
    
    # RFC 1918 反向解析拒绝（防止泄露内网信息）
    local-zone: "10.in-addr.arpa." refuse
    local-zone: "168.192.in-addr.arpa." refuse
    local-zone: "16.172.in-addr.arpa." refuse
    local-zone: "17.172.in-addr.arpa." refuse
    local-zone: "18.172.in-addr.arpa." refuse
    local-zone: "19.172.in-addr.arpa." refuse
    local-zone: "20.172.in-addr.arpa." refuse
    local-zone: "21.172.in-addr.arpa." refuse
    local-zone: "22.172.in-addr.arpa." refuse
    local-zone: "23.172.in-addr.arpa." refuse
    local-zone: "24.172.in-addr.arpa." refuse
    local-zone: "25.172.in-addr.arpa." refuse
    local-zone: "26.172.in-addr.arpa." refuse
    local-zone: "27.172.in-addr.arpa." refuse
    local-zone: "28.172.in-addr.arpa." refuse
    local-zone: "29.172.in-addr.arpa." refuse
    local-zone: "30.172.in-addr.arpa." refuse
    local-zone: "31.172.in-addr.arpa." refuse
    
    # localhost 本地记录
    local-data: "localhost. 10800 IN NS localhost."
    local-data: "localhost. 10800 IN SOA localhost. nobody.invalid. 1 3600 1200 604800 10800"
    local-data: "localhost. 10800 IN A 127.0.0.1"
    local-data: "localhost. 10800 IN AAAA ::1"
    local-data: "1.0.0.127.in-addr.arpa. 10800 IN PTR localhost."
    local-data: "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa. 10800 IN PTR localhost."
    
    ###########################################################
    # 上游转发（可选：转发到国际权威 DNS）
    ###########################################################
    # 注意：注释掉此段则使用纯递归（直接查根服务器，最准确）
    # 如需加速可启用转发到 Cloudflare/Google

# 远程控制接口（本地 Unix socket，监控用）
remote-control:
    control-enable: yes
    control-interface: 127.0.0.1
    control-port: 8953
    control-use-cert: yes
    server-key-file: "/etc/unbound/keys/unbound_server.key"
    server-cert-file: "/etc/unbound/keys/unbound_server.pem"
    control-key-file: "/etc/unbound/keys/unbound_control.key"
    control-cert-file: "/etc/unbound/keys/unbound_control.pem"

# 包含子配置文件
include-toplevel: "/etc/unbound/conf.d/*.conf"
EOF
```

### 3.5 生成远程控制证书

```bash
# 生成 Unbound 控制证书（用于 unbound-control 工具）
unbound-control-setup -d /etc/unbound/keys

# 设置权限
chmod 600 /etc/unbound/keys/*.key
chmod 644 /etc/unbound/keys/*.pem
chown unbound:unbound /etc/unbound/keys/*
```

### 3.6 可选转发配置（提升中国访问速度）

```bash
# 如果需要转发到快速上游 DNS（例如减少递归延迟）
# 注意：PCI-DSS 要求上游必须可信且加密
cat > /etc/unbound/conf.d/forwarders.conf << 'EOF'
# 可选上游转发器（注释状态，按需启用）
# 如果启用，将放弃纯递归模式

# forward-zone:
#     name: "."
#     # Cloudflare DNS-over-TLS
#     forward-tls-upstream: yes
#     forward-addr: 1.1.1.1@853#cloudflare-dns.com
#     forward-addr: 1.0.0.1@853#cloudflare-dns.com
#     # Google DNS-over-TLS
#     forward-addr: 8.8.8.8@853#dns.google
#     forward-addr: 8.8.4.4@853#dns.google
EOF
```

### 3.7 启动服务

```bash
# 检查配置语法
unbound-checkconf

# 如果有错误，检查日志：
# unbound -d -vvv 2>&1 | head -50

# 启用并启动
systemctl enable unbound
systemctl start unbound

# 等待启动完成
sleep 2

# 验证状态
systemctl status unbound

# 验证监听端口
ss -tulnp | grep unbound
```

---

## 4. CIS 合规加固

### 4.1 SSH 加固（CIS Section 5.2）

```bash
# 备份 SSH 配置
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config << 'EOF'
###############################################################
# SSH 配置 - CIS Benchmark Level 2
###############################################################

# 协议版本（仅 SSH2）
Protocol 2

# 监听地址（仅 IPv4，按需调整）
Port 22
AddressFamily inet
ListenAddress 0.0.0.0

# 主机密钥（仅 Ed25519 和 RSA 4096）
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# 认证
PermitRootLogin no
MaxAuthTries 3
MaxSessions 3
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# 加密套件（仅现代算法，PCI-DSS 要求）
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# 功能限制
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no
AllowStreamLocalForwarding no

# 会话管理
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# 日志（CIS 要求）
SyslogFacility AUTH
LogLevel VERBOSE

# 禁止弱功能
IgnoreRhosts yes
HostbasedAuthentication no

# 只允许特定用户（修改为你的用户名）
# AllowUsers yourusername

# Banner（PCI-DSS 9.2 警告信息）
Banner /etc/issue.net
EOF

# 创建登录 Banner（PCI-DSS 合规）
cat > /etc/issue.net << 'EOF'
**********************************************************************
WARNING: Authorized access only. All activity monitored and logged.
         Unauthorized access is prohibited and will be prosecuted.
**********************************************************************
EOF

# 重新生成强 SSH 主机密钥
rm -f /etc/ssh/ssh_host_*key*
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" -q

# 验证配置
sshd -t

# 重启 SSH
systemctl restart sshd
```

### 4.2 用户账户安全（CIS Section 5.4）

```bash
# 密码策略
cat > /etc/security/pwquality.conf << 'EOF'
# PCI-DSS 8.3 密码复杂度要求
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
maxrepeat = 3
maxsequence = 4
gecoscheck = 1
badwords = password admin dns server azure
enforcing = 1
EOF

# PAM 密码策略
cat > /etc/pam.d/passwd << 'EOF'
password requisite pam_pwquality.so retry=3
password sufficient pam_unix.so sha512 shadow nullok try_first_pass use_authtok rounds=65536
password required pam_deny.so
EOF

# 锁定策略（PCI-DSS 8.3.4：6次失败锁定）
cat > /etc/pam.d/common-auth << 'EOF'
auth required pam_faillock.so preauth silent deny=6 unlock_time=900 fail_interval=900
auth [success=1 default=ignore] pam_unix.so nullok
auth [default=die] pam_faillock.so authfail deny=6 unlock_time=900 fail_interval=900
auth sufficient pam_faillock.so authsucc
auth requisite pam_deny.so
auth required pam_permit.so
EOF

# 账户过期设置
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    14/' /etc/login.defs

# 锁定不必要的系统账户
for user in daemon bin sys games man lp mail news uucp proxy www-data backup list irc gnats; do
    usermod -L -s /sbin/nologin $user 2>/dev/null || true
done
```

### 4.3 内核模块限制（CIS Section 3）

```bash
# 禁用不需要的内核模块
cat > /etc/modprobe.d/cis-hardening.conf << 'EOF'
# CIS Level 2 - 禁用不必要协议

# 不需要的文件系统
install cramfs /bin/false
install freevxfs /bin/false
install hfs /bin/false
install hfsplus /bin/false
install jffs2 /bin/false
install squashfs /bin/false
install udf /bin/false

# 网络协议（DNS 服务器不需要）
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false

# 不需要的网络功能
install bluetooth /bin/false
install btusb /bin/false
install net-pf-31 /bin/false
EOF

# 更新 initramfs
update-initramfs -u -k all
```

### 4.4 审计系统（auditd - CIS Section 4）

```bash
# 配置 auditd（CIS Level 2 完整审计规则）
cat > /etc/audit/rules.d/cis-audit.rules << 'EOF'
# 清除已有规则
-D

# 设置缓冲区大小（内存有限，适当调小）
-b 512

# 失败模式（1=打印警告，2=panic）
-f 1

# ========= 系统调用审计 =========

# 身份验证事件（PCI-DSS 10.2.4）
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k identity
-w /etc/sudoers.d/ -p wa -k identity

# 登录和注销（PCI-DSS 10.2.5）
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# 权限提升（PCI-DSS 10.2.5.b）
-w /bin/su -p x -k priv-esc
-w /usr/bin/sudo -p x -k priv-esc
-w /etc/sudoers -p wa -k priv-esc

# 网络配置变更
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network-change
-w /etc/hosts -p wa -k network-change
-w /etc/resolv.conf -p wa -k network-change

# 系统时间（PCI-DSS 10.6）
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# Unbound DNS 配置变更（自定义）
-w /etc/unbound/ -p wa -k dns-config
-w /var/cache/unbound/ -p wa -k dns-data
-w /var/log/unbound/ -p r -k dns-logs

# SSH 配置
-w /etc/ssh/sshd_config -p wa -k sshd-config

# 内核模块（CIS）
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# 挂载操作
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=-1 -k mounts

# 文件删除（PCI-DSS 10.2.7）
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k delete

# 权限修改
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=-1 -k perm-mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=-1 -k perm-mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -F auid>=1000 -F auid!=-1 -k perm-mod
-a always,exit -F arch=b64 -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=-1 -k perm-mod

# 用户和组管理（PCI-DSS 10.2.5）
-a always,exit -F arch=b64 -S setuid -S setreuid -S setresuid -k setuid
-a always,exit -F arch=b64 -S setgid -S setregid -S setresgid -k setgid

# 不成功的文件访问（PCI-DSS 10.2.4）
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=-1 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=-1 -k access

# 锁定审计规则（防篡改，PCI-DSS 10.5）
-e 2
EOF

# 加载规则
service auditd restart
auditctl -l | head -30

# 配置审计日志轮转
cat > /etc/audit/auditd.conf << 'EOF'
log_file = /var/log/audit/audit.log
log_format = RAW
log_group = adm
priority_boost = 4
flush = INCREMENTAL_ASYNC
freq = 50
max_log_file = 50
num_logs = 12
space_left = 100
space_left_action = SYSLOG
admin_space_left = 50
admin_space_left_action = SUSPEND
disk_full_action = SUSPEND
disk_error_action = SYSLOG
tcp_listen_queue = 5
tcp_max_per_addr = 1
tcp_client_max_idle = 0
enable_krb5 = no
krb5_principal = auditd
distribute_network = no
EOF

systemctl restart auditd
```

---

## 5. PCI-DSS 合规配置

### 5.1 日志集中管理（PCI-DSS 10.5）

```bash
# 配置 rsyslog 集中日志
cat > /etc/rsyslog.d/50-pci-dns.conf << 'EOF'
# PCI-DSS 10.2 - 审计事件类型
# DNS 相关日志
if $programname == 'unbound' then /var/log/dns/unbound-security.log
& stop

# 认证日志
auth,authpriv.*    /var/log/auth.log

# 内核日志
kern.*             /var/log/kern.log
EOF

mkdir -p /var/log/dns
chown syslog:adm /var/log/dns
chmod 750 /var/log/dns

systemctl restart rsyslog
```

### 5.2 日志保留策略（PCI-DSS 10.7：最少 12 个月）

```bash
# 配置日志轮转
cat > /etc/logrotate.d/unbound-pci << 'EOF'
/var/log/unbound/*.log {
    daily
    rotate 366
    compress
    delaycompress
    missingok
    notifempty
    create 640 unbound adm
    sharedscripts
    postrotate
        /bin/kill -HUP $(cat /run/unbound.pid 2>/dev/null) 2>/dev/null || true
    endscript
}

/var/log/dns/*.log {
    daily
    rotate 366
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog adm
}
EOF

# 确保审计日志保留 1 年
cat > /etc/logrotate.d/audit-pci << 'EOF'
/var/log/audit/audit.log {
    monthly
    rotate 13
    compress
    delaycompress
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        /sbin/service auditd condrestart 2>/dev/null || true
    endscript
}
EOF
```

### 5.3 文件完整性监控 AIDE（PCI-DSS 11.5）

```bash
# 配置 AIDE
cat > /etc/aide/aide.conf << 'EOF'
# AIDE 配置 - PCI-DSS 文件完整性监控
database=file:/var/lib/aide/aide.db
database_out=file:/var/lib/aide/aide.db.new
gzip_dbout=yes
verbose=5

# 报告
report_url=file:/var/log/aide/aide.log
report_url=syslog:LOG_AUTH

# 规则定义
PERMS = p+u+g+acl+selinux
LOG = p+u+g+n+S
LSPP = p+u+g+n+acl+selinux+sha256

# 监控路径
# Unbound 配置（任何变更必须报警）
/etc/unbound LSPP
/var/cache/unbound PERMS

# 系统二进制
/bin LSPP
/sbin LSPP
/usr/bin LSPP
/usr/sbin LSPP
/usr/lib LSPP

# 系统配置
/etc/ssh LSPP
/etc/pam.d LSPP
/etc/sudoers LSPP
/etc/security LSPP
/etc/audit LSPP

# 排除经常变化的文件
!/var/log
!/var/cache
!/proc
!/sys
!/run
!/tmp
!/dev
EOF

mkdir -p /var/log/aide

# 初始化 AIDE 数据库（首次运行需要时间）
echo "正在初始化 AIDE 数据库（需要几分钟）..."
aide --config=/etc/aide/aide.conf --init

# 复制数据库
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# 创建每日检查 cron
cat > /etc/cron.daily/aide-check << 'EOF'
#!/bin/bash
# PCI-DSS 11.5 - 每日文件完整性检查
/usr/bin/aide --config=/etc/aide/aide.conf --check \
  --report-url=file:/var/log/aide/daily-$(date +%Y%m%d).log \
  2>&1

# 如果检测到变更，发送告警
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    logger -t aide-pci "ALERT: File integrity changes detected! Exit code: $EXIT_CODE"
fi
EOF
chmod +x /etc/cron.daily/aide-check
```

### 5.4 Fail2ban 配置（PCI-DSS 6.4 + 防暴力破解）

```bash
# 配置 Fail2ban
cat > /etc/fail2ban/jail.d/dns-server.conf << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport
backend = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 86400

[sshd-ddos]
enabled  = true
port     = ssh
filter   = sshd-ddos
logpath  = /var/log/auth.log
maxretry = 6
bantime  = 86400

[dns-flood]
enabled  = true
filter   = dns-flood
logpath  = /var/log/unbound/unbound.log
maxretry = 100
findtime = 60
bantime  = 3600
port     = 53
protocol = udp
EOF

# DNS 洪水攻击过滤规则
cat > /etc/fail2ban/filter.d/dns-flood.conf << 'EOF'
[Definition]
# 检测 DNS 查询异常（unbound 日志格式）
failregex = .*\[<HOST>#\d+\].*REFUSED.*
            .*info: <HOST>.*query\[.*\].*
            .*\[<HOST>#.*\] error.*
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban
fail2ban-client status
```

---

## 6. UFW 防火墙规则集成

### 6.1 完整 UFW 规则配置

```bash
# 重置 UFW（小心！会断开连接，确保有控制台访问）
# ufw --force reset

# 设置默认策略（CIS 要求白名单模式）
ufw default deny incoming
ufw default deny outgoing
ufw default deny routed

# ===== 出站规则（DNS 服务器需要的出站连接）=====

# SSH 出站（管理）
ufw allow out 22/tcp comment 'SSH outbound'

# DNS 查询出站（Unbound 递归查询上游）
ufw allow out 53/tcp comment 'DNS TCP outbound recursive'
ufw allow out 53/udp comment 'DNS UDP outbound recursive'

# DNS-over-TLS 出站（如果转发到上游 DoT）
ufw allow out 853/tcp comment 'DNS-over-TLS outbound'

# NTP 时间同步出站
ufw allow out 123/udp comment 'NTP outbound'

# APT 更新出站（HTTPS 仅到 Azure/Debian 仓库）
ufw allow out 80/tcp comment 'HTTP APT update'
ufw allow out 443/tcp comment 'HTTPS APT update'

# ICMP 出站（网络诊断）
ufw allow out proto icmp comment 'ICMP outbound'

# ===== 入站规则 =====

# SSH（限制来源 IP，请替换为你的管理 IP）
# ufw allow from YOUR_ADMIN_IP to any port 22 proto tcp comment 'SSH management'
# 如果没有固定 IP，临时开放：
ufw allow in 22/tcp comment 'SSH inbound'

# DNS 入站（UDP，主要协议）
# 【重要】请替换 YOUR_CLIENT_IP 为青岛客户端实际 IP
ufw allow in 53/udp comment 'DNS UDP inbound'
ufw allow in 53/tcp comment 'DNS TCP inbound'

# DNS-over-TLS（加密 DNS，第 8 节配置后启用）
# ufw allow in 853/tcp comment 'DNS-over-TLS inbound'

# Nginx HTTP/HTTPS（如果本机跑 Web 服务）
ufw allow in 80/tcp comment 'Nginx HTTP'
ufw allow in 443/tcp comment 'Nginx HTTPS'

# ===== 限速规则（防 DDoS）=====
ufw limit in 22/tcp comment 'SSH rate limit'

# ===== ICMP 控制（允许 ping，便于监控）=====
# 在 /etc/ufw/before.rules 中已默认允许 ICMP echo

# 启用 UFW
ufw --force enable
ufw status verbose
```

### 6.2 UFW before.rules 高级规则（DNS 防放大攻击）

```bash
# 备份原始规则
cp /etc/ufw/before.rules /etc/ufw/before.rules.bak

# 在 COMMIT 之前插入 DNS 防护规则
cat >> /etc/ufw/before.rules << 'EOF'

# ============================================================
# DNS 防放大攻击规则（PCI-DSS 6.4 防护）
# ============================================================

# 限制单 IP 每秒 DNS 查询速率（防止 UDP 洪水）
-A ufw-before-input -p udp --dport 53 -m recent --name dns_limit --set
-A ufw-before-input -p udp --dport 53 -m recent --name dns_limit --update --seconds 1 --hitcount 30 -j DROP

# 限制 TCP DNS（防止连接耗尽）
-A ufw-before-input -p tcp --dport 53 -m connlimit --connlimit-above 10 --connlimit-mask 32 -j REJECT

# 阻止 DNS 响应反射（REFUSE 来自 53 端口的入站 UDP，防反射）
-A ufw-before-input -p udp --sport 53 -m state --state INVALID -j DROP

EOF

# 重载 UFW
ufw reload
```

### 6.3 自定义 UFW 客户端 IP 管理脚本

```bash
cat > /usr/local/sbin/dns-allow-client.sh << 'SCRIPT'
#!/bin/bash
# 管理允许访问 DNS 的客户端 IP（PCI-DSS 最小权限）
# 用法：dns-allow-client.sh add 1.2.3.4
#        dns-allow-client.sh remove 1.2.3.4
#        dns-allow-client.sh list

ACTION=$1
CLIENT_IP=$2

case $ACTION in
    add)
        if [[ -z "$CLIENT_IP" ]]; then echo "Usage: $0 add <IP>"; exit 1; fi
        ufw allow from $CLIENT_IP to any port 53 proto udp comment "DNS client: $CLIENT_IP"
        ufw allow from $CLIENT_IP to any port 53 proto tcp comment "DNS client: $CLIENT_IP"
        # 同步更新 Unbound 访问控制
        echo "    access-control: $CLIENT_IP/32 allow" >> /etc/unbound/conf.d/acl.conf
        unbound-control reload
        echo "[+] 已允许 $CLIENT_IP 访问 DNS"
        logger -t dns-acl "Added DNS client: $CLIENT_IP"
        ;;
    remove)
        if [[ -z "$CLIENT_IP" ]]; then echo "Usage: $0 remove <IP>"; exit 1; fi
        ufw delete allow from $CLIENT_IP to any port 53 proto udp 2>/dev/null
        ufw delete allow from $CLIENT_IP to any port 53 proto tcp 2>/dev/null
        sed -i "/$CLIENT_IP/d" /etc/unbound/conf.d/acl.conf
        unbound-control reload
        echo "[-] 已移除 $CLIENT_IP 的 DNS 访问"
        logger -t dns-acl "Removed DNS client: $CLIENT_IP"
        ;;
    list)
        echo "=== 当前允许的 DNS 客户端 ==="
        ufw status | grep "53 "
        echo ""
        echo "=== Unbound ACL ==="
        cat /etc/unbound/conf.d/acl.conf 2>/dev/null || echo "(空)"
        ;;
    *)
        echo "用法: $0 {add|remove|list} [IP]"
        exit 1
        ;;
esac
SCRIPT
chmod 700 /usr/local/sbin/dns-allow-client.sh
```

---

## 7. DNSSEC 验证配置

```bash
# 测试 DNSSEC 验证功能
dig +dnssec google.com @127.0.0.1

# 验证 AD 标志（Authenticated Data）= DNSSEC 验证通过
# 应该看到：flags: qr rd ra ad

# 测试 DNSSEC 失败场景（应返回 SERVFAIL）
dig sigfail.verteiltesysteme.net @127.0.0.1

# 测试有效 DNSSEC 域名
dig sigok.verteiltesysteme.net @127.0.0.1

# 查看根信任锚状态
unbound-anchor -a /var/cache/unbound/root.key -v

# 手动检查 DNSSEC 链
unbound-host -D -r /var/cache/unbound/root.hints google.com

# 定期更新根信任锚（加入 cron）
cat > /etc/cron.weekly/update-root-hints << 'EOF'
#!/bin/bash
# 更新根服务器列表和 DNSSEC 信任锚
curl -sS https://www.internic.net/domain/named.cache \
  -o /var/cache/unbound/root.hints.new && \
  mv /var/cache/unbound/root.hints.new /var/cache/unbound/root.hints && \
  chown unbound:unbound /var/cache/unbound/root.hints

unbound-anchor -a /var/cache/unbound/root.key -v

unbound-control reload
logger -t unbound "Root hints and DNSSEC anchor updated"
EOF
chmod +x /etc/cron.weekly/update-root-hints
```

---

## 8. DNS-over-TLS 加密传输

> **为什么需要 DoT：**
> 青岛→日本途径多个网络节点，明文 DNS 查询可能被监控或篡改。
> DNS-over-TLS（端口 853）提供传输加密，符合 PCI-DSS 4.0 数据传输加密要求。

### 8.1 申请 TLS 证书

```bash
# 安装 Certbot（Let's Encrypt）
apt install -y certbot

# 方案A：如果有域名（推荐）
# certbot certonly --standalone -d your-dns.yourdomain.com \
#   --email admin@yourdomain.com --agree-tos --no-eff-email

# 方案B：自签证书（内部使用）
mkdir -p /etc/unbound/tls

# 生成 CA 私钥和证书
openssl genrsa -out /etc/unbound/tls/ca.key 4096
openssl req -x509 -new -nodes \
  -key /etc/unbound/tls/ca.key \
  -sha384 -days 3650 \
  -out /etc/unbound/tls/ca.crt \
  -subj "/C=JP/ST=Tokyo/O=DNS-Server/CN=Internal-DNS-CA"

# 生成服务器密钥和 CSR
openssl genrsa -out /etc/unbound/tls/server.key 4096
openssl req -new \
  -key /etc/unbound/tls/server.key \
  -out /etc/unbound/tls/server.csr \
  -subj "/C=JP/ST=Tokyo/O=DNS-Server/CN=dns.yourdomain.com"

# 签署服务器证书（包含 SAN）
cat > /tmp/dns-ext.cnf << EOF
[v3_req]
subjectAltName = @alt_names
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = dns.yourdomain.com
IP.1 = $(curl -s ifconfig.me)
EOF

openssl x509 -req \
  -in /etc/unbound/tls/server.csr \
  -CA /etc/unbound/tls/ca.crt \
  -CAkey /etc/unbound/tls/ca.key \
  -CAcreateserial \
  -out /etc/unbound/tls/server.crt \
  -days 365 -sha384 \
  -extfile /tmp/dns-ext.cnf \
  -extensions v3_req

# 权限设置
chown -R unbound:unbound /etc/unbound/tls/
chmod 600 /etc/unbound/tls/*.key
chmod 644 /etc/unbound/tls/*.crt
```

### 8.2 Unbound DoT 配置

```bash
# 添加 DoT 配置
cat > /etc/unbound/conf.d/dot.conf << 'EOF'
server:
    # DNS-over-TLS 监听端口
    interface: 0.0.0.0@853
    interface: ::0@853
    
    # TLS 证书（使用自签或 Let's Encrypt）
    tls-service-key: "/etc/unbound/tls/server.key"
    tls-service-pem: "/etc/unbound/tls/server.crt"
    
    # TLS 1.2 最低版本（PCI-DSS 4.0 禁止 TLS 1.0/1.1）
    tls-min-version: TLSv1_2
    
    # 优先 TLS 1.3
    tls-ciphers: "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
    
    # 允许 DoT 端口（853）来自客户端
    # 注意：UFW 中需要开放 853 端口
EOF

# 验证配置
unbound-checkconf

# 在 UFW 中开放 853 端口（仅允许特定客户端 IP）
# ufw allow from YOUR_CLIENT_IP to any port 853 proto tcp comment 'DNS-over-TLS'
ufw allow in 853/tcp comment 'DNS-over-TLS inbound'

# 重载 Unbound
unbound-control reload

# 测试 DoT（在客户端使用 kdig 或 stubby）
# kdig -d @SERVER_IP +tls-ca=/path/to/ca.crt example.com
```

### 8.3 客户端配置（中国/青岛端）

```bash
# 在客户端安装 Stubby（DoT 客户端）
# apt install stubby  # Debian/Ubuntu

# Stubby 配置（/etc/stubby/stubby.yml）
cat << 'EOF'
# Stubby 客户端配置（在青岛客户端运行）
resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
  - GETDNS_TRANSPORT_TLS
tls_authentication: GETDNS_AUTHENTICATION_REQUIRED
tls_query_padding_blocksize: 128
edns_client_subnet_private: 1
idle_timeout: 10000
listen_addresses:
  - 127.0.0.1@53

upstream_recursive_servers:
  - address_data: YOUR_AZURE_JAPAN_IP
    tls_port: 853
    tls_auth_name: "dns.yourdomain.com"
    # 自签证书的 CA
    tls_ca_file: "/path/to/ca.crt"
EOF
```

---

## 9. 缓存与性能极限调优

### 9.1 Unbound 缓存暖机脚本

```bash
# 创建缓存预热脚本（减少冷启动延迟）
cat > /usr/local/sbin/dns-cache-warmup.sh << 'SCRIPT'
#!/bin/bash
# DNS 缓存预热脚本 - 针对中国常用域名
# 运行在 Unbound 启动后

DNS_SERVER="127.0.0.1"
LOG="/var/log/unbound/warmup.log"

echo "[$(date)] 开始 DNS 缓存预热..." | tee -a $LOG

# 常用国际域名列表（根据实际使用调整）
DOMAINS=(
    # 常用 CDN 和基础服务
    "google.com"
    "cloudflare.com"
    "github.com"
    "amazonaws.com"
    "azure.com"
    "microsoft.com"
    "apple.com"
    "facebook.com"
    "twitter.com"
    "youtube.com"
    # 常用 DNS 和技术
    "1.1.1.1.in-addr.arpa"
    "8.8.8.8.in-addr.arpa"
    # 安全和证书
    "ocsp.digicert.com"
    "ocsp.globalsign.com"
    "crl.microsoft.com"
)

SUCCESS=0
FAIL=0

for domain in "${DOMAINS[@]}"; do
    result=$(dig +short +timeout=5 @$DNS_SERVER $domain 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        ((SUCCESS++))
    else
        ((FAIL++))
        echo "[WARN] 预热失败: $domain" >> $LOG
    fi
    sleep 0.05  # 防止过快查询
done

echo "[$(date)] 预热完成: 成功=$SUCCESS 失败=$FAIL" | tee -a $LOG
SCRIPT
chmod +x /usr/local/sbin/dns-cache-warmup.sh

# 加入 Unbound 服务启动后触发
cat > /etc/systemd/system/dns-warmup.service << 'EOF'
[Unit]
Description=DNS Cache Warmup
After=unbound.service
Requires=unbound.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/local/sbin/dns-cache-warmup.sh
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable dns-warmup
```

### 9.2 Unbound 性能分析配置

```bash
# 启用统计信息收集
cat >> /etc/unbound/conf.d/stats.conf << 'EOF'
server:
    # 统计信息
    statistics-interval: 3600
    statistics-cumulative: yes
    extended-statistics: yes
EOF

# 查看实时统计
unbound-control stats_noreset | grep -E "total|cache|num"
```

### 9.3 系统性能基准测试

```bash
# 安装测试工具
apt install -y dnsperf

# 创建测试域名列表
cat > /tmp/dns-perf-data.txt << 'EOF'
google.com A
github.com A
cloudflare.com A
amazon.com A
microsoft.com A
apple.com A
facebook.com A
twitter.com A
youtube.com A
netflix.com A
EOF

# 运行性能测试（本地）
dnsperf -s 127.0.0.1 -d /tmp/dns-perf-data.txt \
  -l 30 -c 10 -Q 1000 2>&1 | tail -20

# 查看缓存命中率
echo "=== Unbound 缓存统计 ==="
unbound-control stats_noreset | grep -E "cache|total"
```

### 9.4 网络延迟监控

```bash
# 创建延迟监控脚本
cat > /usr/local/sbin/dns-latency-check.sh << 'SCRIPT'
#!/bin/bash
# DNS 响应延迟检查脚本（针对青岛→日本场景）

SERVER="127.0.0.1"
DOMAINS=("google.com" "github.com" "cloudflare.com")
LOG="/var/log/unbound/latency.log"

echo "=== DNS 延迟报告 $(date) ===" | tee -a $LOG

for domain in "${DOMAINS[@]}"; do
    # 首次查询（冷缓存）
    TIME_COLD=$( { time dig +short @$SERVER $domain > /dev/null; } 2>&1 | grep real | awk '{print $2}')
    # 第二次查询（热缓存）  
    TIME_HOT=$( { time dig +short @$SERVER $domain > /dev/null; } 2>&1 | grep real | awk '{print $2}')
    
    echo "$domain | 冷缓存: $TIME_COLD | 热缓存: $TIME_HOT" | tee -a $LOG
done

# 上游解析延迟（递归查询到根服务器）
echo "" | tee -a $LOG
echo "上游递归测试（uncached）:" | tee -a $LOG
dig +stats @$SERVER $(date +%s).uncached-test.com 2>&1 | grep "Query time" | tee -a $LOG

SCRIPT
chmod +x /usr/local/sbin/dns-latency-check.sh

# 加入 cron 定期检查
echo "0 * * * * root /usr/local/sbin/dns-latency-check.sh" > /etc/cron.d/dns-latency
```

---

## 10. 监控与日志审计

### 10.1 Systemd 服务加固

```bash
# 创建 Unbound 服务 Override（安全加固）
mkdir -p /etc/systemd/system/unbound.service.d/

cat > /etc/systemd/system/unbound.service.d/override.conf << 'EOF'
[Service]
# 进程限制
LimitNOFILE=65536
LimitNPROC=512

# 安全加固（systemd 沙箱）
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/unbound /var/cache/unbound /run
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @obsolete
SystemCallArchitectures=native

# 重启策略（保证高可用）
Restart=always
RestartSec=5s
StartLimitIntervalSec=300
StartLimitBurst=10

# 资源限制（1GB 内存保护）
MemoryMax=256M
MemoryHigh=200M
CPUQuota=80%
EOF

systemctl daemon-reload
systemctl restart unbound
```

### 10.2 实时监控脚本

```bash
cat > /usr/local/sbin/dns-monitor.sh << 'SCRIPT'
#!/bin/bash
# DNS 服务器实时状态监控

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo "======================================================"
echo "  Unbound DNS 服务器状态监控 - $(date)"
echo "  Azure Japan East | Standard_B2ats_v2"
echo "======================================================"

# 服务状态
STATUS=$(systemctl is-active unbound)
if [ "$STATUS" = "active" ]; then
    echo -e "服务状态: ${GREEN}运行中${NC}"
else
    echo -e "服务状态: ${RED}停止${NC}"
fi

# 内存使用
echo ""
echo "--- 系统资源 ---"
free -h | grep -E "Mem|Swap"
echo "CPU 使用: $(top -bn1 | grep unbound | awk '{print $9}')%"

# DNS 统计
echo ""
echo "--- DNS 统计（过去 1 小时）---"
unbound-control stats_noreset 2>/dev/null | \
  grep -E "total\.|cache\." | \
  awk -F= '{printf "  %-40s %s\n", $1, $2}'

# 连接状态
echo ""
echo "--- 网络连接 ---"
echo "DNS UDP 监听: $(ss -uln | grep ':53 ' | wc -l) 个"
echo "DNS TCP 连接: $(ss -tn | grep ':53 ' | wc -l) 个"
echo "当前 DNS 查询: $(ss -uln sport = :53 | wc -l) 个"

# 最近错误日志
echo ""
echo "--- 最近错误（最后 5 条）---"
tail -5 /var/log/unbound/unbound.log 2>/dev/null | grep -i "error\|warn\|fail"

# UFW 状态
echo ""
echo "--- 防火墙状态 ---"
ufw status | head -5

SCRIPT
chmod +x /usr/local/sbin/dns-monitor.sh

# 创建别名
echo "alias dns-status='/usr/local/sbin/dns-monitor.sh'" >> /root/.bashrc
```

### 10.3 告警脚本

```bash
cat > /usr/local/sbin/dns-alert.sh << 'SCRIPT'
#!/bin/bash
# DNS 服务健康检查和告警
# 建议配置邮件或其他告警方式

ALERT_LOG="/var/log/unbound/alerts.log"
TEST_DOMAIN="google.com"
MAX_LATENCY_MS=500  # 最大可接受延迟（毫秒）

alert() {
    local msg="[ALERT] $(date) - $1"
    echo "$msg" >> $ALERT_LOG
    logger -t dns-alert "$msg"
    # 可以添加邮件告警：echo "$msg" | mail -s "DNS Alert" admin@yourdomain.com
}

# 检查 Unbound 进程
if ! systemctl is-active --quiet unbound; then
    alert "Unbound DNS 服务停止！正在尝试重启..."
    systemctl restart unbound
    sleep 3
    if ! systemctl is-active --quiet unbound; then
        alert "Unbound 重启失败！需要人工介入"
    fi
fi

# 检查 DNS 响应
RESULT=$(dig +time=5 +tries=2 +short @127.0.0.1 $TEST_DOMAIN 2>/dev/null)
if [ -z "$RESULT" ]; then
    alert "DNS 查询失败：$TEST_DOMAIN 无响应"
fi

# 检查响应延迟
LATENCY=$(dig +stats @127.0.0.1 $TEST_DOMAIN 2>&1 | grep "Query time" | awk '{print $4}')
if [ -n "$LATENCY" ] && [ "$LATENCY" -gt "$MAX_LATENCY_MS" 2>/dev/null ]; then
    alert "DNS 响应延迟过高：${LATENCY}ms (阈值: ${MAX_LATENCY_MS}ms)"
fi

# 检查内存使用
MEM_USED_PCT=$(free | awk '/Mem:/ {printf "%d", $3/$2 * 100}')
if [ "$MEM_USED_PCT" -gt 85 ]; then
    alert "内存使用率过高：${MEM_USED_PCT}%（1GB 主机）"
fi

# 检查磁盘空间（日志和缓存）
DISK_USED_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USED_PCT" -gt 80 ]; then
    alert "磁盘使用率过高：${DISK_USED_PCT}%"
fi

SCRIPT
chmod +x /usr/local/sbin/dns-alert.sh

# 每 5 分钟运行一次
echo "*/5 * * * * root /usr/local/sbin/dns-alert.sh" > /etc/cron.d/dns-alert
```

---

## 11. 自动化维护脚本

### 11.1 系统定期维护

```bash
cat > /usr/local/sbin/dns-maintenance.sh << 'SCRIPT'
#!/bin/bash
# DNS 服务器定期维护脚本（建议每周日凌晨运行）

LOG="/var/log/unbound/maintenance.log"
echo "=== 维护开始: $(date) ===" >> $LOG

# 更新根服务器列表
echo "更新 Root Hints..." >> $LOG
curl -sS https://www.internic.net/domain/named.cache \
  -o /var/cache/unbound/root.hints.new && \
  mv /var/cache/unbound/root.hints.new /var/cache/unbound/root.hints
chown unbound:unbound /var/cache/unbound/root.hints

# 更新 DNSSEC 信任锚
echo "更新 DNSSEC 锚..." >> $LOG
unbound-anchor -a /var/cache/unbound/root.key -v >> $LOG 2>&1

# 更新系统和安全补丁（PCI-DSS 6.3.3）
echo "系统安全更新..." >> $LOG
apt update -qq && apt upgrade -y --only-upgrade 2>> $LOG

# 更新 Fail2ban 规则
fail2ban-client reload >> $LOG 2>&1

# 清理旧日志（保留 366 天符合 PCI-DSS）
find /var/log/unbound/ -name "*.gz" -mtime +366 -delete
find /var/log/aide/ -name "*.log" -mtime +366 -delete

# 重载 Unbound（不重启，保持缓存）
unbound-control reload >> $LOG 2>&1

# 运行延迟检查
/usr/local/sbin/dns-latency-check.sh >> $LOG

echo "=== 维护完成: $(date) ===" >> $LOG

SCRIPT
chmod +x /usr/local/sbin/dns-maintenance.sh

# 每周日凌晨 3 点运行
echo "0 3 * * 0 root /usr/local/sbin/dns-maintenance.sh" > /etc/cron.d/dns-maintenance
```

### 11.2 自动备份配置

```bash
cat > /usr/local/sbin/dns-backup.sh << 'SCRIPT'
#!/bin/bash
# DNS 配置备份脚本（PCI-DSS 12.10 业务连续性）

BACKUP_DIR="/var/backups/dns"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/dns-config-$DATE.tar.gz"

mkdir -p $BACKUP_DIR

# 打包关键配置文件
tar -czf $BACKUP_FILE \
    /etc/unbound/ \
    /var/cache/unbound/root.key \
    /var/cache/unbound/root.hints \
    /etc/ufw/ \
    /etc/fail2ban/ \
    /etc/audit/rules.d/ \
    2>/dev/null

# 加密备份文件（PCI-DSS 3.4 静态数据加密）
# openssl enc -aes-256-gcm -pbkdf2 -in $BACKUP_FILE -out ${BACKUP_FILE}.enc \
#   -pass file:/etc/unbound/backup.key && rm $BACKUP_FILE

# 设置权限
chmod 600 $BACKUP_FILE
chown root:root $BACKUP_FILE

# 保留 30 天备份
find $BACKUP_DIR -name "dns-config-*.tar.gz" -mtime +30 -delete

echo "备份完成: $BACKUP_FILE ($(du -sh $BACKUP_FILE | cut -f1))"
logger -t dns-backup "Configuration backup: $BACKUP_FILE"

SCRIPT
chmod +x /usr/local/sbin/dns-backup.sh

# 每日凌晨 2 点备份
echo "0 2 * * * root /usr/local/sbin/dns-backup.sh" > /etc/cron.d/dns-backup
```

---

## 12. 验证与测试完整流程

### 12.1 功能测试

```bash
echo "====== Unbound DNS 功能验证 ======"

# 1. 基本解析测试
echo "[1] 基本 A 记录查询:"
dig +short google.com @127.0.0.1

# 2. DNSSEC 验证（应看到 ad 标志）
echo "[2] DNSSEC 验证 (应有 ad 标志):"
dig +dnssec google.com @127.0.0.1 | grep -E "flags:|status:"

# 3. NXDOMAIN 测试
echo "[3] NXDOMAIN 测试:"
dig +short nonexistent-$(date +%s).example.com @127.0.0.1; echo "状态: $?"

# 4. DNSSEC 失败测试（应返回 SERVFAIL）
echo "[4] DNSSEC 失败域名（应返回 SERVFAIL）:"
dig sigfail.verteiltesysteme.net @127.0.0.1 | grep -E "status:|ANSWER"

# 5. 缓存测试
echo "[5] 缓存性能测试（第2次应更快）:"
for i in 1 2 3; do
    TIME=$(dig +stats cloudflare.com @127.0.0.1 2>&1 | grep "Query time" | awk '{print $4}')
    echo "  查询 $i: ${TIME}ms"
done

# 6. IPv6 解析
echo "[6] IPv6 解析测试:"
dig +short AAAA google.com @127.0.0.1

# 7. 反向解析
echo "[7] 反向解析测试:"
dig +short -x 8.8.8.8 @127.0.0.1

# 8. 拒绝私有地址（防重绑定）
echo "[8] 私有地址拒绝测试（应失败）:"
dig +short 10.0.0.1.in-addr.arpa @127.0.0.1 || echo "已正确拒绝私有地址"

# 9. unbound-control 连接测试
echo "[9] 远程控制接口测试:"
unbound-control status | head -5

# 10. 服务版本隐藏验证
echo "[10] 版本信息隐藏测试（应不显示 Unbound 版本）:"
dig chaos TXT version.bind @127.0.0.1 +short
```

### 12.2 安全扫描

```bash
# DNS 安全扫描
echo "====== 安全配置验证 ======"

# 检查版本隐藏
echo "[安全1] 版本查询（应为空）:"
dig +short chaos TXT version.bind @127.0.0.1
dig +short chaos TXT version.server @127.0.0.1

# 检查 ANY 查询拒绝
echo "[安全2] ANY 查询（应被拒绝）:"
dig ANY google.com @127.0.0.1 | grep -E "status:|QUESTION"

# 检查访问控制
echo "[安全3] UFW 规则列表:"
ufw status numbered | head -20

# 检查 CIS 内核参数
echo "[安全4] 关键内核参数:"
for param in \
  net.ipv4.ip_forward \
  net.ipv4.conf.all.accept_redirects \
  net.ipv4.tcp_syncookies \
  kernel.randomize_va_space \
  kernel.dmesg_restrict; do
    VAL=$(sysctl -n $param 2>/dev/null)
    echo "  $param = $VAL"
done

# 检查 DNSSEC
echo "[安全5] DNSSEC 信任锚状态:"
unbound-anchor -a /var/cache/unbound/root.key -v 2>&1 | tail -3

# rkhunter 快速扫描
echo "[安全6] rkhunter 快速检查:"
rkhunter --check --sk --rwo 2>/dev/null | tail -10
```

### 12.3 从青岛客户端测试

```bash
# 在青岛客户端运行以下命令（将 AZURE_IP 替换为实际 IP）
AZURE_IP="YOUR_AZURE_JAPAN_IP"

echo "=== 从客户端测试 Azure Japan DNS ==="

# 基本响应测试
dig google.com @$AZURE_IP +time=10

# 延迟测试（取 10 次平均）
echo "延迟统计（10次查询）:"
for i in $(seq 1 10); do
    dig +stats google.com @$AZURE_IP 2>&1 | grep "Query time"
done | awk '{sum += $4; count++} END {printf "平均延迟: %.1f ms\n", sum/count}'

# DoT 测试（需要 kdig 工具：apt install knot-dnsutils）
# kdig -d @$AZURE_IP +tls google.com

# 批量域名解析速度
echo "批量解析测试:"
time for domain in google.com github.com cloudflare.com amazon.com microsoft.com; do
    dig +short @$AZURE_IP $domain > /dev/null
done
```

### 12.4 PCI-DSS 合规验证清单

```bash
cat << 'EOF'
====================================================
PCI-DSS v4.0 合规验证清单 - DNS 服务器
====================================================

要求 1 - 网络安全控制
[✓] 1.3.2  UFW 默认拒绝，白名单规则
[✓] 1.3.3  DNS 放大攻击防护规则（UFW + Unbound deny-any）
[ ] 1.4.1  请确认 Azure NSG 仅允许必要端口（53/853/22）

要求 2 - 安全默认配置  
[✓] 2.2.1  系统已更新至最新补丁
[✓] 2.2.7  SSH 加密套件仅允许强算法
[✓] 2.3.1  不需要的服务/模块已禁用

要求 6 - 安全软件开发
[✓] 6.3.3  自动安全更新已配置
[✓] 6.4.1  防暴力攻击（Fail2ban）已配置

要求 7 - 访问控制
[✓] 7.2.1  DNS 访问仅限授权客户端 IP
[✓] 7.3.1  Unbound 以非 root 用户运行

要求 8 - 用户识别和身份验证
[✓] 8.3.4  账户锁定（6次失败/900秒）
[✓] 8.3.6  密码最低14位，含复杂度要求
[ ] 8.4.2  请为管理账户配置 MFA

要求 9 - 物理安全
[ ] 9.2    Azure 数据中心托管，查阅 Azure 合规文档

要求 10 - 日志和监控
[✓] 10.2.1 审计日志已配置（auditd）
[✓] 10.3.1 日志防篡改（auditd -e 2）
[✓] 10.5.1 时间同步（chrony）
[✓] 10.7.1 日志保留 366 天（logrotate）

要求 11 - 安全测试
[✓] 11.3.1 Fail2ban 入侵防御
[✓] 11.5.1 AIDE 文件完整性监控

要求 12 - 策略和程序
[✓] 12.10.1 自动备份脚本配置

====================================================
[ ] = 需要手动验证  [✓] = 已自动配置
====================================================
EOF
```

---

## 13. 故障排查速查表

### 快速诊断命令

```bash
# =========================================
# 一键状态检查
# =========================================

echo "=== 服务状态 ==="
systemctl status unbound --no-pager -l | head -20

echo "=== 监听端口 ==="
ss -tulnp | grep -E "unbound|:53|:853"

echo "=== 最近日志 ==="
tail -30 /var/log/unbound/unbound.log

echo "=== DNS 统计 ==="
unbound-control stats_noreset | grep -E "total|cache|num"

echo "=== 防火墙规则 ==="
ufw status verbose

echo "=== 内存使用 ==="
free -h && ps aux | grep unbound | grep -v grep

# =========================================
# 常见问题排查
# =========================================

# 问题1：unbound 无法启动
# journalctl -xeu unbound.service --no-pager | tail -50
# unbound -d -vvv 2>&1 | head -100  # 前台调试模式

# 问题2：DNS 解析缓慢（超过 500ms）
# unbound-control stats | grep "query.latency"
# dig +trace google.com @127.0.0.1  # 查看递归路径

# 问题3：DNSSEC 验证失败
# unbound-control flush_zone . && unbound-control reload  # 清缓存重试
# dig +dnssec +cd google.com @127.0.0.1  # 跳过 DNSSEC 验证测试

# 问题4：访问控制拒绝客户端
# /usr/local/sbin/dns-allow-client.sh add CLIENT_IP

# 问题5：内存不足（1GB 主机）
# unbound-control stats | grep "mem.cache"
# 如果超过 200MB，减小配置中的 rrset-cache-size 和 msg-cache-size

# 问题6：BBR 未启用
# 重新检查：sysctl net.ipv4.tcp_congestion_control
# 手动加载：modprobe tcp_bbr && echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

# =========================================
# 紧急恢复命令
# =========================================

# 强制重启 Unbound
# systemctl restart unbound

# 清空 DNS 缓存（debug 用）
# unbound-control flush_all

# 重载配置（不清缓存）
# unbound-control reload

# 检查并修复 DNSSEC 锚
# unbound-anchor -a /var/cache/unbound/root.key -f -v

# 恢复默认配置（如严重损坏）
# cp /etc/unbound/unbound.conf.bak /etc/unbound/unbound.conf
# systemctl restart unbound
```

---

## 附录：配置文件汇总

```
关键文件路径速查：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/etc/unbound/unbound.conf          主配置文件
/etc/unbound/conf.d/               子配置目录
  ├── forwarders.conf               上游转发配置
  ├── dot.conf                      DNS-over-TLS 配置
  ├── stats.conf                    统计配置
  └── acl.conf                      客户端访问控制
/etc/unbound/keys/                  远程控制证书
/etc/unbound/tls/                   DoT TLS 证书
/var/cache/unbound/root.key         DNSSEC 根锚
/var/cache/unbound/root.hints       根服务器列表
/var/log/unbound/unbound.log        DNS 运行日志
/var/log/unbound/latency.log        延迟监控日志

运维命令速查：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
unbound-control status              查看状态
unbound-control stats_noreset       查看统计（不重置）
unbound-control reload              热重载配置
unbound-control flush_all           清空全部缓存
unbound-control flush google.com    清除指定域名缓存
unbound-checkconf                   验证配置语法
dns-status                          自定义监控面板（别名）
dns-allow-client.sh add IP          添加允许的客户端 IP
```

---

*最后更新: 2025 | 适用: Debian 13 · Unbound 1.19+ · Azure Japan East*
*合规: CIS Benchmark Level 2 · PCI-DSS v4.0 · Standard_B2ats_v2 优化*
