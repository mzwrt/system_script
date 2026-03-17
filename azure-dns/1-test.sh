# ══ 确认机型参数 ══════════════════════════════════════════
echo "=== CPU ===" && lscpu | grep -E "Model|CPU\(s\)|Thread|MHz"
echo "=== RAM ===" && free -m
echo "=== 内存详情 ===" && cat /proc/meminfo | grep -E "^MemTotal|^MemFree|^MemAvail|^Swap|^HugePages"
echo "=== 内核 ===" && uname -r
echo "=== 网卡 ===" && ip -brief addr && ethtool eth0 2>/dev/null | grep -E "Speed|driver"
echo "=== 当前服务 ===" && systemctl list-units --type=service --state=running --no-legend | awk '{print $1}'
echo "=== 当前内存占用 ===" && ps aux --sort=-%mem | head -15
echo "=== Nginx 模块 ===" && nginx -V 2>&1 | tr -- ' -' '\n' | grep -v "^$"
echo "=== OWASP CRS 路径 ===" && find /etc /usr/share -name "crs-setup.conf" 2>/dev/null

# 1GB 机器内存分配预算
echo ""
echo "=== 内存预算估算 ==="
python3 << 'PY'
total = 1024  # MB
os_kernel     = 120   # OS + 内核
nginx         = 40    # 2 worker × 20MB
modsec_crs    = 60    # ModSecurity + CRS 规则加载
unbound       = 130   # DNS 缓存 + 进程本身
auditd_misc   = 30    # auditd + chrony + sshd + fail2ban
reserved      = 50    # 突发预留
allocated     = os_kernel + nginx + modsec_crs + unbound + auditd_misc + reserved
print(f"OS/内核:          {os_kernel} MB")
print(f"Nginx (2 worker): {nginx} MB")
print(f"ModSec + CRS:     {modsec_crs} MB")
print(f"Unbound + 缓存:   {unbound} MB")
print(f"系统服务:         {auditd_misc} MB")
print(f"突发预留:         {reserved} MB")
print(f"{'─'*30}")
print(f"已分配合计:       {allocated} MB / {total} MB")
print(f"剩余:             {total - allocated} MB")
PY
