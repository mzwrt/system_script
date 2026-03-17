cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d)

cat > /etc/sysctl.d/99-b2ats-1gb-tuning.conf << 'EOF'
##################################################################
## Standard_B2ats_v2 · 1GB RAM 专项 sysctl 调优
## 原则：缓冲区保守，延迟优先，严禁内存浪费
##################################################################

# ────────────────────────────────────────────────────────────────
# ① 网络缓冲区（按 1GB 严格缩减）
# 128MB 缓冲在 1GB 机器上会挤压 DNS 缓存 → 全部缩至合理值
# ────────────────────────────────────────────────────────────────

# TCP/通用 socket 最大缓冲：16MB（原 128MB → 大幅缩减）
net.core.rmem_max                   = 16777216
net.core.wmem_max                   = 16777216
net.core.rmem_default               = 1048576
net.core.wmem_default               = 1048576

# TCP 自动调整 min/default/max
net.ipv4.tcp_rmem                   = 4096 32768 8388608
net.ipv4.tcp_wmem                   = 4096 32768 8388608

# UDP 内存页（page=4096B）min/pressure/max
# 1GB 机器：给 UDP DNS 分配约 48MB 空间
net.ipv4.udp_mem                    = 4096 8192 12288
net.ipv4.udp_rmem_min               = 4096
net.ipv4.udp_wmem_min               = 4096

# ────────────────────────────────────────────────────────────────
# ② 设备队列（1GB 下适当降低，防 OOM）
# ────────────────────────────────────────────────────────────────

net.core.netdev_max_backlog         = 16384
net.core.netdev_budget              = 300
net.core.netdev_budget_usecs        = 4000

# listen() 队列（Nginx accept）
net.core.somaxconn                  = 8192
net.ipv4.tcp_max_syn_backlog        = 8192

# RPS 流表（2 CPU × 8192 = 16384）
net.core.rps_sock_flow_entries      = 16384

# ────────────────────────────────────────────────────────────────
# ③ TCP 性能（BBR + 低延迟，适合青岛→日本 50ms 链路）
# ────────────────────────────────────────────────────────────────

# BBR 拥塞控制（不占额外内存，提升吞吐）
net.ipv4.tcp_congestion_control     = bbr
net.core.default_qdisc              = fq

# TCP Fast Open 双向（减少 1 RTT，青岛→日本 50ms 每次节省显著）
net.ipv4.tcp_fastopen               = 3

# TIME_WAIT 优化（1GB 下必须控制 socket 内存）
net.ipv4.tcp_tw_reuse               = 1
net.ipv4.tcp_fin_timeout            = 15
net.ipv4.tcp_max_tw_buckets         = 32768     # 1GB 下大幅缩减（原 200 万）

# SACK 提升丢包恢复
net.ipv4.tcp_sack                   = 1
net.ipv4.tcp_dsack                  = 1

# 空闲后不重置 cwnd（保持 BBR 状态，避免重新慢启动）
net.ipv4.tcp_slow_start_after_idle  = 0

# 窗口缩放
net.ipv4.tcp_window_scaling         = 1
net.ipv4.tcp_moderate_rcvbuf        = 1

# Keepalive（快速清理死连接，释放 1GB 宝贵内存）
net.ipv4.tcp_keepalive_time         = 120       # 比标准更激进
net.ipv4.tcp_keepalive_intvl        = 15
net.ipv4.tcp_keepalive_probes       = 3

# RFC1337（TIME_WAIT 安全）
net.ipv4.tcp_rfc1337                = 1

# 本地端口范围
net.ipv4.ip_local_port_range        = 1024 65535

# ────────────────────────────────────────────────────────────────
# ④ 文件描述符（Nginx 需要，但 1GB 下不放太大）
# ────────────────────────────────────────────────────────────────

fs.file-max                         = 262144    # 原 200 万 → 26 万
fs.nr_open                          = 262144

# ────────────────────────────────────────────────────────────────
# ⑤ 安全加固（CIS L2 + PCI-DSS，不占内存）
# ────────────────────────────────────────────────────────────────

net.ipv4.ip_forward                 = 0
net.ipv6.conf.all.forwarding        = 0

net.ipv4.conf.all.accept_source_route    = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route    = 0

net.ipv4.conf.all.accept_redirects       = 0
net.ipv4.conf.default.accept_redirects   = 0
net.ipv4.conf.all.secure_redirects       = 0
net.ipv4.conf.default.secure_redirects   = 0
net.ipv6.conf.all.accept_redirects       = 0

net.ipv4.conf.all.send_redirects         = 0
net.ipv4.conf.default.send_redirects     = 0

net.ipv4.conf.all.rp_filter              = 1
net.ipv4.conf.default.rp_filter          = 1

net.ipv4.tcp_syncookies                  = 1
net.ipv4.icmp_echo_ignore_broadcasts     = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

net.ipv4.conf.all.log_martians           = 1
net.ipv4.conf.default.log_martians       = 1

kernel.randomize_va_space                = 2
kernel.dmesg_restrict                    = 1
kernel.perf_event_paranoid               = 3
kernel.kptr_restrict                     = 2
kernel.sysrq                             = 0

fs.protected_hardlinks                   = 1
fs.protected_symlinks                    = 1
fs.protected_fifos                       = 2
fs.protected_regular                     = 2
fs.suid_dumpable                         = 0

# ────────────────────────────────────────────────────────────────
# ⑥ 内存管理（1GB 最关键：必须防止 OOM 杀掉 Unbound/Nginx）
# ────────────────────────────────────────────────────────────────

# swap 倾向：适当提高（1GB 下需要允许非热点页被换出）
# 不能设 0/5，否则内核拒绝换出任何东西反而触发 OOM
vm.swappiness                       = 20

# 文件系统缓存压力（提高，让内核更积极回收 pagecache 给应用）
vm.vfs_cache_pressure               = 150

# 脏页写回（积极写回，减少内存中脏页积压）
vm.dirty_ratio                      = 10
vm.dirty_background_ratio           = 3

# 保留最小空闲内存（约 64MB，防止 OOM 雪崩）
vm.min_free_kbytes                  = 65536

# 禁止过量提交（1GB 下 overcommit 危险）
vm.overcommit_memory                = 2
vm.overcommit_ratio                 = 80

# OOM 时优先杀分数高的非关键进程
vm.oom_kill_allocating_task         = 0

EOF

# 生效
sysctl --system 2>&1 | grep -E "^(net|vm|fs|kernel)" | tail -10
echo "✓ sysctl 已加载"

# 验证 BBR
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr || (modprobe tcp_bbr && echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf && echo "✓ BBR 模块已加载")

# fq 队列调度器
tc qdisc replace dev eth0 root fq 2>/dev/null && echo "✓ fq qdisc 已设置"
