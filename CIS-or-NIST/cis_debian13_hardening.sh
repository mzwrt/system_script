#!/bin/bash
# =============================================================================
#  CIS Debian Linux 13 Benchmark v1.0.0 完整硬化脚本
#  参考标准：CIS Debian Linux 13 Benchmark v1.0.0（2026年2月）
#  适用系统：Debian 13 (trixie)
#
#  使用方法：sudo bash cis_debian13_hardening.sh
#
#  流程：
#    Step 1 → 预审计（检查每一条是否符合 CIS 标准）
#    Step 2 → 执行修复（仅修复开关为 true 且不合规的项）
#    Step 3 → 后审计（再次验证每一条是否已合规）
#    Step 4 → 二次修正（对仍不合规项重新尝试修复）
#
#  ⚠ 强烈建议先在测试环境运行
#  ⚠ 脚本会备份关键配置文件到 /root/cis_backup_<日期>/ 目录
# =============================================================================

# =============================================================================
#  【配置开关区域】
#  true  = 启用该硬化项（若审计不合规则自动修复）
#  false = 跳过该硬化项（仅审计，不修改）
# =============================================================================

# ---- 1.1 文件系统配置 ----
ENABLE_1_1_1_1=true    # 1.1.1.1  禁用 cramfs 文件系统
ENABLE_1_1_1_2=true    # 1.1.1.2  禁用 freevxfs 文件系统
ENABLE_1_1_1_3=true    # 1.1.1.3  禁用 jffs2 文件系统
ENABLE_1_1_1_4=true    # 1.1.1.4  禁用 hfs 文件系统
ENABLE_1_1_1_5=true    # 1.1.1.5  禁用 hfsplus 文件系统
ENABLE_1_1_1_6=true    # 1.1.1.6  禁用 squashfs（使用 snap/docker 改为 false）
ENABLE_1_1_1_7=true    # 1.1.1.7  禁用 udf（需读光盘改为 false）
ENABLE_1_1_2_1=true    # 1.1.2.1  /tmp 配置为独立分区或 tmpfs
ENABLE_1_1_2_2=true    # 1.1.2.2  /tmp 挂载加 nodev 选项
ENABLE_1_1_2_3=true    # 1.1.2.3  /tmp 挂载加 nosuid 选项
ENABLE_1_1_2_4=true    # 1.1.2.4  /tmp 挂载加 noexec 选项（需在 /tmp 执行改为 false）
ENABLE_1_1_3_1=true    # 1.1.3.1  /var 挂载加 nodev 选项
ENABLE_1_1_3_2=true    # 1.1.3.2  /var 挂载加 nosuid 选项
ENABLE_1_1_4_1=true    # 1.1.4.1  /var/tmp 挂载加 nodev 选项
ENABLE_1_1_4_2=true    # 1.1.4.2  /var/tmp 挂载加 nosuid 选项
ENABLE_1_1_4_3=true    # 1.1.4.3  /var/tmp 挂载加 noexec 选项
ENABLE_1_1_5_1=true    # 1.1.5.1  /var/log 挂载加 nodev 选项
ENABLE_1_1_5_2=true    # 1.1.5.2  /var/log 挂载加 nosuid 选项
ENABLE_1_1_5_3=true    # 1.1.5.3  /var/log 挂载加 noexec 选项
ENABLE_1_1_6_1=true    # 1.1.6.1  /var/log/audit 挂载加 nodev 选项
ENABLE_1_1_6_2=true    # 1.1.6.2  /var/log/audit 挂载加 nosuid 选项
ENABLE_1_1_6_3=true    # 1.1.6.3  /var/log/audit 挂载加 noexec 选项
ENABLE_1_1_7_1=true    # 1.1.7.1  /home 挂载加 nodev 选项
ENABLE_1_1_7_2=true    # 1.1.7.2  /home 挂载加 nosuid 选项
ENABLE_1_1_8_1=true    # 1.1.8.1  /dev/shm 挂载加 nodev 选项
ENABLE_1_1_8_2=true    # 1.1.8.2  /dev/shm 挂载加 nosuid 选项
ENABLE_1_1_8_3=true    # 1.1.8.3  /dev/shm 挂载加 noexec 选项

# ---- 1.2 软件更新 ----
ENABLE_1_2_1=true      # 1.2.1  确保 apt 使用 HTTPS
ENABLE_1_2_2=true      # 1.2.2  确保 apt 源使用 GPG 签名验证

# ---- 1.3 文件完整性检查 ----
ENABLE_1_3_1=false      # 1.3.1  安装 AIDE
ENABLE_1_3_2=false      # 1.3.2  配置 AIDE 定期检查（cron）

# ---- 1.4 安全启动设置 ----
ENABLE_1_4_1=true      # 1.4.1  确保 GRUB 引导加密（需交互输入密码）
ENABLE_1_4_2=true      # 1.4.2  确保引导加载器权限（600）
ENABLE_1_4_3=true      # 1.4.3  要求单用户模式输入密码

# ---- 1.5 进程加固 ----
ENABLE_1_5_1=true      # 1.5.1  确保 core dump 受限
ENABLE_1_5_2=true      # 1.5.2  启用 XD/NX 支持（仅检查，硬件相关）
ENABLE_1_5_3=true      # 1.5.3  启用 ASLR 地址空间随机化
ENABLE_1_5_4=true      # 1.5.4  确保 ptrace 范围受限

# ---- 1.6 强制访问控制 AppArmor ----
ENABLE_1_6_1_1=true    # 1.6.1.1 安装 AppArmor
ENABLE_1_6_1_2=true    # 1.6.1.2 确保 AppArmor 在启动时启用
ENABLE_1_6_1_3=true    # 1.6.1.3 确保所有配置文件为 enforce 或 complain 模式
ENABLE_1_6_1_4=true    # 1.6.1.4 确保无进程处于 unconfined 状态

# ---- 1.7 警告横幅 ----
ENABLE_1_7_1=true      # 1.7.1  配置本地登录警告横幅 /etc/motd
ENABLE_1_7_2=true      # 1.7.2  配置远程登录警告横幅 /etc/issue.net
ENABLE_1_7_3=true      # 1.7.3  配置本地登录横幅 /etc/issue
ENABLE_1_7_4=true      # 1.7.4  确保 /etc/motd 权限正确
ENABLE_1_7_5=true      # 1.7.5  确保 /etc/issue 权限正确
ENABLE_1_7_6=true      # 1.7.6  确保 /etc/issue.net 权限正确

# ---- 2.1 禁用非必要服务 ----
ENABLE_2_1_1=true      # 2.1.1  确保 xinetd 未安装
ENABLE_2_1_2=true      # 2.1.2  确保 openbsd-inetd 未安装
ENABLE_2_2_1=true      # 2.2.1  确保时间同步已配置（chrony）
ENABLE_2_2_2=true      # 2.2.2  确保 X Window System 未安装（服务器）
ENABLE_2_2_3=true      # 2.2.3  确保 Avahi 服务未安装（如需 mDNS 改为 false）
ENABLE_2_2_4=true      # 2.2.4  确保 CUPS 未安装（如需打印改为 false）
ENABLE_2_2_5=true      # 2.2.5  确保 DHCP 服务未安装
ENABLE_2_2_6=true      # 2.2.6  确保 LDAP 服务未安装
ENABLE_2_2_7=true      # 2.2.7  确保 NFS 未安装（如需网络存储改为 false）
ENABLE_2_2_8=true      # 2.2.8  确保 DNS 服务未安装
ENABLE_2_2_9=true      # 2.2.9  确保 FTP 服务未安装
ENABLE_2_2_10=true     # 2.2.10 确保 HTTP 服务未安装（Web服务器改为 false）
ENABLE_2_2_11=true     # 2.2.11 确保 IMAP/POP3 服务未安装
ENABLE_2_2_12=true     # 2.2.12 确保 Samba 服务未安装
ENABLE_2_2_13=true     # 2.2.13 确保 HTTP 代理服务未安装
ENABLE_2_2_14=true     # 2.2.14 确保 SNMP 服务未安装
ENABLE_2_2_15=true     # 2.2.15 确保 rsync 服务未安装
ENABLE_2_2_16=true     # 2.2.16 确保 NIS 服务未安装
ENABLE_2_3_1=true      # 2.3.1  确保 NIS 客户端未安装
ENABLE_2_3_2=true      # 2.3.2  确保 rsh 客户端未安装
ENABLE_2_3_3=true      # 2.3.3  确保 talk 客户端未安装
ENABLE_2_3_4=true      # 2.3.4  确保 telnet 客户端未安装
ENABLE_2_3_5=true      # 2.3.5  确保 LDAP 客户端未安装
ENABLE_2_3_6=true      # 2.3.6  确保 RPC 客户端未安装

# ---- 3.1-3.2 网络内核参数 ----
ENABLE_3_1_1=true      # 3.1.1  禁用 IP 转发（Docker/路由器改为 false）
ENABLE_3_1_2=true      # 3.1.2  禁用发送 ICMP 重定向
ENABLE_3_2_1=true      # 3.2.1  禁用接受源路由数据包
ENABLE_3_2_2=true      # 3.2.2  禁用接受 ICMP 重定向
ENABLE_3_2_3=true      # 3.2.3  禁用接受安全 ICMP 重定向
ENABLE_3_2_4=true      # 3.2.4  记录可疑数据包
ENABLE_3_2_5=true      # 3.2.5  启用忽略广播 ICMP
ENABLE_3_2_6=true      # 3.2.6  启用忽略虚假 ICMP 错误
ENABLE_3_2_7=true      # 3.2.7  启用反向路径过滤
ENABLE_3_2_8=true      # 3.2.8  启用 TCP SYN Cookies
ENABLE_3_2_9=true      # 3.2.9  禁用 IPv6 路由广播（非路由器）

# ---- 3.3 IPv6 ----
ENABLE_3_3_1=false     # 3.3.1  禁用 IPv6（使用 IPv6 保持 false）

# ---- 3.4 不常用协议 ----
ENABLE_3_4_1=true      # 3.4.1  禁用 DCCP 协议
ENABLE_3_4_2=true      # 3.4.2  禁用 SCTP 协议
ENABLE_3_4_3=true      # 3.4.3  禁用 RDS 协议
ENABLE_3_4_4=true      # 3.4.4  禁用 TIPC 协议

# ---- 3.5 防火墙（UFW）----
ENABLE_3_5_1_1=true    # 3.5.1.1 安装 UFW
ENABLE_3_5_1_2=true    # 3.5.1.2 确保 UFW 已启用并开机自启
ENABLE_3_5_1_3=true    # 3.5.1.3 配置 UFW 基础规则（默认拒绝入站，允许出站，允许 SSH）
ENABLE_3_5_1_4=true    # 3.5.1.4 确保 UFW 拒绝所有未明确允许的入站连接
ENABLE_3_5_1_5=true    # 3.5.1.5 确保 UFW 日志记录已启用
# 如需开放额外端口，在 fix_3_5_1_3 函数中取消相应注释行

# ---- 4.1 auditd 审计 ----
ENABLE_4_1_1_1=true    # 4.1.1.1 安装 auditd
ENABLE_4_1_1_2=true    # 4.1.1.2 确保 auditd 服务已启用
ENABLE_4_1_1_3=true    # 4.1.1.3 确保审计日志不会自动删除
ENABLE_4_1_1_4=true    # 4.1.1.4 确保磁盘满时不关闭系统（改为 halt）
ENABLE_4_1_2_1=true    # 4.1.2.1 确保审计登录/注销事件
ENABLE_4_1_2_2=true    # 4.1.2.2 确保审计文件删除事件
ENABLE_4_1_2_3=true    # 4.1.2.3 确保审计 sudo 使用
ENABLE_4_1_2_4=true    # 4.1.2.4 确保审计 sudo 配置修改
ENABLE_4_1_2_5=true    # 4.1.2.5 确保审计 mount 操作
ENABLE_4_1_2_6=true    # 4.1.2.6 确保审计用户/组信息修改
ENABLE_4_1_2_7=true    # 4.1.2.7 确保审计网络环境修改
ENABLE_4_1_2_8=true    # 4.1.2.8 确保审计 MAC 策略修改
ENABLE_4_1_2_9=true    # 4.1.2.9 确保审计登录事件
ENABLE_4_1_2_10=true   # 4.1.2.10 确保审计会话启动
ENABLE_4_1_2_11=true   # 4.1.2.11 确保审计文件权限修改
ENABLE_4_1_2_12=true   # 4.1.2.12 确保审计未授权文件访问
ENABLE_4_1_2_13=true   # 4.1.2.13 确保审计 SUID/SGID 程序执行
ENABLE_4_1_2_14=true   # 4.1.2.14 确保审计内核模块加载/卸载
ENABLE_4_1_3_1=true    # 4.1.3.1  确保审计日志文件权限为 640 或更严
ENABLE_4_1_3_2=true    # 4.1.3.2  确保审计配置文件权限为 640 或更严
ENABLE_4_1_3_3=true    # 4.1.3.3  确保审计工具文件权限为 755 或更严

# ---- 4.2 日志配置 ----
ENABLE_4_2_1_1=true    # 4.2.1.1 安装 rsyslog
ENABLE_4_2_1_2=true    # 4.2.1.2 确保 rsyslog 已启用
ENABLE_4_2_1_3=true    # 4.2.1.3 确保日志文件权限配置正确
ENABLE_4_2_1_4=true    # 4.2.1.4 确保日志写入正确位置
ENABLE_4_2_2_1=true    # 4.2.2.1 确保 journald 配置正确压缩日志
ENABLE_4_2_2_2=true    # 4.2.2.2 确保 journald 将日志写入磁盘
ENABLE_4_2_3=true      # 4.2.3   确保日志文件权限受控

# ---- 5.1 cron ----
ENABLE_5_1_1=true      # 5.1.1  确保 cron 守护进程已启用
ENABLE_5_1_2=true      # 5.1.2  确保 /etc/crontab 权限正确
ENABLE_5_1_3=true      # 5.1.3  确保 /etc/cron.hourly 权限正确
ENABLE_5_1_4=true      # 5.1.4  确保 /etc/cron.daily 权限正确
ENABLE_5_1_5=true      # 5.1.5  确保 /etc/cron.weekly 权限正确
ENABLE_5_1_6=true      # 5.1.6  确保 /etc/cron.monthly 权限正确
ENABLE_5_1_7=true      # 5.1.7  确保 /etc/cron.d 权限正确
ENABLE_5_1_8=true      # 5.1.8  确保 cron 限制为授权用户

# ---- 5.2 SSH 服务 ----
ENABLE_5_2_1=true      # 5.2.1  确保 SSH 配置文件权限正确
ENABLE_5_2_2=true      # 5.2.2  确保 SSH 私钥权限正确
ENABLE_5_2_3=true      # 5.2.3  确保 SSH 公钥权限正确
ENABLE_5_2_4=true      # 5.2.4  确保 SSH 使用强加密算法
ENABLE_5_2_5=true      # 5.2.5  确保 SSH MaxAuthTries 不超过 4
ENABLE_5_2_6=true      # 5.2.6  确保 SSH IgnoreRhosts 已启用
ENABLE_5_2_7=true      # 5.2.7  确保 SSH HostbasedAuthentication 已禁用
ENABLE_5_2_8=true      # 5.2.8  确保 SSH root 登录已禁用
ENABLE_5_2_9=true      # 5.2.9  确保 SSH 空密码已禁用
ENABLE_5_2_10=true     # 5.2.10 确保 SSH 用户环境变量已禁用
ENABLE_5_2_11=true     # 5.2.11 确保仅使用强 MAC 算法
ENABLE_5_2_12=true     # 5.2.12 确保仅使用强 KEX 算法
ENABLE_5_2_13=true     # 5.2.13 确保 SSH 登录宽限时间不超过 60 秒
ENABLE_5_2_14=true     # 5.2.14 确保 SSH 警告横幅已配置
ENABLE_5_2_15=true     # 5.2.15 确保 SSH PAM 已启用
ENABLE_5_2_16=true     # 5.2.16 确保 SSH AllowTcpForwarding 已禁用（需要隧道改 false）
ENABLE_5_2_17=true     # 5.2.17 确保 SSH MaxStartups 已配置
ENABLE_5_2_18=true     # 5.2.18 确保 SSH MaxSessions 不超过 10
ENABLE_5_2_19=true     # 5.2.19 确保 SSH X11Forwarding 已禁用
ENABLE_5_2_20=true     # 5.2.20 确保 SSH ClientAliveInterval 已配置

# ---- 5.3 PAM ----
ENABLE_5_3_1=true      # 5.3.1  确保 PAM 密码复杂度已配置（libpam-pwquality）
ENABLE_5_3_2=true      # 5.3.2  确保 PAM 密码重用历史已配置（不能重用最近5个）
ENABLE_5_3_3=true      # 5.3.3  确保 PAM 密码哈希算法为 SHA512
ENABLE_5_3_4=true      # 5.3.4  确保 PAM 失败锁定已配置（5次失败锁定15分钟）

# ---- 5.4 用户账户策略 ----
ENABLE_5_4_1=true      # 5.4.1  确保密码到期策略（PASS_MAX_DAYS=365）
ENABLE_5_4_2=true      # 5.4.2  确保密码最短有效期（PASS_MIN_DAYS=1）
ENABLE_5_4_3=true      # 5.4.3  确保密码到期警告天数（PASS_WARN_AGE=7）
ENABLE_5_4_4=true      # 5.4.4  确保非活动账户锁定（30天）
ENABLE_5_4_5=true      # 5.4.5  确保默认 umask 为 027 或更严格
ENABLE_5_4_6=true      # 5.4.6  确保 root 默认组为 GID 0
ENABLE_5_4_7=true      # 5.4.7  确保系统账户设置为非登录状态
ENABLE_5_4_8=true      # 5.4.8  确保 root 账户有密码（需交互输入）

# ---- 5.5 sudo ----
ENABLE_5_5_1=true      # 5.5.1  确保 sudo 已安装
ENABLE_5_5_2=true      # 5.5.2  确保 sudo 指令不使用 NOPASSWD
ENABLE_5_5_3=true      # 5.5.3  确保 sudo 需要密码重新认证（不超过15分钟）
ENABLE_5_5_4=true      # 5.5.4  确保 su 命令仅限 sudo 组

# ---- 6.1 系统文件权限 ----
ENABLE_6_1_1=true      # 6.1.1  审计系统文件权限（dpkg verify）
ENABLE_6_1_2=true      # 6.1.2  确保 /etc/passwd 权限为 644
ENABLE_6_1_3=true      # 6.1.3  确保 /etc/passwd- 权限为 644 或更严
ENABLE_6_1_4=true      # 6.1.4  确保 /etc/shadow 权限为 640 或更严
ENABLE_6_1_5=true      # 6.1.5  确保 /etc/shadow- 权限为 640 或更严
ENABLE_6_1_6=true      # 6.1.6  确保 /etc/group 权限为 644
ENABLE_6_1_7=true      # 6.1.7  确保 /etc/group- 权限为 644 或更严
ENABLE_6_1_8=true      # 6.1.8  确保 /etc/gshadow 权限为 640 或更严
ENABLE_6_1_9=true      # 6.1.9  确保 /etc/gshadow- 权限为 640 或更严
ENABLE_6_1_10=true     # 6.1.10 确保无全局可写文件（仅审计）
ENABLE_6_1_11=true     # 6.1.11 确保无无主文件（仅审计）
ENABLE_6_1_12=true     # 6.1.12 确保 SUID/SGID 文件审计

# ---- 6.2 用户和组设置 ----
ENABLE_6_2_1=true      # 6.2.1  确保 /etc/passwd 中所有用户账户有密码
ENABLE_6_2_2=true      # 6.2.2  确保 /etc/shadow 密码字段非空
ENABLE_6_2_3=true      # 6.2.3  确保所有用户 UID 唯一
ENABLE_6_2_4=true      # 6.2.4  确保所有组 GID 唯一
ENABLE_6_2_5=true      # 6.2.5  确保所有用户名唯一
ENABLE_6_2_6=true      # 6.2.6  确保所有组名唯一
ENABLE_6_2_7=true      # 6.2.7  确保 root 是唯一 UID 为 0 的账户
ENABLE_6_2_8=true      # 6.2.8  确保 root 的 PATH 中无危险路径
ENABLE_6_2_9=true      # 6.2.9  确保所有用户家目录存在且权限正确
ENABLE_6_2_10=true     # 6.2.10 确保用户点文件不是全局可写
ENABLE_6_2_11=true     # 6.2.11 确保无用户有 .forward 文件
ENABLE_6_2_12=true     # 6.2.12 确保无用户有 .netrc 文件
ENABLE_6_2_13=true     # 6.2.13 确保无用户有 .rhosts 文件
ENABLE_6_2_14=true     # 6.2.14 确保 /etc/passwd 中所有组存在于 /etc/group
ENABLE_6_2_15=true     # 6.2.15 确保 shadow 和 passwd 账户一致

# =============================================================================
# 以下为脚本执行代码，无需修改（除非你清楚知道在做什么）
# =============================================================================

# ---- 全局变量 ----
BACKUP_DIR="/root/cis_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/cis_hardening_$(date +%Y%m%d_%H%M%S).log"
SYSCTL_FILE="/etc/sysctl.d/60-cis-harden.conf"
AUDIT_RULES_FILE="/etc/audit/rules.d/99-cis.rules"
PASS_RESULTS=0
FAIL_RESULTS=0
SKIP_RESULTS=0
FIXED_RESULTS=0
STILL_FAIL=0

# ---- 颜色 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ---- 日志函数 ----
log()      { echo -e "$1" | tee -a "$LOG_FILE"; }
log_pass() { log "${GREEN}[PASS]${NC} $1"; ((PASS_RESULTS++)); }
log_fail() { log "${RED}[FAIL]${NC} $1"; ((FAIL_RESULTS++)); }
log_skip() { log "${YELLOW}[SKIP]${NC} $1"; ((SKIP_RESULTS++)); }
log_fix()  { log "${CYAN}[FIX] ${NC} $1"; ((FIXED_RESULTS++)); }
log_info() { log "${BLUE}[INFO]${NC} $1"; }
log_warn() { log "${YELLOW}[WARN]${NC} $1"; }
log_section() {
    log "\n${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    log "${BOLD}${BLUE}  $1${NC}"
    log "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
}

# ---- 工具函数 ----
check_root() {
    [ "$(id -u)" -ne 0 ] && { echo -e "${RED}错误：请使用 root 权限运行: sudo bash $0${NC}"; exit 1; }
}

backup_file() {
    local file="$1"
    [ -f "$file" ] && cp -p "$file" "$BACKUP_DIR/$(basename $file).bak"
}

get_enable() {
    local var="ENABLE_${1//./_}"
    echo "${!var:-false}"
}

sysctl_set() {
    local key="$1" val="$2"
    grep -q "^${key}" "$SYSCTL_FILE" && sed -i "s|^${key}.*|${key} = ${val}|" "$SYSCTL_FILE" || echo "${key} = ${val}" >> "$SYSCTL_FILE"
    sysctl -w "${key}=${val}" > /dev/null 2>&1
}

modprobe_disable() {
    local mod="$1"
    local conf="/etc/modprobe.d/cis-disable-${mod}.conf"
    echo "install ${mod} /bin/false" > "$conf"
    echo "blacklist ${mod}" >> "$conf"
}

fstab_add_option() {
    local mountpoint="$1" option="$2"
    if grep -q "\s${mountpoint}\s" /etc/fstab; then
        if ! grep "\s${mountpoint}\s" /etc/fstab | grep -q "${option}"; then
            sed -i "s|\(\s${mountpoint}\s\S*\s\S*\s\)\(\S*\)|\1\2,${option}|" /etc/fstab
            return 0
        fi
    fi
    return 1
}

mount_has_option() {
    local mountpoint="$1" option="$2"
    findmnt -n -o OPTIONS "$mountpoint" 2>/dev/null | grep -qw "$option"
}

# ---- SSH 配置辅助 ----
ssh_set() {
    local key="$1" val="$2"
    local conf="/etc/ssh/sshd_config"
    if grep -qE "^#?\s*${key}\s" "$conf"; then
        sed -i "s|^#\?\s*${key}\s.*|${key} ${val}|" "$conf"
    else
        echo "${key} ${val}" >> "$conf"
    fi
}

# =============================================================================
# ---- 审计函数（每个 CIS 项目独立一个函数）----
# 返回值：0=合规 1=不合规
# =============================================================================

# ---------- 1.1 文件系统 ----------

audit_1_1_1() {
    local fs="$1" id="$2"
    if modprobe -n -v "$fs" 2>/dev/null | grep -q "install /bin/false" || \
       grep -r "install $fs /bin/false" /etc/modprobe.d/ >/dev/null 2>&1; then
        log_pass "$id 文件系统 $fs 已禁用"; return 0
    fi
    log_fail "$id 文件系统 $fs 未禁用（仍可加载）"; return 1
}

fix_1_1_1() {
    local fs="$1" id="$2"
    modprobe_disable "$fs"
    log_fix "$id 已禁用文件系统: $fs"
}

audit_mount_option() {
    local mp="$1" opt="$2" id="$3"
    if mount_has_option "$mp" "$opt"; then
        log_pass "$id $mp 已设置 $opt"; return 0
    fi
    # 检查是否有挂载点
    if ! findmnt -n "$mp" >/dev/null 2>&1; then
        log_skip "$id $mp 未作为独立分区挂载（建议单独分区）"; return 2
    fi
    log_fail "$id $mp 缺少 $opt 选项"; return 1
}

fix_mount_option() {
    local mp="$1" opt="$2" id="$3"
    if findmnt -n "$mp" >/dev/null 2>&1; then
        fstab_add_option "$mp" "$opt" && log_fix "$id 已在 /etc/fstab 为 $mp 添加 $opt（需重启生效）"
        mount -o "remount,$opt" "$mp" 2>/dev/null && log_fix "$id 已立即重新挂载 $mp 加上 $opt"
    else
        log_warn "$id $mp 未独立挂载，跳过（建议分区独立）"
    fi
}

# ---------- 1.2 软件更新 ----------

audit_1_2_1() {
    if grep -rq "^deb https" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        log_pass "1.2.1 apt 源已使用 HTTPS"; return 0
    fi
    log_fail "1.2.1 apt 源未使用 HTTPS"; return 1
}
fix_1_2_1() { log_warn "1.2.1 请手动检查 /etc/apt/sources.list 确保使用 HTTPS 源"; }

audit_1_2_2() {
    if apt-key list 2>/dev/null | grep -qi "debian" || ls /etc/apt/trusted.gpg.d/*.gpg >/dev/null 2>&1; then
        log_pass "1.2.2 apt GPG 签名验证已配置"; return 0
    fi
    log_fail "1.2.2 apt GPG 签名验证未找到"; return 1
}
fix_1_2_2() { log_warn "1.2.2 请确保 /etc/apt/trusted.gpg.d/ 包含正确的 GPG 密钥"; }

# ---------- 1.3 文件完整性 ----------

audit_1_3_1() {
    dpkg -l aide aide-common 2>/dev/null | grep -q "^ii" && { log_pass "1.3.1 AIDE 已安装"; return 0; }
    log_fail "1.3.1 AIDE 未安装"; return 1
}
fix_1_3_1() {
    apt-get install -y aide aide-common -qq
    if [ ! -f /var/lib/aide/aide.db ]; then
        log_info "1.3.1 初始化 AIDE 数据库（需要几分钟）..."
        aideinit > /dev/null 2>&1
        [ -f /var/lib/aide/aide.db.new ] && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
    log_fix "1.3.1 AIDE 安装完成"
}

audit_1_3_2() {
    if crontab -l -u root 2>/dev/null | grep -q "aide" || ls /etc/cron.d/aide /etc/cron.daily/aide 2>/dev/null | grep -q "aide"; then
        log_pass "1.3.2 AIDE 定期检查已配置"; return 0
    fi
    log_fail "1.3.2 AIDE 定期检查未配置"; return 1
}
fix_1_3_2() {
    echo "0 5 * * * root /usr/bin/aide --check >> /var/log/aide.log 2>&1" > /etc/cron.d/aide
    log_fix "1.3.2 AIDE 每天 05:00 自动检查已配置"
}

# ---------- 1.4 安全启动 ----------

audit_1_4_1() {
    if grep -q "password" /etc/grub.d/40_custom 2>/dev/null || grep -q "password_pbkdf2" /boot/grub/grub.cfg 2>/dev/null; then
        log_pass "1.4.1 GRUB 引导密码已设置"; return 0
    fi
    log_fail "1.4.1 GRUB 引导密码未设置"; return 1
}
fix_1_4_1() {
    echo ""
    log_warn "1.4.1 需要为 GRUB 引导加载器设置密码"
    echo -e "${YELLOW}请输入 GRUB 管理员密码（用于保护引导修改）：${NC}"
    local GRUB_PASS
    GRUB_PASS=$(grub-mkpasswd-pbkdf2 2>&1 | tee /dev/tty | grep "PBKDF2 hash" | awk '{print $NF}')
    if [ -n "$GRUB_PASS" ]; then
        backup_file /etc/grub.d/40_custom
        cat >> /etc/grub.d/40_custom << GRUBEOF

# CIS 1.4.1 GRUB 密码保护
set superusers="root"
password_pbkdf2 root ${GRUB_PASS}
GRUBEOF
        # 添加 --unrestricted
        grep -q -- "--unrestricted" /etc/grub.d/10_linux || \
        sed -i '/^CLASS="/ s/"$/ --unrestricted"/' /etc/grub.d/10_linux

        update-grub > /dev/null 2>&1
        log_fix "1.4.1 GRUB 引导密码已设置"
    else
        log_warn "1.4.1 GRUB 密码设置失败，请手动执行: grub-mkpasswd-pbkdf2"
    fi
}

audit_1_4_2() {
    local grub_cfg="/boot/grub/grub.cfg"
    [ -f "$grub_cfg" ] || { log_skip "1.4.2 未找到 grub.cfg"; return 2; }
    local perm; perm=$(stat -c "%a" "$grub_cfg")
    [ "$perm" -le 600 ] && { log_pass "1.4.2 grub.cfg 权限为 $perm（合规）"; return 0; }
    log_fail "1.4.2 grub.cfg 权限为 $perm（应 <= 600）"; return 1
}
fix_1_4_2() {
    chmod 600 /boot/grub/grub.cfg 2>/dev/null
    chown root:root /boot/grub/grub.cfg 2>/dev/null
    log_fix "1.4.2 /boot/grub/grub.cfg 权限已设为 600"
}

audit_1_4_3() {
    if grep -q "^GRUB_DISABLE_RECOVERY" /etc/default/grub && ! grep -q 'GRUB_DISABLE_RECOVERY=false' /etc/default/grub 2>/dev/null; then
        log_pass "1.4.3 单用户模式已受保护"; return 0
    fi
    log_fail "1.4.3 单用户模式未受保护（需设置 root 密码）"; return 1
}
fix_1_4_3() {
    backup_file /etc/default/grub
    if grep -q "^GRUB_DISABLE_RECOVERY" /etc/default/grub; then
        sed -i 's/^GRUB_DISABLE_RECOVERY.*/GRUB_DISABLE_RECOVERY=true/' /etc/default/grub
    else
        echo 'GRUB_DISABLE_RECOVERY=true' >> /etc/default/grub
    fi
    update-grub > /dev/null 2>&1
    log_fix "1.4.3 已禁用 recovery 模式（防止无密码单用户访问）"

    # 确保 root 有密码
    if ! grep -q "^root:[!*]" /etc/shadow; then
        log_pass "1.4.3 root 账户已有密码"
    else
        echo ""
        log_warn "1.4.3 root 账户当前无密码，CIS 要求设置密码"
        echo -e "${YELLOW}请为 root 账户设置密码（直接回车跳过）：${NC}"
        passwd root
    fi
}

# ---------- 1.5 进程加固 ----------

audit_1_5_1() {
    local hard_core; hard_core=$(grep -s "hard core" /etc/security/limits.conf /etc/security/limits.d/*.conf 2>/dev/null | grep "0")
    local suid_dump; suid_dump=$(sysctl -n fs.suid_dumpable 2>/dev/null)
    [ -n "$hard_core" ] && [ "$suid_dump" = "0" ] && { log_pass "1.5.1 core dump 已受限"; return 0; }
    log_fail "1.5.1 core dump 未完全受限"; return 1
}
fix_1_5_1() {
    backup_file /etc/security/limits.conf
    grep -q "hard core" /etc/security/limits.conf || echo "* hard core 0" >> /etc/security/limits.conf
    sysctl_set "fs.suid_dumpable" "0"
    # 配置 systemd core dump
    mkdir -p /etc/systemd/coredump.conf.d/
    echo -e "[Coredump]\nStorage=none\nProcessSizeMax=0" > /etc/systemd/coredump.conf.d/cis.conf
    log_fix "1.5.1 core dump 已限制"
}

audit_1_5_2() {
    local nx; nx=$(dmesg | grep -i "NX\|XD" | head -1)
    grep -qi "NX.*protection.*active\|execute disable.*active" /proc/cpuinfo 2>/dev/null && { log_pass "1.5.2 NX/XD 位已启用（硬件支持）"; return 0; }
    dmesg 2>/dev/null | grep -qi "NX.*active\|NX bit.*active" && { log_pass "1.5.2 NX/XD 位已启用"; return 0; }
    log_warn "1.5.2 无法确认 NX/XD 状态（BIOS 设置，脚本无法修改）"; return 2
}
fix_1_5_2() { log_warn "1.5.2 NX/XD 为硬件/BIOS 设置，请进入 BIOS 启用 Execute Disable Bit"; }

audit_1_5_3() {
    local val; val=$(sysctl -n kernel.randomize_va_space 2>/dev/null)
    [ "$val" = "2" ] && { log_pass "1.5.3 ASLR 已启用（值=2）"; return 0; }
    log_fail "1.5.3 ASLR 未完全启用（当前值=$val，应为2）"; return 1
}
fix_1_5_3() { sysctl_set "kernel.randomize_va_space" "2"; log_fix "1.5.3 ASLR 已设为级别2（完全随机化）"; }

audit_1_5_4() {
    local val; val=$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null)
    [ "$val" -ge 1 ] 2>/dev/null && { log_pass "1.5.4 ptrace 范围已限制（值=$val）"; return 0; }
    log_fail "1.5.4 ptrace 未限制（当前值=$val，应 >= 1）"; return 1
}
fix_1_5_4() { sysctl_set "kernel.yama.ptrace_scope" "1"; log_fix "1.5.4 ptrace 范围已限制为1（仅父进程）"; }

# ---------- 1.6 AppArmor ----------

audit_1_6_1_1() {
    dpkg -l apparmor 2>/dev/null | grep -q "^ii" && { log_pass "1.6.1.1 AppArmor 已安装"; return 0; }
    log_fail "1.6.1.1 AppArmor 未安装"; return 1
}
fix_1_6_1_1() { apt-get install -y apparmor apparmor-utils -qq; log_fix "1.6.1.1 AppArmor 安装完成"; }

audit_1_6_1_2() {
    if grep -q "apparmor=1" /proc/cmdline && grep -q "security=apparmor" /proc/cmdline; then
        log_pass "1.6.1.2 AppArmor 已在启动时启用"; return 0
    fi
    if systemctl is-active apparmor >/dev/null 2>&1; then
        log_pass "1.6.1.2 AppArmor 服务运行中"; return 0
    fi
    log_fail "1.6.1.2 AppArmor 未在启动时启用"; return 1
}
fix_1_6_1_2() {
    systemctl enable apparmor && systemctl start apparmor
    # 确保 GRUB 参数包含 apparmor
    if ! grep -q "apparmor=1" /etc/default/grub; then
        backup_file /etc/default/grub
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=1 security=apparmor"/' /etc/default/grub
        update-grub > /dev/null 2>&1
    fi
    log_fix "1.6.1.2 AppArmor 已启用并添加到启动参数"
}

audit_1_6_1_3() {
    local unconfined; unconfined=$(apparmor_status 2>/dev/null | grep -c "processes are unconfined")
    local profiles; profiles=$(apparmor_status 2>/dev/null | grep "profiles are loaded" | awk '{print $1}')
    [ -n "$profiles" ] && [ "$profiles" -gt 0 ] && { log_pass "1.6.1.3 AppArmor 已加载 $profiles 个配置文件"; return 0; }
    log_fail "1.6.1.3 AppArmor 未加载配置文件"; return 1
}
fix_1_6_1_3() {
    aa-enforce /etc/apparmor.d/* 2>/dev/null
    log_fix "1.6.1.3 AppArmor 配置文件已设为 enforce 模式"
}

audit_1_6_1_4() {
    local unconfined; unconfined=$(aa-status 2>/dev/null | grep "processes are unconfined but have a profile defined" | awk '{print $1}')
    [ "${unconfined:-0}" -eq 0 ] && { log_pass "1.6.1.4 无进程处于 unconfined 状态"; return 0; }
    log_warn "1.6.1.4 有 $unconfined 个进程处于 unconfined 状态（建议检查）"; return 1
}
fix_1_6_1_4() {
    aa-enforce /etc/apparmor.d/* 2>/dev/null
    log_fix "1.6.1.4 已强制所有可用 AppArmor 配置文件"
}

# ---------- 1.7 警告横幅 ----------

BANNER_TEXT="Authorized users only. All activity may be monitored and reported. Unauthorized access is strictly prohibited."

audit_1_7_banner() {
    local file="$1" id="$2"
    [ -s "$file" ] && ! grep -qiE "debian|ubuntu|linux|kernel" "$file" && { log_pass "$id $file 警告横幅已配置"; return 0; }
    log_fail "$id $file 未配置警告横幅或包含系统信息泄露"; return 1
}
fix_1_7_banner() {
    local file="$1" id="$2"
    backup_file "$file"
    echo "$BANNER_TEXT" > "$file"
    log_fix "$id $file 警告横幅已设置"
}

audit_1_7_perm() {
    local file="$1" expected="$2" id="$3"
    local perm owner group
    perm=$(stat -c "%a" "$file" 2>/dev/null)
    owner=$(stat -c "%U" "$file" 2>/dev/null)
    group=$(stat -c "%G" "$file" 2>/dev/null)
    [ "$perm" = "$expected" ] && [ "$owner" = "root" ] && [ "$group" = "root" ] && { log_pass "$id $file 权限正确（$perm root:root）"; return 0; }
    log_fail "$id $file 权限不正确（当前 $perm $owner:$group，应 $expected root:root）"; return 1
}
fix_1_7_perm() {
    local file="$1" perm="$2" id="$3"
    chmod "$perm" "$file" && chown root:root "$file"
    log_fix "$id $file 权限已设为 $perm root:root"
}

# ---------- 2.1/2.2 服务 ----------

audit_pkg_not_installed() {
    local pkg="$1" id="$2"
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && { log_fail "$id $pkg 已安装（不合规）"; return 1; }
    log_pass "$id $pkg 未安装（合规）"; return 0
}
fix_pkg_remove() {
    local pkg="$1" id="$2"
    apt-get purge -y "$pkg" -qq 2>/dev/null
    log_fix "$id 已卸载 $pkg"
}

audit_2_2_1() {
    dpkg -l chrony 2>/dev/null | grep -q "^ii" && systemctl is-active chrony >/dev/null 2>&1 && { log_pass "2.2.1 chrony 时间同步已安装并运行"; return 0; }
    dpkg -l ntp 2>/dev/null | grep -q "^ii" && systemctl is-active ntp >/dev/null 2>&1 && { log_pass "2.2.1 ntp 时间同步已安装并运行"; return 0; }
    log_fail "2.2.1 时间同步服务未配置"; return 1
}
fix_2_2_1() {
    apt-get install -y chrony -qq
    systemctl enable chrony && systemctl start chrony
    log_fix "2.2.1 chrony 已安装并启动"
}

# ---------- 3.1-3.2 网络内核参数 ----------

audit_sysctl() {
    local key="$1" expected="$2" id="$3"
    local val; val=$(sysctl -n "$key" 2>/dev/null)
    [ "$val" = "$expected" ] && { log_pass "$id $key = $val（合规）"; return 0; }
    log_fail "$id $key = $val（应为 $expected）"; return 1
}
fix_sysctl() {
    local key="$1" val="$2" id="$3"
    sysctl_set "$key" "$val"
    log_fix "$id 已设置 $key = $val"
}

# ---------- 3.4 禁用协议 ----------

audit_proto_disabled() {
    local proto="$1" id="$2"
    grep -r "install $proto /bin/false" /etc/modprobe.d/ >/dev/null 2>&1 && { log_pass "$id 协议 $proto 已禁用"; return 0; }
    log_fail "$id 协议 $proto 未禁用"; return 1
}
fix_proto_disable() {
    local proto="$1" id="$2"
    modprobe_disable "$proto"
    log_fix "$id 已禁用协议 $proto"
}

# ---------- 3.5 防火墙（UFW）----------

audit_3_5_1_1() {
    dpkg -l ufw 2>/dev/null | grep -q "^ii" && { log_pass "3.5.1.1 UFW 已安装"; return 0; }
    log_fail "3.5.1.1 UFW 未安装"; return 1
}
fix_3_5_1_1() {
    apt-get install -y ufw -qq
    log_fix "3.5.1.1 UFW 安装完成"
}

audit_3_5_1_2() {
    ufw status 2>/dev/null | grep -q "^Status: active" && \
    systemctl is-enabled ufw >/dev/null 2>&1 && { log_pass "3.5.1.2 UFW 已启用且开机自启"; return 0; }
    log_fail "3.5.1.2 UFW 未启用或未设置开机自启"; return 1
}
fix_3_5_1_2() {
    # 先禁用可能冲突的防火墙
    systemctl stop nftables 2>/dev/null; systemctl disable nftables 2>/dev/null
    systemctl stop iptables 2>/dev/null; systemctl disable iptables 2>/dev/null
    # 确保 SSH 规则存在后再启用，防止锁机
    ufw allow ssh > /dev/null 2>&1
    echo "y" | ufw enable > /dev/null 2>&1
    systemctl enable ufw
    log_fix "3.5.1.2 UFW 已启用并设置开机自启"
    log_warn "3.5.1.2 ⚠ 防火墙已激活，已默认放行 SSH（22端口）"
}

audit_3_5_1_3() {
    ufw status verbose 2>/dev/null | grep -q "22.*ALLOW" && \
    ufw status verbose 2>/dev/null | grep -q "deny (incoming)" && \
    { log_pass "3.5.1.3 UFW 基础规则已配置（默认拒绝入站，SSH 已放行）"; return 0; }
    log_fail "3.5.1.3 UFW 基础规则未配置"; return 1
}
fix_3_5_1_3() {
    # ---- 默认策略 ----
    ufw default deny incoming   > /dev/null 2>&1   # 默认拒绝所有入站
    ufw default allow outgoing  > /dev/null 2>&1   # 默认允许所有出站
    ufw default deny forward    > /dev/null 2>&1   # 默认拒绝转发

    # ---- SSH 访问（必须保留，防止锁机）----
    ufw allow ssh               > /dev/null 2>&1   # 允许 SSH（端口22）
    # 如果 SSH 使用非标准端口，取消注释并修改端口号：
    # ufw allow 2222/tcp         > /dev/null 2>&1

    # ---- 根据需要取消注释以下规则 ----
    # ufw allow 80/tcp           > /dev/null 2>&1   # HTTP
    # ufw allow 443/tcp          > /dev/null 2>&1   # HTTPS
    # ufw allow 3306/tcp         > /dev/null 2>&1   # MySQL（建议仅允许特定 IP）
    # ufw allow from 192.168.1.0/24 to any port 8080  # 仅允许内网访问 8080

    # ---- 限制 SSH 暴力破解（速率限制）----
    ufw limit ssh               > /dev/null 2>&1   # SSH 速率限制（防暴力破解）

    # ---- 允许 ICMP ping（注释掉可禁 ping）----
    # UFW 默认允许 ICMP，可通过 /etc/ufw/before.rules 精细控制

    log_fix "3.5.1.3 UFW 基础规则已配置"
    log_fix "3.5.1.3 默认策略：入站拒绝 / 出站允许 / 转发拒绝"
    log_fix "3.5.1.3 已放行：SSH（22/tcp）并启用速率限制"
    log_warn "3.5.1.3 ⚠ 请根据业务需求在脚本中取消注释其他端口规则"
}

audit_3_5_1_4() {
    ufw status verbose 2>/dev/null | grep -q "deny (incoming)" && { log_pass "3.5.1.4 UFW 入站默认策略为 deny"; return 0; }
    log_fail "3.5.1.4 UFW 入站默认策略不是 deny"; return 1
}
fix_3_5_1_4() {
    ufw default deny incoming > /dev/null 2>&1
    log_fix "3.5.1.4 UFW 入站默认策略已设为 deny"
}

audit_3_5_1_5() {
    ufw status verbose 2>/dev/null | grep -qi "logging: on" && { log_pass "3.5.1.5 UFW 日志记录已启用"; return 0; }
    log_fail "3.5.1.5 UFW 日志记录未启用"; return 1
}
fix_3_5_1_5() {
    ufw logging on > /dev/null 2>&1
    log_fix "3.5.1.5 UFW 日志记录已启用"
}

# ---------- 4.1 auditd ----------

audit_4_1_1_1() {
    dpkg -l auditd 2>/dev/null | grep -q "^ii" && { log_pass "4.1.1.1 auditd 已安装"; return 0; }
    log_fail "4.1.1.1 auditd 未安装"; return 1
}
fix_4_1_1_1() { apt-get install -y auditd audispd-plugins -qq; log_fix "4.1.1.1 auditd 安装完成"; }

audit_4_1_1_2() {
    systemctl is-enabled auditd >/dev/null 2>&1 && systemctl is-active auditd >/dev/null 2>&1 && { log_pass "4.1.1.2 auditd 服务已启用并运行"; return 0; }
    log_fail "4.1.1.2 auditd 服务未启用或未运行"; return 1
}
fix_4_1_1_2() { systemctl enable auditd && systemctl start auditd; log_fix "4.1.1.2 auditd 已启用并启动"; }

audit_4_1_1_3() {
    grep -q "max_log_file_action\s*=\s*keep_logs" /etc/audit/auditd.conf 2>/dev/null && { log_pass "4.1.1.3 审计日志不自动删除（keep_logs）"; return 0; }
    log_fail "4.1.1.3 审计日志可能被自动删除"; return 1
}
fix_4_1_1_3() {
    backup_file /etc/audit/auditd.conf
    sed -i 's/^max_log_file_action.*/max_log_file_action = keep_logs/' /etc/audit/auditd.conf
    grep -q "max_log_file_action" /etc/audit/auditd.conf || echo "max_log_file_action = keep_logs" >> /etc/audit/auditd.conf
    log_fix "4.1.1.3 已设置 max_log_file_action = keep_logs"
}

audit_4_1_1_4() {
    local space_action; space_action=$(grep "^space_left_action" /etc/audit/auditd.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
    [ "$space_action" = "email" ] || [ "$space_action" = "halt" ] && { log_pass "4.1.1.4 磁盘不足处理已配置（$space_action）"; return 0; }
    log_fail "4.1.1.4 磁盘不足处理未配置（应为 email 或 halt）"; return 1
}
fix_4_1_1_4() {
    backup_file /etc/audit/auditd.conf
    sed -i 's/^space_left_action.*/space_left_action = email/' /etc/audit/auditd.conf
    grep -q "space_left_action" /etc/audit/auditd.conf || echo "space_left_action = email" >> /etc/audit/auditd.conf
    sed -i 's/^admin_space_left_action.*/admin_space_left_action = halt/' /etc/audit/auditd.conf
    grep -q "admin_space_left_action" /etc/audit/auditd.conf || echo "admin_space_left_action = halt" >> /etc/audit/auditd.conf
    log_fix "4.1.1.4 space_left_action=email, admin_space_left_action=halt"
}

audit_audit_rule() {
    local pattern="$1" id="$2"
    auditctl -l 2>/dev/null | grep -q "$pattern" && { log_pass "$id 审计规则已配置"; return 0; }
    grep -rq "$pattern" /etc/audit/rules.d/ 2>/dev/null && { log_pass "$id 审计规则文件已配置"; return 0; }
    log_fail "$id 审计规则未配置"; return 1
}

write_audit_rules() {
    cat > "$AUDIT_RULES_FILE" << 'AUDITEOF'
# CIS Debian 12 审计规则（99-cis.rules）

# 4.1.2.1 登录/注销事件
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins

# 4.1.2.2 文件删除事件
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# 4.1.2.3 sudo 使用
-w /usr/bin/sudo -p x -k sudo_usage

# 4.1.2.4 sudo 配置修改
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# 4.1.2.5 mount 操作
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# 4.1.2.6 用户/组信息修改
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# 4.1.2.7 网络环境修改
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# 4.1.2.8 MAC 策略修改
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy

# 4.1.2.9 登录事件
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins
-w /var/run/utmp -p wa -k session

# 4.1.2.10 会话启动
-w /var/log/wtmp -p wa -k session
-w /var/run/utmp -p wa -k session

# 4.1.2.11 文件权限修改
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod

# 4.1.2.12 未授权文件访问
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# 4.1.2.13 SUID/SGID 程序执行
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k setuid
-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k setuid
-a always,exit -F arch=b64 -S execve -C gid!=egid -F egid=0 -k setgid
-a always,exit -F arch=b32 -S execve -C gid!=egid -F egid=0 -k setgid

# 4.1.2.14 内核模块
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# 时间修改
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change
AUDITEOF
    service auditd restart > /dev/null 2>&1
}

fix_4_1_2_all() {
    mkdir -p /etc/audit/rules.d/
    write_audit_rules
    log_fix "4.1.2.x 所有 auditd 规则已写入 $AUDIT_RULES_FILE"
}

audit_4_1_3_1() {
    local bad; bad=$(find /var/log/audit/ -type f ! -perm 640 2>/dev/null | wc -l)
    [ "$bad" -eq 0 ] && { log_pass "4.1.3.1 审计日志文件权限合规（640）"; return 0; }
    log_fail "4.1.3.1 有 $bad 个审计日志文件权限不合规"; return 1
}
fix_4_1_3_1() { find /var/log/audit/ -type f -exec chmod 640 {} \;; log_fix "4.1.3.1 审计日志权限已修正为 640"; }

audit_4_1_3_2() {
    local bad; bad=$(find /etc/audit/ -type f ! -perm 640 2>/dev/null | wc -l)
    [ "$bad" -eq 0 ] && { log_pass "4.1.3.2 审计配置文件权限合规（640）"; return 0; }
    log_fail "4.1.3.2 有 $bad 个审计配置文件权限不合规"; return 1
}
fix_4_1_3_2() { find /etc/audit/ -type f -exec chmod 640 {} \; && chown -R root:root /etc/audit/; log_fix "4.1.3.2 审计配置权限已修正"; }

audit_4_1_3_3() {
    for tool in auditctl auditd ausearch aureport autrace; do
        local path; path=$(which "$tool" 2>/dev/null)
        [ -z "$path" ] && continue
        local perm; perm=$(stat -c "%a" "$path")
        [ "$perm" -gt 755 ] && { log_fail "4.1.3.3 审计工具 $tool 权限过宽（$perm）"; return 1; }
    done
    log_pass "4.1.3.3 审计工具权限合规（<=755）"; return 0
}
fix_4_1_3_3() {
    for tool in auditctl auditd ausearch aureport autrace; do
        local path; path=$(which "$tool" 2>/dev/null)
        [ -n "$path" ] && chmod 755 "$path"
    done
    log_fix "4.1.3.3 审计工具权限已修正为 755"
}

# ---------- 4.2 日志 ----------

audit_4_2_1_1() {
    dpkg -l rsyslog 2>/dev/null | grep -q "^ii" && { log_pass "4.2.1.1 rsyslog 已安装"; return 0; }
    log_fail "4.2.1.1 rsyslog 未安装"; return 1
}
fix_4_2_1_1() { apt-get install -y rsyslog -qq; log_fix "4.2.1.1 rsyslog 安装完成"; }

audit_4_2_1_2() {
    systemctl is-enabled rsyslog >/dev/null 2>&1 && { log_pass "4.2.1.2 rsyslog 已启用"; return 0; }
    log_fail "4.2.1.2 rsyslog 未启用"; return 1
}
fix_4_2_1_2() { systemctl enable rsyslog && systemctl start rsyslog; log_fix "4.2.1.2 rsyslog 已启用"; }

audit_4_2_1_3() {
    grep -q "FileCreateMode" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null && { log_pass "4.2.1.3 rsyslog 日志文件权限已配置"; return 0; }
    log_fail "4.2.1.3 rsyslog 日志文件权限未配置"; return 1
}
fix_4_2_1_3() {
    echo '$FileCreateMode 0640' > /etc/rsyslog.d/99-cis-permissions.conf
    systemctl restart rsyslog 2>/dev/null
    log_fix "4.2.1.3 rsyslog 日志文件权限设为 0640"
}

audit_4_2_1_4() {
    grep -qE "^\*\.\*|auth\.\*|kern\.\*" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null && { log_pass "4.2.1.4 rsyslog 日志写入目标已配置"; return 0; }
    log_fail "4.2.1.4 rsyslog 日志写入目标未配置"; return 1
}
fix_4_2_1_4() {
    cat > /etc/rsyslog.d/99-cis-logging.conf << 'RSYSEOF'
# CIS 4.2.1.4 基础日志规则
auth,authpriv.*          /var/log/auth.log
*.*;auth,authpriv.none   -/var/log/syslog
kern.*                   -/var/log/kern.log
mail.*                   -/var/log/mail.log
RSYSEOF
    systemctl restart rsyslog 2>/dev/null
    log_fix "4.2.1.4 rsyslog 日志写入规则已配置"
}

audit_4_2_2_1() {
    grep -q "Compress=yes" /etc/systemd/journald.conf 2>/dev/null && { log_pass "4.2.2.1 journald 压缩已启用"; return 0; }
    log_fail "4.2.2.1 journald 压缩未启用"; return 1
}
fix_4_2_2_1() {
    backup_file /etc/systemd/journald.conf
    sed -i 's/^#\?Compress=.*/Compress=yes/' /etc/systemd/journald.conf
    grep -q "^Compress" /etc/systemd/journald.conf || echo "Compress=yes" >> /etc/systemd/journald.conf
    systemctl restart systemd-journald 2>/dev/null
    log_fix "4.2.2.1 journald 压缩已启用"
}

audit_4_2_2_2() {
    grep -qE "^Storage=persistent|^Storage=auto" /etc/systemd/journald.conf 2>/dev/null && { log_pass "4.2.2.2 journald 日志持久化已配置"; return 0; }
    log_fail "4.2.2.2 journald 日志未配置持久化"; return 1
}
fix_4_2_2_2() {
    sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
    grep -q "^Storage" /etc/systemd/journald.conf || echo "Storage=persistent" >> /etc/systemd/journald.conf
    mkdir -p /var/log/journal
    systemctl restart systemd-journald 2>/dev/null
    log_fix "4.2.2.2 journald 日志已设为持久化存储"
}

audit_4_2_3() {
    local bad=0
    for f in /var/log/syslog /var/log/auth.log /var/log/kern.log; do
        [ -f "$f" ] && [ "$(stat -c '%a' $f)" -gt 640 ] && ((bad++))
    done
    [ "$bad" -eq 0 ] && { log_pass "4.2.3 日志文件权限合规"; return 0; }
    log_fail "4.2.3 有 $bad 个日志文件权限过宽"; return 1
}
fix_4_2_3() {
    find /var/log -type f -exec chmod g-wx,o-rwx {} \; 2>/dev/null
    log_fix "4.2.3 日志文件权限已修正"
}

# ---------- 5.1 cron ----------

audit_5_1_1() {
    systemctl is-enabled cron >/dev/null 2>&1 && { log_pass "5.1.1 cron 已启用"; return 0; }
    log_fail "5.1.1 cron 未启用"; return 1
}
fix_5_1_1() { systemctl enable cron && systemctl start cron; log_fix "5.1.1 cron 已启用"; }

audit_cron_perm() {
    local path="$1" expected_perm="$2" id="$3"
    [ -e "$path" ] || { log_skip "$id $path 不存在"; return 2; }
    local perm owner group
    perm=$(stat -c "%a" "$path"); owner=$(stat -c "%U" "$path"); group=$(stat -c "%G" "$path")
    [ "$perm" = "$expected_perm" ] && [ "$owner" = "root" ] && [ "$group" = "root" ] && { log_pass "$id $path 权限正确"; return 0; }
    log_fail "$id $path 权限不合规（当前 $perm $owner:$group，应 $expected_perm root:root）"; return 1
}
fix_cron_perm() {
    local path="$1" perm="$2" id="$3"
    chown root:root "$path" && chmod "$perm" "$path"
    log_fix "$id $path 权限已设为 $perm root:root"
}

audit_5_1_8() {
    local ok=true
    [ -f /etc/cron.deny ] && ok=false
    [ -f /etc/at.deny ] && ok=false
    [ ! -f /etc/cron.allow ] && ok=false
    $ok && { log_pass "5.1.8 cron 访问控制已配置（使用 allow 列表）"; return 0; }
    log_fail "5.1.8 cron 访问控制未正确配置"; return 1
}
fix_5_1_8() {
    rm -f /etc/cron.deny /etc/at.deny
    touch /etc/cron.allow /etc/at.allow
    chown root:root /etc/cron.allow /etc/at.allow
    chmod 600 /etc/cron.allow /etc/at.allow
    log_fix "5.1.8 cron 已使用 allow 列表控制访问"
}

# ---------- 5.2 SSH ----------

audit_5_2_1() {
    local perm; perm=$(stat -c "%a" /etc/ssh/sshd_config 2>/dev/null)
    local own; own=$(stat -c "%U:%G" /etc/ssh/sshd_config 2>/dev/null)
    [ "$perm" = "600" ] && [ "$own" = "root:root" ] && { log_pass "5.2.1 sshd_config 权限正确（600 root:root）"; return 0; }
    log_fail "5.2.1 sshd_config 权限不正确（当前 $perm $own）"; return 1
}
fix_5_2_1() { chown root:root /etc/ssh/sshd_config; chmod 600 /etc/ssh/sshd_config; log_fix "5.2.1 sshd_config 权限已设为 600 root:root"; }

audit_5_2_2() {
    local bad; bad=$(find /etc/ssh -name "ssh_host_*_key" ! -perm 600 2>/dev/null | wc -l)
    [ "$bad" -eq 0 ] && { log_pass "5.2.2 SSH 私钥权限正确（600）"; return 0; }
    log_fail "5.2.2 有 $bad 个 SSH 私钥权限不合规"; return 1
}
fix_5_2_2() { find /etc/ssh -name "ssh_host_*_key" -exec chmod 600 {} \;; log_fix "5.2.2 SSH 私钥权限已修正为 600"; }

audit_5_2_3() {
    local bad; bad=$(find /etc/ssh -name "ssh_host_*_key.pub" ! -perm 644 2>/dev/null | wc -l)
    [ "$bad" -eq 0 ] && { log_pass "5.2.3 SSH 公钥权限正确（644）"; return 0; }
    log_fail "5.2.3 有 $bad 个 SSH 公钥权限不合规"; return 1
}
fix_5_2_3() { find /etc/ssh -name "ssh_host_*_key.pub" -exec chmod 644 {} \;; log_fix "5.2.3 SSH 公钥权限已修正为 644"; }

audit_ssh_option() {
    local key="$1" expected="$2" id="$3"
    local val; val=$(sshd -T 2>/dev/null | grep -i "^${key} " | awk '{print tolower($2)}')
    local exp_lower; exp_lower=$(echo "$expected" | tr '[:upper:]' '[:lower:]')
    [ "$val" = "$exp_lower" ] && { log_pass "$id SSH $key = $val（合规）"; return 0; }
    log_fail "$id SSH $key = $val（应为 $expected）"; return 1
}

fix_ssh_option() {
    local key="$1" val="$2" id="$3"
    backup_file /etc/ssh/sshd_config
    ssh_set "$key" "$val"
    systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null
    log_fix "$id SSH $key 已设为 $val"
}

# ---------- 5.3 PAM ----------

audit_5_3_1() {
    dpkg -l libpam-pwquality 2>/dev/null | grep -q "^ii" && \
    grep -qE "^minlen\s*=\s*1[4-9]|^minlen\s*=\s*[2-9][0-9]" /etc/security/pwquality.conf 2>/dev/null && \
    { log_pass "5.3.1 PAM 密码复杂度已配置（minlen>=14）"; return 0; }
    log_fail "5.3.1 PAM 密码复杂度未配置或不满足要求"; return 1
}
fix_5_3_1() {
    apt-get install -y libpam-pwquality -qq
    backup_file /etc/security/pwquality.conf
    cat > /etc/security/pwquality.conf << 'PWEOF'
# CIS 5.3.1 密码复杂度策略
minlen = 14       # 最小长度
dcredit = -1      # 至少1个数字
ucredit = -1      # 至少1个大写字母
ocredit = -1      # 至少1个特殊字符
lcredit = -1      # 至少1个小写字母
maxrepeat = 3     # 最多连续3个相同字符
minclass = 4      # 至少4种字符类型
PWEOF
    log_fix "5.3.1 PAM 密码复杂度已配置（最小14位，含大小写数字特殊字符）"
}

audit_5_3_2() {
    grep -qE "remember\s*=\s*[5-9]|remember\s*=\s*[1-9][0-9]" /etc/pam.d/common-password 2>/dev/null && \
    { log_pass "5.3.2 密码历史记录已配置（remember>=5）"; return 0; }
    log_fail "5.3.2 密码历史记录未配置"; return 1
}
fix_5_3_2() {
    backup_file /etc/pam.d/common-password
    if grep -q "pam_pwhistory" /etc/pam.d/common-password; then
        sed -i 's/pam_pwhistory.*/pam_pwhistory.so remember=5 use_authtok/' /etc/pam.d/common-password
    else
        sed -i '/pam_unix.so/i password required pam_pwhistory.so remember=5 use_authtok' /etc/pam.d/common-password
    fi
    log_fix "5.3.2 密码历史记录设为5次（不能重用最近5个密码）"
}

audit_5_3_3() {
    grep -qE "pam_unix.*sha512|sha512" /etc/pam.d/common-password 2>/dev/null && { log_pass "5.3.3 密码哈希算法为 SHA512"; return 0; }
    log_fail "5.3.3 密码哈希算法未设为 SHA512"; return 1
}
fix_5_3_3() {
    backup_file /etc/pam.d/common-password
    sed -i 's/pam_unix.so.*/pam_unix.so obscure use_authtok try_first_pass sha512/' /etc/pam.d/common-password
    log_fix "5.3.3 密码哈希算法已设为 SHA512"
}

audit_5_3_4() {
    grep -qE "deny\s*=\s*[1-5]\b" /etc/pam.d/common-auth /etc/security/faillock.conf 2>/dev/null && \
    { log_pass "5.3.4 PAM 登录失败锁定已配置"; return 0; }
    log_fail "5.3.4 PAM 登录失败锁定未配置"; return 1
}
fix_5_3_4() {
    backup_file /etc/pam.d/common-auth
    backup_file /etc/security/faillock.conf
    cat > /etc/security/faillock.conf << 'FEOF'
# CIS 5.3.4 登录失败锁定策略
deny = 5            # 失败5次锁定
fail_interval = 900 # 统计窗口900秒
unlock_time = 600   # 锁定600秒（10分钟）
FEOF
    if ! grep -q "pam_faillock" /etc/pam.d/common-auth; then
        sed -i '/^auth.*pam_unix/i auth required pam_faillock.so preauth\nauth [default=die] pam_faillock.so authfail' /etc/pam.d/common-auth
    fi
    log_fix "5.3.4 PAM 失败锁定：5次失败后锁定10分钟"
}

# ---------- 5.4 账户策略 ----------

audit_login_defs() {
    local key="$1" expected="$2" id="$3" op="${4:-eq}"
    local val; val=$(grep "^${key}" /etc/login.defs 2>/dev/null | awk '{print $2}')
    case "$op" in
        eq) [ "$val" = "$expected" ] && { log_pass "$id $key = $val（合规）"; return 0; } ;;
        le) [ "${val:-9999}" -le "$expected" ] 2>/dev/null && { log_pass "$id $key = $val（合规，<=$expected）"; return 0; } ;;
        ge) [ "${val:-0}" -ge "$expected" ] 2>/dev/null && { log_pass "$id $key = $val（合规，>=$expected）"; return 0; } ;;
    esac
    log_fail "$id $key = $val（不合规，应${op}${expected}）"; return 1
}
fix_login_defs() {
    local key="$1" val="$2" id="$3"
    backup_file /etc/login.defs
    sed -i "s/^${key}\s.*/${key}\t${val}/" /etc/login.defs
    grep -q "^${key}" /etc/login.defs || echo -e "${key}\t${val}" >> /etc/login.defs
    log_fix "$id /etc/login.defs $key 已设为 $val"
}

audit_5_4_4() {
    local val; val=$(useradd -D 2>/dev/null | grep INACTIVE | awk -F= '{print $2}')
    [ "${val:-0}" -le 30 ] && [ "${val:-0}" -gt 0 ] && { log_pass "5.4.4 非活动账户锁定已配置（$val天）"; return 0; }
    log_fail "5.4.4 非活动账户锁定未配置（当前=$val，应1-30天）"; return 1
}
fix_5_4_4() { useradd -D -f 30; log_fix "5.4.4 非活动账户将在30天后锁定"; }

audit_5_4_5() {
    local umask; umask=$(grep "^UMASK" /etc/login.defs 2>/dev/null | awk '{print $2}')
    [ "$umask" = "027" ] || [ "$umask" = "077" ] && { log_pass "5.4.5 默认 umask 为 $umask（合规）"; return 0; }
    log_fail "5.4.5 默认 umask = $umask（应为 027 或更严格）"; return 1
}
fix_5_4_5() {
    backup_file /etc/login.defs
    sed -i 's/^UMASK\s.*/UMASK\t027/' /etc/login.defs
    grep -q "^UMASK" /etc/login.defs || echo -e "UMASK\t027" >> /etc/login.defs
    # 同时设置 /etc/profile
    echo "umask 027" > /etc/profile.d/cis-umask.sh
    log_fix "5.4.5 默认 umask 已设为 027"
}

audit_5_4_6() {
    local gid; gid=$(id -g root 2>/dev/null)
    [ "$gid" = "0" ] && { log_pass "5.4.6 root 默认组为 GID 0"; return 0; }
    log_fail "5.4.6 root 默认组不是 GID 0（当前=$gid）"; return 1
}
fix_5_4_6() { usermod -g 0 root; log_fix "5.4.6 root 默认组已设为 GID 0"; }

audit_5_4_7() {
    local bad=0
    while IFS=: read -r user pass uid gid gecos home shell; do
        [ "$uid" -ge 1000 ] && continue
        [ "$user" = "root" ] && continue
        [[ "$shell" == */nologin || "$shell" == */false ]] || ((bad++))
    done < /etc/passwd
    [ "$bad" -eq 0 ] && { log_pass "5.4.7 所有系统账户均为非登录状态"; return 0; }
    log_fail "5.4.7 有 $bad 个系统账户可登录"; return 1
}
fix_5_4_7() {
    while IFS=: read -r user pass uid gid gecos home shell; do
        [ "$uid" -ge 1000 ] && continue
        [ "$user" = "root" ] && continue
        [[ "$shell" == */nologin || "$shell" == */false ]] && continue
        usermod -s /usr/sbin/nologin "$user" 2>/dev/null
        log_fix "5.4.7 系统账户 $user shell 已设为 /usr/sbin/nologin"
    done < /etc/passwd
}

audit_5_4_8() {
    ! grep -q "^root:[!*]" /etc/shadow 2>/dev/null && { log_pass "5.4.8 root 账户有密码"; return 0; }
    log_fail "5.4.8 root 账户无密码或密码被锁定"; return 1
}
fix_5_4_8() {
    echo ""
    log_warn "5.4.8 需要为 root 账户设置密码"
    echo -e "${YELLOW}请为 root 账户设置密码：${NC}"
    passwd root
}

# ---------- 5.5 sudo ----------

audit_5_5_1() {
    dpkg -l sudo 2>/dev/null | grep -q "^ii" && { log_pass "5.5.1 sudo 已安装"; return 0; }
    log_fail "5.5.1 sudo 未安装"; return 1
}
fix_5_5_1() { apt-get install -y sudo -qq; log_fix "5.5.1 sudo 安装完成"; }

audit_5_5_2() {
    grep -rE "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v "^#" | grep -q "NOPASSWD" && \
    { log_fail "5.5.2 sudoers 中存在 NOPASSWD 条目"; return 1; }
    log_pass "5.5.2 sudoers 中无 NOPASSWD 条目"; return 0
}
fix_5_5_2() {
    log_warn "5.5.2 请手动检查并删除以下 NOPASSWD 条目："
    grep -rn "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v "^#"
}

audit_5_5_3() {
    grep -qE "^Defaults.*timestamp_timeout\s*=\s*([0-9]+)" /etc/sudoers /etc/sudoers.d/*.conf 2>/dev/null
    local val; val=$(grep -hE "^Defaults.*timestamp_timeout" /etc/sudoers /etc/sudoers.d/*.conf 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -n "$val" ] && [ "$val" -le 15 ] && { log_pass "5.5.3 sudo 认证超时已配置（${val}分钟）"; return 0; }
    log_fail "5.5.3 sudo 认证超时未配置或超过15分钟"; return 1
}
fix_5_5_3() {
    echo "Defaults timestamp_timeout=15" > /etc/sudoers.d/cis-timeout
    log_fix "5.5.3 sudo 认证超时设为15分钟"
}

audit_5_5_4() {
    grep -qE "^auth\s+required\s+pam_wheel.so" /etc/pam.d/su 2>/dev/null && { log_pass "5.5.4 su 命令已限制为 sudo 组"; return 0; }
    log_fail "5.5.4 su 命令未限制为 sudo 组"; return 1
}
fix_5_5_4() {
    backup_file /etc/pam.d/su
    sed -i '/^#.*pam_wheel.so/s/^#//' /etc/pam.d/su
    grep -q "pam_wheel.so" /etc/pam.d/su || sed -i '1i auth required pam_wheel.so' /etc/pam.d/su
    log_fix "5.5.4 su 命令已限制为 wheel/sudo 组"
}

# ---------- 6.1 文件权限 ----------

audit_file_perm() {
    local file="$1" max_perm="$2" id="$3"
    [ -f "$file" ] || { log_skip "$id $file 不存在"; return 2; }
    local perm; perm=$(stat -c "%a" "$file")
    [ "$perm" -le "$max_perm" ] && { log_pass "$id $file 权限为 $perm（合规，<=$max_perm）"; return 0; }
    log_fail "$id $file 权限为 $perm（应 <= $max_perm）"; return 1
}
fix_file_perm() {
    local file="$1" perm="$2" id="$3"
    chmod "$perm" "$file" && chown root:root "$file" 2>/dev/null
    log_fix "$id $file 权限已设为 $perm"
}

audit_6_1_1() {
    local output; output=$(dpkg --verify 2>/dev/null | grep -v "^$" | head -10)
    [ -z "$output" ] && { log_pass "6.1.1 系统软件包文件完整性验证通过"; return 0; }
    log_warn "6.1.1 以下软件包文件有变更（可能正常）:\n$output"; return 1
}
fix_6_1_1() { log_warn "6.1.1 请手动检查软件包完整性异常，使用 dpkg --verify 排查"; }

audit_6_1_10() {
    local files; files=$(find / -xdev -type f -perm -0002 2>/dev/null | grep -v /proc | grep -v /sys)
    [ -z "$files" ] && { log_pass "6.1.10 无全局可写文件"; return 0; }
    log_warn "6.1.10 发现全局可写文件（建议检查）:\n$(echo $files | head -20)"; return 1
}
fix_6_1_10() {
    log_warn "6.1.10 以下全局可写文件需人工确认后再处理："
    find / -xdev -type f -perm -0002 2>/dev/null | grep -v /proc | grep -v /sys
}

audit_6_1_11() {
    local files; files=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | grep -v /proc)
    [ -z "$files" ] && { log_pass "6.1.11 无无主文件"; return 0; }
    log_warn "6.1.11 发现无主文件:\n$(echo $files | head -10)"; return 1
}
fix_6_1_11() { log_warn "6.1.11 发现无主文件，请检查后手动处理 chown"; }

audit_6_1_12() {
    log_info "6.1.12 SUID/SGID 文件审计列表："
    find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | sort | tee -a "$LOG_FILE"
    log_warn "6.1.12 请检查以上 SUID/SGID 文件是否都必要"; return 0
}
fix_6_1_12() { log_warn "6.1.12 SUID/SGID 文件需人工判断，请使用 chmod u-s <文件> 移除不需要的位"; }

# ---------- 6.2 用户组检查 ----------

audit_6_2_1() {
    local bad; bad=$(awk -F: '($2 == "") {print $1}' /etc/passwd 2>/dev/null)
    [ -z "$bad" ] && { log_pass "6.2.1 所有用户账户有密码字段"; return 0; }
    log_fail "6.2.1 以下账户密码字段为空: $bad"; return 1
}
fix_6_2_1() { log_warn "6.2.1 请手动处理空密码字段的账户"; }

audit_6_2_2() {
    local bad; bad=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null | head -5)
    [ -z "$bad" ] && { log_pass "6.2.2 所有账户 shadow 密码字段非空"; return 0; }
    log_fail "6.2.2 以下账户无有效密码: $bad"; return 1
}
fix_6_2_2() { log_warn "6.2.2 请为以上账户设置密码或锁定: passwd -l <用户名>"; }

audit_6_2_3() {
    local dups; dups=$(awk -F: 'seen[$3]++{print $1, $3}' /etc/passwd 2>/dev/null)
    [ -z "$dups" ] && { log_pass "6.2.3 所有用户 UID 唯一"; return 0; }
    log_fail "6.2.3 发现重复 UID: $dups"; return 1
}
fix_6_2_3() { log_warn "6.2.3 重复 UID 需要手动修复"; }

audit_6_2_4() {
    local dups; dups=$(awk -F: 'seen[$3]++{print $1, $3}' /etc/group 2>/dev/null)
    [ -z "$dups" ] && { log_pass "6.2.4 所有组 GID 唯一"; return 0; }
    log_fail "6.2.4 发现重复 GID: $dups"; return 1
}
fix_6_2_4() { log_warn "6.2.4 重复 GID 需要手动修复"; }

audit_6_2_5() {
    local dups; dups=$(awk -F: 'seen[$1]++{print $1}' /etc/passwd 2>/dev/null)
    [ -z "$dups" ] && { log_pass "6.2.5 所有用户名唯一"; return 0; }
    log_fail "6.2.5 发现重复用户名: $dups"; return 1
}
fix_6_2_5() { log_warn "6.2.5 重复用户名需要手动修复"; }

audit_6_2_6() {
    local dups; dups=$(awk -F: 'seen[$1]++{print $1}' /etc/group 2>/dev/null)
    [ -z "$dups" ] && { log_pass "6.2.6 所有组名唯一"; return 0; }
    log_fail "6.2.6 发现重复组名: $dups"; return 1
}
fix_6_2_6() { log_warn "6.2.6 重复组名需要手动修复"; }

audit_6_2_7() {
    local uids; uids=$(awk -F: '($3 == 0) {print $1}' /etc/passwd 2>/dev/null)
    [ "$uids" = "root" ] && { log_pass "6.2.7 只有 root 的 UID 为 0"; return 0; }
    log_fail "6.2.7 以下账户 UID 为 0: $uids"; return 1
}
fix_6_2_7() { log_warn "6.2.7 除 root 外的 UID=0 账户需要手动处理"; }

audit_6_2_8() {
    local path; path=$(sudo -i -u root env 2>/dev/null | grep "^PATH=" | cut -d= -f2)
    echo "$path" | grep -qE "^:|::|\s|/\.|:\.:" && { log_fail "6.2.8 root PATH 包含危险路径"; return 1; }
    log_pass "6.2.8 root PATH 安全"; return 0
}
fix_6_2_8() {
    echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' > /etc/profile.d/cis-root-path.sh
    log_fix "6.2.8 root PATH 已设为安全路径"
}

audit_6_2_9() {
    local bad=0
    while IFS=: read -r user _ uid _ _ home _; do
        [ "$uid" -lt 1000 ] && continue
        [ ! -d "$home" ] && { log_warn "6.2.9 用户 $user 家目录 $home 不存在"; ((bad++)); continue; }
        local perm; perm=$(stat -c "%a" "$home")
        [ "$perm" -gt 750 ] && { log_warn "6.2.9 用户 $user 家目录 $home 权限过宽（$perm）"; ((bad++)); }
    done < /etc/passwd
    [ "$bad" -eq 0 ] && { log_pass "6.2.9 所有用户家目录权限合规"; return 0; }
    log_fail "6.2.9 有 $bad 个用户家目录权限问题"; return 1
}
fix_6_2_9() {
    while IFS=: read -r user _ uid _ _ home _; do
        [ "$uid" -lt 1000 ] && continue
        [ ! -d "$home" ] && continue
        local perm; perm=$(stat -c "%a" "$home")
        [ "$perm" -gt 750 ] && { chmod 750 "$home"; log_fix "6.2.9 $home 权限已修正为 750"; }
    done < /etc/passwd
}

audit_6_2_10() {
    local bad=0
    while IFS=: read -r user _ uid _ _ home _; do
        [ "$uid" -lt 1000 ] && continue
        [ -d "$home" ] || continue
        find "$home" -name ".*" -maxdepth 1 -perm -0002 2>/dev/null | while read -r f; do
            log_warn "6.2.10 点文件全局可写: $f"
            ((bad++))
        done
    done < /etc/passwd
    [ "$bad" -eq 0 ] && { log_pass "6.2.10 无全局可写点文件"; return 0; }
    return 1
}
fix_6_2_10() {
    while IFS=: read -r user _ uid _ _ home _; do
        [ "$uid" -lt 1000 ] && continue
        [ -d "$home" ] || continue
        find "$home" -name ".*" -maxdepth 1 -perm -0002 2>/dev/null -exec chmod o-w {} \;
    done < /etc/passwd
    log_fix "6.2.10 已移除点文件的全局可写权限"
}

audit_dot_file() {
    local filename="$1" id="$2"
    local found=0
    while IFS=: read -r user _ uid _ _ home _; do
        [ "$uid" -lt 1000 ] && continue
        [ -f "$home/$filename" ] && { log_warn "$id 用户 $user 有 $filename 文件"; ((found++)); }
    done < /etc/passwd
    [ "$found" -eq 0 ] && { log_pass "$id 无用户有 $filename 文件"; return 0; }
    return 1
}
fix_dot_file() {
    local filename="$1" id="$2"
    while IFS=: read -r user _ uid _ _ home _; do
        [ "$uid" -lt 1000 ] && continue
        [ -f "$home/$filename" ] && rm -f "$home/$filename" && log_fix "$id 已删除 $home/$filename"
    done < /etc/passwd
}

audit_6_2_14() {
    local bad=0
    while IFS=: read -r user _ uid gid _ _ _; do
        if ! grep -q "^[^:]*:[^:]*:${gid}:" /etc/group 2>/dev/null; then
            log_warn "6.2.14 用户 $user 的 GID $gid 在 /etc/group 中不存在"
            ((bad++))
        fi
    done < /etc/passwd
    [ "$bad" -eq 0 ] && { log_pass "6.2.14 所有用户 GID 在 /etc/group 中存在"; return 0; }
    return 1
}
fix_6_2_14() { log_warn "6.2.14 缺失的 GID 需要手动添加到 /etc/group"; }

audit_6_2_15() {
    local r; r=$(pwck -r 2>&1 | grep -v "^$")
    [ -z "$r" ] && { log_pass "6.2.15 passwd 和 shadow 账户一致"; return 0; }
    log_warn "6.2.15 passwd/shadow 存在不一致:\n$r"; return 1
}
fix_6_2_15() { log_warn "6.2.15 账户不一致需要手动修复（使用 pwck 检查）"; }

# =============================================================================
# ---- 执行审计 ----
# =============================================================================

run_audit() {
    local phase="$1"   # "pre" or "post"
    PASS_RESULTS=0; FAIL_RESULTS=0; SKIP_RESULTS=0

    [ "$phase" = "pre" ] && log_section "📋 阶段一：预审计（检查当前合规状态）" || log_section "✅ 阶段三：后审计（验证修复结果）"

    # 1.1 文件系统
    log_section "1.1 文件系统配置"
    for fs_item in "cramfs:1.1.1.1" "freevxfs:1.1.1.2" "jffs2:1.1.1.3" "hfs:1.1.1.4" "hfsplus:1.1.1.5" "squashfs:1.1.1.6" "udf:1.1.1.7"; do
        local fs="${fs_item%%:*}" id="${fs_item##*:}"
        audit_1_1_1 "$fs" "$id"
    done
    audit_mount_option "/tmp"          "nodev"   "1.1.2.2"
    audit_mount_option "/tmp"          "nosuid"  "1.1.2.3"
    audit_mount_option "/tmp"          "noexec"  "1.1.2.4"
    audit_mount_option "/var"          "nodev"   "1.1.3.1"
    audit_mount_option "/var"          "nosuid"  "1.1.3.2"
    audit_mount_option "/var/tmp"      "nodev"   "1.1.4.1"
    audit_mount_option "/var/tmp"      "nosuid"  "1.1.4.2"
    audit_mount_option "/var/tmp"      "noexec"  "1.1.4.3"
    audit_mount_option "/var/log"      "nodev"   "1.1.5.1"
    audit_mount_option "/var/log"      "nosuid"  "1.1.5.2"
    audit_mount_option "/var/log"      "noexec"  "1.1.5.3"
    audit_mount_option "/var/log/audit" "nodev"  "1.1.6.1"
    audit_mount_option "/var/log/audit" "nosuid" "1.1.6.2"
    audit_mount_option "/var/log/audit" "noexec" "1.1.6.3"
    audit_mount_option "/home"         "nodev"   "1.1.7.1"
    audit_mount_option "/home"         "nosuid"  "1.1.7.2"
    audit_mount_option "/dev/shm"      "nodev"   "1.1.8.1"
    audit_mount_option "/dev/shm"      "nosuid"  "1.1.8.2"
    audit_mount_option "/dev/shm"      "noexec"  "1.1.8.3"

    # 1.2 软件更新
    log_section "1.2 软件更新"
    audit_1_2_1; audit_1_2_2

    # 1.3 文件完整性
    log_section "1.3 文件完整性"
    audit_1_3_1; audit_1_3_2

    # 1.4 安全启动
    log_section "1.4 安全启动"
    audit_1_4_1; audit_1_4_2; audit_1_4_3

    # 1.5 进程加固
    log_section "1.5 进程加固"
    audit_1_5_1; audit_1_5_2; audit_1_5_3; audit_1_5_4

    # 1.6 AppArmor
    log_section "1.6 AppArmor"
    audit_1_6_1_1; audit_1_6_1_2; audit_1_6_1_3; audit_1_6_1_4

    # 1.7 横幅
    log_section "1.7 警告横幅"
    audit_1_7_banner "/etc/motd"      "1.7.1"
    audit_1_7_banner "/etc/issue.net" "1.7.2"
    audit_1_7_banner "/etc/issue"     "1.7.3"
    audit_1_7_perm   "/etc/motd"      "644" "1.7.4"
    audit_1_7_perm   "/etc/issue"     "644" "1.7.5"
    audit_1_7_perm   "/etc/issue.net" "644" "1.7.6"

    # 2. 服务
    log_section "2. 服务配置"
    audit_pkg_not_installed "xinetd"          "2.1.1"
    audit_pkg_not_installed "openbsd-inetd"   "2.1.2"
    audit_2_2_1
    audit_pkg_not_installed "xserver-xorg"    "2.2.2"
    audit_pkg_not_installed "avahi-daemon"    "2.2.3"
    audit_pkg_not_installed "cups"            "2.2.4"
    audit_pkg_not_installed "isc-dhcp-server" "2.2.5"
    audit_pkg_not_installed "slapd"           "2.2.6"
    audit_pkg_not_installed "nfs-kernel-server" "2.2.7"
    audit_pkg_not_installed "bind9"           "2.2.8"
    audit_pkg_not_installed "vsftpd"          "2.2.9"
    audit_pkg_not_installed "apache2"         "2.2.10"
    audit_pkg_not_installed "dovecot-imapd"   "2.2.11"
    audit_pkg_not_installed "samba"           "2.2.12"
    audit_pkg_not_installed "squid"           "2.2.13"
    audit_pkg_not_installed "snmpd"           "2.2.14"
    audit_pkg_not_installed "rsync"           "2.2.15"
    audit_pkg_not_installed "nis"             "2.2.16"
    audit_pkg_not_installed "ypbind"          "2.3.1"
    audit_pkg_not_installed "rsh-client"      "2.3.2"
    audit_pkg_not_installed "talk"            "2.3.3"
    audit_pkg_not_installed "telnet"          "2.3.4"
    audit_pkg_not_installed "ldap-utils"      "2.3.5"
    audit_pkg_not_installed "rpcbind"         "2.3.6"

    # 3. 网络
    log_section "3. 网络配置"
    audit_sysctl "net.ipv4.ip_forward"                     "0" "3.1.1"
    audit_sysctl "net.ipv4.conf.all.send_redirects"        "0" "3.1.2"
    audit_sysctl "net.ipv4.conf.all.accept_source_route"   "0" "3.2.1"
    audit_sysctl "net.ipv4.conf.all.accept_redirects"      "0" "3.2.2"
    audit_sysctl "net.ipv4.conf.all.secure_redirects"      "0" "3.2.3"
    audit_sysctl "net.ipv4.conf.all.log_martians"          "1" "3.2.4"
    audit_sysctl "net.ipv4.icmp_echo_ignore_broadcasts"    "1" "3.2.5"
    audit_sysctl "net.ipv4.icmp_ignore_bogus_error_responses" "1" "3.2.6"
    audit_sysctl "net.ipv4.conf.all.rp_filter"             "1" "3.2.7"
    audit_sysctl "net.ipv4.tcp_syncookies"                 "1" "3.2.8"
    audit_sysctl "net.ipv6.conf.all.accept_ra"             "0" "3.2.9"
    audit_sysctl "net.ipv6.conf.all.disable_ipv6"          "1" "3.3.1"
    audit_proto_disabled "dccp" "3.4.1"
    audit_proto_disabled "sctp" "3.4.2"
    audit_proto_disabled "rds"  "3.4.3"
    audit_proto_disabled "tipc" "3.4.4"
    audit_3_5_1_1; audit_3_5_1_2; audit_3_5_1_3; audit_3_5_1_4; audit_3_5_1_5

    # 4. 审计日志
    log_section "4. 审计与日志"
    audit_4_1_1_1; audit_4_1_1_2; audit_4_1_1_3; audit_4_1_1_4
    audit_audit_rule "logins"          "4.1.2.1"
    audit_audit_rule "delete"          "4.1.2.2"
    audit_audit_rule "sudo_usage"      "4.1.2.3"
    audit_audit_rule "sudoers_changes" "4.1.2.4"
    audit_audit_rule "mounts"          "4.1.2.5"
    audit_audit_rule "identity"        "4.1.2.6"
    audit_audit_rule "system-locale"   "4.1.2.7"
    audit_audit_rule "MAC-policy"      "4.1.2.8"
    audit_audit_rule "session"         "4.1.2.9 / 4.1.2.10"
    audit_audit_rule "perm_mod"        "4.1.2.11"
    audit_audit_rule "access"          "4.1.2.12"
    audit_audit_rule "setuid"          "4.1.2.13"
    audit_audit_rule "modules"         "4.1.2.14"
    audit_4_1_3_1; audit_4_1_3_2; audit_4_1_3_3
    audit_4_2_1_1; audit_4_2_1_2; audit_4_2_1_3; audit_4_2_1_4
    audit_4_2_2_1; audit_4_2_2_2; audit_4_2_3

    # 5. 访问控制
    log_section "5. 访问控制"
    audit_5_1_1
    audit_cron_perm "/etc/crontab"      "600" "5.1.2"
    audit_cron_perm "/etc/cron.hourly"  "700" "5.1.3"
    audit_cron_perm "/etc/cron.daily"   "700" "5.1.4"
    audit_cron_perm "/etc/cron.weekly"  "700" "5.1.5"
    audit_cron_perm "/etc/cron.monthly" "700" "5.1.6"
    audit_cron_perm "/etc/cron.d"       "700" "5.1.7"
    audit_5_1_8
    audit_5_2_1; audit_5_2_2; audit_5_2_3
    audit_ssh_option "protocol"                 "2"       "5.2.4"
    audit_ssh_option "maxauthtries"             "4"       "5.2.5"
    audit_ssh_option "ignorerhosts"             "yes"     "5.2.6"
    audit_ssh_option "hostbasedauthentication"  "no"      "5.2.7"
    audit_ssh_option "permitrootlogin"          "no"      "5.2.8"
    audit_ssh_option "permitemptypasswords"     "no"      "5.2.9"
    audit_ssh_option "permituserenvironment"    "no"      "5.2.10"
    audit_ssh_option "logingracetime"           "60"      "5.2.13"
    audit_ssh_option "banner"                   "/etc/issue.net" "5.2.14"
    audit_ssh_option "usepam"                   "yes"     "5.2.15"
    audit_ssh_option "allowtcpforwarding"       "no"      "5.2.16"
    audit_ssh_option "maxsessions"              "4"       "5.2.18"
    audit_ssh_option "x11forwarding"            "no"      "5.2.19"
    audit_ssh_option "clientaliveinterval"      "300"     "5.2.20"
    audit_5_3_1; audit_5_3_2; audit_5_3_3; audit_5_3_4
    audit_login_defs "PASS_MAX_DAYS" "365" "5.4.1" "le"
    audit_login_defs "PASS_MIN_DAYS" "1"   "5.4.2" "ge"
    audit_login_defs "PASS_WARN_AGE" "7"   "5.4.3" "ge"
    audit_5_4_4; audit_5_4_5; audit_5_4_6; audit_5_4_7; audit_5_4_8
    audit_5_5_1; audit_5_5_2; audit_5_5_3; audit_5_5_4

    # 6. 文件权限
    log_section "6. 文件权限"
    audit_6_1_1
    audit_file_perm "/etc/passwd"  "644" "6.1.2"
    audit_file_perm "/etc/passwd-" "644" "6.1.3"
    audit_file_perm "/etc/shadow"  "640" "6.1.4"
    audit_file_perm "/etc/shadow-" "640" "6.1.5"
    audit_file_perm "/etc/group"   "644" "6.1.6"
    audit_file_perm "/etc/group-"  "644" "6.1.7"
    audit_file_perm "/etc/gshadow" "640" "6.1.8"
    audit_file_perm "/etc/gshadow-" "640" "6.1.9"
    audit_6_1_10; audit_6_1_11; audit_6_1_12
    audit_6_2_1; audit_6_2_2; audit_6_2_3; audit_6_2_4; audit_6_2_5
    audit_6_2_6; audit_6_2_7; audit_6_2_8; audit_6_2_9; audit_6_2_10
    audit_dot_file ".forward" "6.2.11"
    audit_dot_file ".netrc"   "6.2.12"
    audit_dot_file ".rhosts"  "6.2.13"
    audit_6_2_14; audit_6_2_15
}

# =============================================================================
# ---- 执行修复 ----
# =============================================================================

run_fixes() {
    log_section "🔧 阶段二：执行修复"
    FIXED_RESULTS=0

    # 1.1 文件系统
    [ "$ENABLE_1_1_1_1" = "true" ] && fix_1_1_1 "cramfs"   "1.1.1.1"
    [ "$ENABLE_1_1_1_2" = "true" ] && fix_1_1_1 "freevxfs" "1.1.1.2"
    [ "$ENABLE_1_1_1_3" = "true" ] && fix_1_1_1 "jffs2"    "1.1.1.3"
    [ "$ENABLE_1_1_1_4" = "true" ] && fix_1_1_1 "hfs"      "1.1.1.4"
    [ "$ENABLE_1_1_1_5" = "true" ] && fix_1_1_1 "hfsplus"  "1.1.1.5"
    [ "$ENABLE_1_1_1_6" = "true" ] && fix_1_1_1 "squashfs" "1.1.1.6"
    [ "$ENABLE_1_1_1_7" = "true" ] && fix_1_1_1 "udf"      "1.1.1.7"
    touch "$SYSCTL_FILE"
    [ "$ENABLE_1_1_2_1" = "true" ] && { grep -q "\s/tmp\s" /etc/fstab || echo "tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec 0 0" >> /etc/fstab; log_fix "1.1.2.1 /tmp 已加入 fstab"; }
    [ "$ENABLE_1_1_2_2" = "true" ] && fix_mount_option "/tmp" "nodev"   "1.1.2.2"
    [ "$ENABLE_1_1_2_3" = "true" ] && fix_mount_option "/tmp" "nosuid"  "1.1.2.3"
    [ "$ENABLE_1_1_2_4" = "true" ] && fix_mount_option "/tmp" "noexec"  "1.1.2.4"
    [ "$ENABLE_1_1_3_1" = "true" ] && fix_mount_option "/var" "nodev"   "1.1.3.1"
    [ "$ENABLE_1_1_3_2" = "true" ] && fix_mount_option "/var" "nosuid"  "1.1.3.2"
    [ "$ENABLE_1_1_4_1" = "true" ] && fix_mount_option "/var/tmp" "nodev"   "1.1.4.1"
    [ "$ENABLE_1_1_4_2" = "true" ] && fix_mount_option "/var/tmp" "nosuid"  "1.1.4.2"
    [ "$ENABLE_1_1_4_3" = "true" ] && fix_mount_option "/var/tmp" "noexec"  "1.1.4.3"
    [ "$ENABLE_1_1_5_1" = "true" ] && fix_mount_option "/var/log" "nodev"   "1.1.5.1"
    [ "$ENABLE_1_1_5_2" = "true" ] && fix_mount_option "/var/log" "nosuid"  "1.1.5.2"
    [ "$ENABLE_1_1_5_3" = "true" ] && fix_mount_option "/var/log" "noexec"  "1.1.5.3"
    [ "$ENABLE_1_1_6_1" = "true" ] && fix_mount_option "/var/log/audit" "nodev"   "1.1.6.1"
    [ "$ENABLE_1_1_6_2" = "true" ] && fix_mount_option "/var/log/audit" "nosuid"  "1.1.6.2"
    [ "$ENABLE_1_1_6_3" = "true" ] && fix_mount_option "/var/log/audit" "noexec"  "1.1.6.3"
    [ "$ENABLE_1_1_7_1" = "true" ] && fix_mount_option "/home" "nodev"  "1.1.7.1"
    [ "$ENABLE_1_1_7_2" = "true" ] && fix_mount_option "/home" "nosuid" "1.1.7.2"
    [ "$ENABLE_1_1_8_1" = "true" ] && fix_mount_option "/dev/shm" "nodev"   "1.1.8.1"
    [ "$ENABLE_1_1_8_2" = "true" ] && fix_mount_option "/dev/shm" "nosuid"  "1.1.8.2"
    [ "$ENABLE_1_1_8_3" = "true" ] && fix_mount_option "/dev/shm" "noexec"  "1.1.8.3"

    # 1.2
    [ "$ENABLE_1_2_1" = "true" ] && fix_1_2_1
    [ "$ENABLE_1_2_2" = "true" ] && fix_1_2_2

    # 1.3
    [ "$ENABLE_1_3_1" = "true" ] && fix_1_3_1
    [ "$ENABLE_1_3_2" = "true" ] && fix_1_3_2

    # 1.4
    [ "$ENABLE_1_4_1" = "true" ] && fix_1_4_1
    [ "$ENABLE_1_4_2" = "true" ] && fix_1_4_2
    [ "$ENABLE_1_4_3" = "true" ] && fix_1_4_3

    # 1.5
    [ "$ENABLE_1_5_1" = "true" ] && fix_1_5_1
    [ "$ENABLE_1_5_2" = "true" ] && fix_1_5_2
    [ "$ENABLE_1_5_3" = "true" ] && fix_1_5_3
    [ "$ENABLE_1_5_4" = "true" ] && fix_1_5_4

    # 1.6
    [ "$ENABLE_1_6_1_1" = "true" ] && fix_1_6_1_1
    [ "$ENABLE_1_6_1_2" = "true" ] && fix_1_6_1_2
    [ "$ENABLE_1_6_1_3" = "true" ] && fix_1_6_1_3
    [ "$ENABLE_1_6_1_4" = "true" ] && fix_1_6_1_4

    # 1.7
    [ "$ENABLE_1_7_1" = "true" ] && fix_1_7_banner "/etc/motd"      "1.7.1"
    [ "$ENABLE_1_7_2" = "true" ] && fix_1_7_banner "/etc/issue.net" "1.7.2"
    [ "$ENABLE_1_7_3" = "true" ] && fix_1_7_banner "/etc/issue"     "1.7.3"
    [ "$ENABLE_1_7_4" = "true" ] && fix_1_7_perm   "/etc/motd"      "644" "1.7.4"
    [ "$ENABLE_1_7_5" = "true" ] && fix_1_7_perm   "/etc/issue"     "644" "1.7.5"
    [ "$ENABLE_1_7_6" = "true" ] && fix_1_7_perm   "/etc/issue.net" "644" "1.7.6"

    # 2. 服务
    [ "$ENABLE_2_1_1" = "true" ]  && fix_pkg_remove "xinetd"            "2.1.1"
    [ "$ENABLE_2_1_2" = "true" ]  && fix_pkg_remove "openbsd-inetd"     "2.1.2"
    [ "$ENABLE_2_2_1" = "true" ]  && fix_2_2_1
    [ "$ENABLE_2_2_2" = "true" ]  && fix_pkg_remove "xserver-xorg"      "2.2.2"
    [ "$ENABLE_2_2_3" = "true" ]  && fix_pkg_remove "avahi-daemon"      "2.2.3"
    [ "$ENABLE_2_2_4" = "true" ]  && fix_pkg_remove "cups"              "2.2.4"
    [ "$ENABLE_2_2_5" = "true" ]  && fix_pkg_remove "isc-dhcp-server"   "2.2.5"
    [ "$ENABLE_2_2_6" = "true" ]  && fix_pkg_remove "slapd"             "2.2.6"
    [ "$ENABLE_2_2_7" = "true" ]  && fix_pkg_remove "nfs-kernel-server" "2.2.7"
    [ "$ENABLE_2_2_8" = "true" ]  && fix_pkg_remove "bind9"             "2.2.8"
    [ "$ENABLE_2_2_9" = "true" ]  && fix_pkg_remove "vsftpd"            "2.2.9"
    [ "$ENABLE_2_2_10" = "true" ] && fix_pkg_remove "apache2"           "2.2.10"
    [ "$ENABLE_2_2_11" = "true" ] && fix_pkg_remove "dovecot-imapd"     "2.2.11"
    [ "$ENABLE_2_2_12" = "true" ] && fix_pkg_remove "samba"             "2.2.12"
    [ "$ENABLE_2_2_13" = "true" ] && fix_pkg_remove "squid"             "2.2.13"
    [ "$ENABLE_2_2_14" = "true" ] && fix_pkg_remove "snmpd"             "2.2.14"
    [ "$ENABLE_2_2_15" = "true" ] && fix_pkg_remove "rsync"             "2.2.15"
    [ "$ENABLE_2_2_16" = "true" ] && fix_pkg_remove "nis"               "2.2.16"
    [ "$ENABLE_2_3_1" = "true" ]  && fix_pkg_remove "ypbind"            "2.3.1"
    [ "$ENABLE_2_3_2" = "true" ]  && fix_pkg_remove "rsh-client"        "2.3.2"
    [ "$ENABLE_2_3_3" = "true" ]  && fix_pkg_remove "talk"              "2.3.3"
    [ "$ENABLE_2_3_4" = "true" ]  && fix_pkg_remove "telnet"            "2.3.4"
    [ "$ENABLE_2_3_5" = "true" ]  && fix_pkg_remove "ldap-utils"        "2.3.5"
    [ "$ENABLE_2_3_6" = "true" ]  && fix_pkg_remove "rpcbind"           "2.3.6"

    # 3. 网络
    [ "$ENABLE_3_1_1" = "true" ] && { fix_sysctl "net.ipv4.ip_forward" "0" "3.1.1"; fix_sysctl "net.ipv6.conf.all.forwarding" "0" "3.1.1"; }
    [ "$ENABLE_3_1_2" = "true" ] && { fix_sysctl "net.ipv4.conf.all.send_redirects" "0" "3.1.2"; fix_sysctl "net.ipv4.conf.default.send_redirects" "0" "3.1.2"; }
    [ "$ENABLE_3_2_1" = "true" ] && { fix_sysctl "net.ipv4.conf.all.accept_source_route" "0" "3.2.1"; fix_sysctl "net.ipv6.conf.all.accept_source_route" "0" "3.2.1"; }
    [ "$ENABLE_3_2_2" = "true" ] && { fix_sysctl "net.ipv4.conf.all.accept_redirects" "0" "3.2.2"; fix_sysctl "net.ipv4.conf.default.accept_redirects" "0" "3.2.2"; fix_sysctl "net.ipv6.conf.all.accept_redirects" "0" "3.2.2"; }
    [ "$ENABLE_3_2_3" = "true" ] && { fix_sysctl "net.ipv4.conf.all.secure_redirects" "0" "3.2.3"; fix_sysctl "net.ipv4.conf.default.secure_redirects" "0" "3.2.3"; }
    [ "$ENABLE_3_2_4" = "true" ] && { fix_sysctl "net.ipv4.conf.all.log_martians" "1" "3.2.4"; fix_sysctl "net.ipv4.conf.default.log_martians" "1" "3.2.4"; }
    [ "$ENABLE_3_2_5" = "true" ] && fix_sysctl "net.ipv4.icmp_echo_ignore_broadcasts" "1" "3.2.5"
    [ "$ENABLE_3_2_6" = "true" ] && fix_sysctl "net.ipv4.icmp_ignore_bogus_error_responses" "1" "3.2.6"
    [ "$ENABLE_3_2_7" = "true" ] && { fix_sysctl "net.ipv4.conf.all.rp_filter" "1" "3.2.7"; fix_sysctl "net.ipv4.conf.default.rp_filter" "1" "3.2.7"; }
    [ "$ENABLE_3_2_8" = "true" ] && fix_sysctl "net.ipv4.tcp_syncookies" "1" "3.2.8"
    [ "$ENABLE_3_2_9" = "true" ] && { fix_sysctl "net.ipv6.conf.all.accept_ra" "0" "3.2.9"; fix_sysctl "net.ipv6.conf.default.accept_ra" "0" "3.2.9"; }
    [ "$ENABLE_3_3_1" = "true" ] && { fix_sysctl "net.ipv6.conf.all.disable_ipv6" "1" "3.3.1"; fix_sysctl "net.ipv6.conf.default.disable_ipv6" "1" "3.3.1"; }
    [ "$ENABLE_3_4_1" = "true" ] && fix_proto_disable "dccp" "3.4.1"
    [ "$ENABLE_3_4_2" = "true" ] && fix_proto_disable "sctp" "3.4.2"
    [ "$ENABLE_3_4_3" = "true" ] && fix_proto_disable "rds"  "3.4.3"
    [ "$ENABLE_3_4_4" = "true" ] && fix_proto_disable "tipc" "3.4.4"
    [ "$ENABLE_3_5_1_1" = "true" ] && fix_3_5_1_1
    [ "$ENABLE_3_5_1_2" = "true" ] && fix_3_5_1_2
    [ "$ENABLE_3_5_1_3" = "true" ] && fix_3_5_1_3
    [ "$ENABLE_3_5_1_4" = "true" ] && fix_3_5_1_4
    [ "$ENABLE_3_5_1_5" = "true" ] && fix_3_5_1_5

    # 4. auditd
    [ "$ENABLE_4_1_1_1" = "true" ] && fix_4_1_1_1
    [ "$ENABLE_4_1_1_2" = "true" ] && fix_4_1_1_2
    [ "$ENABLE_4_1_1_3" = "true" ] && fix_4_1_1_3
    [ "$ENABLE_4_1_1_4" = "true" ] && fix_4_1_1_4
    # 一次性写入所有审计规则
    if [[ "$ENABLE_4_1_2_1" = "true" || "$ENABLE_4_1_2_2" = "true" || "$ENABLE_4_1_2_3" = "true" || \
          "$ENABLE_4_1_2_4" = "true" || "$ENABLE_4_1_2_5" = "true" || "$ENABLE_4_1_2_6" = "true" || \
          "$ENABLE_4_1_2_7" = "true" || "$ENABLE_4_1_2_8" = "true" || "$ENABLE_4_1_2_9" = "true" || \
          "$ENABLE_4_1_2_10" = "true" || "$ENABLE_4_1_2_11" = "true" || "$ENABLE_4_1_2_12" = "true" || \
          "$ENABLE_4_1_2_13" = "true" || "$ENABLE_4_1_2_14" = "true" ]]; then
        fix_4_1_2_all
    fi
    [ "$ENABLE_4_1_3_1" = "true" ] && fix_4_1_3_1
    [ "$ENABLE_4_1_3_2" = "true" ] && fix_4_1_3_2
    [ "$ENABLE_4_1_3_3" = "true" ] && fix_4_1_3_3
    [ "$ENABLE_4_2_1_1" = "true" ] && fix_4_2_1_1
    [ "$ENABLE_4_2_1_2" = "true" ] && fix_4_2_1_2
    [ "$ENABLE_4_2_1_3" = "true" ] && fix_4_2_1_3
    [ "$ENABLE_4_2_1_4" = "true" ] && fix_4_2_1_4
    [ "$ENABLE_4_2_2_1" = "true" ] && fix_4_2_2_1
    [ "$ENABLE_4_2_2_2" = "true" ] && fix_4_2_2_2
    [ "$ENABLE_4_2_3" = "true" ]   && fix_4_2_3

    # 5. 访问控制
    [ "$ENABLE_5_1_1" = "true" ] && fix_5_1_1
    [ "$ENABLE_5_1_2" = "true" ] && fix_cron_perm "/etc/crontab"      "600" "5.1.2"
    [ "$ENABLE_5_1_3" = "true" ] && fix_cron_perm "/etc/cron.hourly"  "700" "5.1.3"
    [ "$ENABLE_5_1_4" = "true" ] && fix_cron_perm "/etc/cron.daily"   "700" "5.1.4"
    [ "$ENABLE_5_1_5" = "true" ] && fix_cron_perm "/etc/cron.weekly"  "700" "5.1.5"
    [ "$ENABLE_5_1_6" = "true" ] && fix_cron_perm "/etc/cron.monthly" "700" "5.1.6"
    [ "$ENABLE_5_1_7" = "true" ] && fix_cron_perm "/etc/cron.d"       "700" "5.1.7"
    [ "$ENABLE_5_1_8" = "true" ] && fix_5_1_8
    [ "$ENABLE_5_2_1" = "true" ]  && fix_5_2_1
    [ "$ENABLE_5_2_2" = "true" ]  && fix_5_2_2
    [ "$ENABLE_5_2_3" = "true" ]  && fix_5_2_3
    [ "$ENABLE_5_2_4" = "true" ]  && fix_ssh_option "Protocol"                  "2"              "5.2.4"
    [ "$ENABLE_5_2_5" = "true" ]  && fix_ssh_option "MaxAuthTries"              "4"              "5.2.5"
    [ "$ENABLE_5_2_6" = "true" ]  && fix_ssh_option "IgnoreRhosts"              "yes"            "5.2.6"
    [ "$ENABLE_5_2_7" = "true" ]  && fix_ssh_option "HostbasedAuthentication"   "no"             "5.2.7"
    [ "$ENABLE_5_2_8" = "true" ]  && fix_ssh_option "PermitRootLogin"           "no"             "5.2.8"
    [ "$ENABLE_5_2_9" = "true" ]  && fix_ssh_option "PermitEmptyPasswords"      "no"             "5.2.9"
    [ "$ENABLE_5_2_10" = "true" ] && fix_ssh_option "PermitUserEnvironment"     "no"             "5.2.10"
    [ "$ENABLE_5_2_13" = "true" ] && fix_ssh_option "LoginGraceTime"            "60"             "5.2.13"
    [ "$ENABLE_5_2_14" = "true" ] && fix_ssh_option "Banner"                    "/etc/issue.net" "5.2.14"
    [ "$ENABLE_5_2_15" = "true" ] && fix_ssh_option "UsePAM"                    "yes"            "5.2.15"
    [ "$ENABLE_5_2_16" = "true" ] && fix_ssh_option "AllowTcpForwarding"        "no"             "5.2.16"
    [ "$ENABLE_5_2_17" = "true" ] && fix_ssh_option "MaxStartups"               "10:30:60"       "5.2.17"
    [ "$ENABLE_5_2_18" = "true" ] && fix_ssh_option "MaxSessions"               "4"              "5.2.18"
    [ "$ENABLE_5_2_19" = "true" ] && fix_ssh_option "X11Forwarding"             "no"             "5.2.19"
    [ "$ENABLE_5_2_20" = "true" ] && { fix_ssh_option "ClientAliveInterval" "300" "5.2.20"; fix_ssh_option "ClientAliveCountMax" "3" "5.2.20"; }
    systemctl restart sshd 2>/dev/null || true
    [ "$ENABLE_5_3_1" = "true" ]  && fix_5_3_1
    [ "$ENABLE_5_3_2" = "true" ]  && fix_5_3_2
    [ "$ENABLE_5_3_3" = "true" ]  && fix_5_3_3
    [ "$ENABLE_5_3_4" = "true" ]  && fix_5_3_4
    [ "$ENABLE_5_4_1" = "true" ]  && fix_login_defs "PASS_MAX_DAYS" "365" "5.4.1"
    [ "$ENABLE_5_4_2" = "true" ]  && fix_login_defs "PASS_MIN_DAYS" "1"   "5.4.2"
    [ "$ENABLE_5_4_3" = "true" ]  && fix_login_defs "PASS_WARN_AGE" "7"   "5.4.3"
    [ "$ENABLE_5_4_4" = "true" ]  && fix_5_4_4
    [ "$ENABLE_5_4_5" = "true" ]  && fix_5_4_5
    [ "$ENABLE_5_4_6" = "true" ]  && fix_5_4_6
    [ "$ENABLE_5_4_7" = "true" ]  && fix_5_4_7
    [ "$ENABLE_5_4_8" = "true" ]  && fix_5_4_8
    [ "$ENABLE_5_5_1" = "true" ]  && fix_5_5_1
    [ "$ENABLE_5_5_2" = "true" ]  && fix_5_5_2
    [ "$ENABLE_5_5_3" = "true" ]  && fix_5_5_3
    [ "$ENABLE_5_5_4" = "true" ]  && fix_5_5_4

    # 6. 文件权限
    [ "$ENABLE_6_1_1" = "true" ]  && fix_6_1_1
    [ "$ENABLE_6_1_2" = "true" ]  && fix_file_perm "/etc/passwd"   "644" "6.1.2"
    [ "$ENABLE_6_1_3" = "true" ]  && fix_file_perm "/etc/passwd-"  "644" "6.1.3"
    [ "$ENABLE_6_1_4" = "true" ]  && fix_file_perm "/etc/shadow"   "640" "6.1.4"
    [ "$ENABLE_6_1_5" = "true" ]  && fix_file_perm "/etc/shadow-"  "640" "6.1.5"
    [ "$ENABLE_6_1_6" = "true" ]  && fix_file_perm "/etc/group"    "644" "6.1.6"
    [ "$ENABLE_6_1_7" = "true" ]  && fix_file_perm "/etc/group-"   "644" "6.1.7"
    [ "$ENABLE_6_1_8" = "true" ]  && fix_file_perm "/etc/gshadow"  "640" "6.1.8"
    [ "$ENABLE_6_1_9" = "true" ]  && fix_file_perm "/etc/gshadow-" "640" "6.1.9"
    [ "$ENABLE_6_1_10" = "true" ] && fix_6_1_10
    [ "$ENABLE_6_1_11" = "true" ] && fix_6_1_11
    [ "$ENABLE_6_1_12" = "true" ] && fix_6_1_12
    [ "$ENABLE_6_2_1" = "true" ]  && fix_6_2_1
    [ "$ENABLE_6_2_2" = "true" ]  && fix_6_2_2
    [ "$ENABLE_6_2_3" = "true" ]  && fix_6_2_3
    [ "$ENABLE_6_2_4" = "true" ]  && fix_6_2_4
    [ "$ENABLE_6_2_5" = "true" ]  && fix_6_2_5
    [ "$ENABLE_6_2_6" = "true" ]  && fix_6_2_6
    [ "$ENABLE_6_2_7" = "true" ]  && fix_6_2_7
    [ "$ENABLE_6_2_8" = "true" ]  && fix_6_2_8
    [ "$ENABLE_6_2_9" = "true" ]  && fix_6_2_9
    [ "$ENABLE_6_2_10" = "true" ] && fix_6_2_10
    [ "$ENABLE_6_2_11" = "true" ] && fix_dot_file ".forward" "6.2.11"
    [ "$ENABLE_6_2_12" = "true" ] && fix_dot_file ".netrc"   "6.2.12"
    [ "$ENABLE_6_2_13" = "true" ] && fix_dot_file ".rhosts"  "6.2.13"
    [ "$ENABLE_6_2_14" = "true" ] && fix_6_2_14
    [ "$ENABLE_6_2_15" = "true" ] && fix_6_2_15

    # 应用所有 sysctl 参数
    sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1 && log_fix "所有 sysctl 参数已应用"
}

# =============================================================================
# ---- 汇总报告 ----
# =============================================================================
print_summary() {
    local phase="$1"
    log "\n${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    log "${BOLD}${BLUE}  $phase 审计汇总${NC}"
    log "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    log "${GREEN}  ✅ PASS（合规）  : $PASS_RESULTS${NC}"
    log "${RED}  ❌ FAIL（不合规）: $FAIL_RESULTS${NC}"
    log "${YELLOW}  ⏭  SKIP（跳过）  : $SKIP_RESULTS${NC}"
    local total=$((PASS_RESULTS + FAIL_RESULTS))
    [ "$total" -gt 0 ] && log "${BOLD}  📊 合规率        : $(( PASS_RESULTS * 100 / total ))%${NC}"
}

# =============================================================================
# ---- 主流程 ----
# =============================================================================
main() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║      CIS Debian Linux 13 Benchmark v1.0.0                ║"
    echo "  ║      完整硬化脚本（审计 → 修复 → 验证）                  ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  开始时间 : $(date)"
    echo "  日志文件 : $LOG_FILE"
    echo "  备份目录 : $BACKUP_DIR"
    echo ""

    check_root
    mkdir -p "$BACKUP_DIR"
    touch "$SYSCTL_FILE"
    touch "$LOG_FILE"

    # ---- Step 1: 预审计 ----
    run_audit "pre"
    print_summary "预审计"
    PRE_FAIL=$FAIL_RESULTS

    echo ""
    echo -e "${YELLOW}预审计完成。发现 $PRE_FAIL 项不合规。按 Enter 开始修复...${NC}"
    read -r

    # ---- Step 2: 执行修复 ----
    run_fixes
    log "\n${CYAN}[INFO] 本次修复执行了 $FIXED_RESULTS 项修正${NC}"

    echo ""
    echo -e "${YELLOW}修复完成。按 Enter 开始后审计验证...${NC}"
    read -r

    # ---- Step 3: 后审计 ----
    PASS_RESULTS=0; FAIL_RESULTS=0; SKIP_RESULTS=0
    run_audit "post"
    print_summary "后审计"
    POST_FAIL=$FAIL_RESULTS

    # ---- Step 4: 二次修正（如仍有失败项）----
    if [ "$POST_FAIL" -gt 0 ]; then
        log "\n${YELLOW}后审计仍有 $POST_FAIL 项不合规，尝试二次修正...${NC}"
        run_fixes
        PASS_RESULTS=0; FAIL_RESULTS=0; SKIP_RESULTS=0
        run_audit "post2"
        print_summary "二次修正后审计"
        FINAL_FAIL=$FAIL_RESULTS
    else
        FINAL_FAIL=0
    fi

    # ---- 最终汇总 ----
    log_section "🏁 硬化完成汇总"
    log "  执行时间     : $(date)"
    log "  日志文件     : $LOG_FILE"
    log "  备份目录     : $BACKUP_DIR"
    log "  预审计失败   : $PRE_FAIL 项"
    log "  后审计失败   : $POST_FAIL 项"
    log "  最终失败     : $FINAL_FAIL 项"

    if [ "$FINAL_FAIL" -eq 0 ]; then
        log "\n${GREEN}${BOLD}  🎉 所有启用的 CIS 检查项已通过！${NC}"
    else
        log "\n${YELLOW}  ⚠ 仍有 $FINAL_FAIL 项需要手动处理（如密码设置、磁盘分区等）${NC}"
        log "  ${YELLOW}  请查看日志文件了解详情: $LOG_FILE${NC}"
    fi

    log "\n${BOLD}  📋 建议后续操作：${NC}"
    log "  1. 重启系统使内核参数和文件系统选项完全生效"
    log "  2. 重启后确认 SSH 可以正常登录（避免锁机）"
    log "  3. 使用 Lynis 进行全面合规扫描: apt install lynis && lynis audit system"
    log "  4. 定期运行 AIDE 完整性检查: /usr/bin/aide --check"
    log "  5. 查看防火墙规则确认业务端口已放行: ufw status verbose"
    log ""
}

main
