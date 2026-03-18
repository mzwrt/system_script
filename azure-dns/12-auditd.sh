cat > /etc/audit/rules.d/99-dns-pci.rules << 'EOF'
# PCI-DSS 10.2 — 记录所有管理员行为
-a always,exit -F arch=b64 -S execve -F uid=0 -k admin_cmds
-a always,exit -F arch=b64 -S execve -F euid=0 -k admin_cmds

# 配置文件变更
-w /etc/unbound/ -p wa -k unbound_config
-w /etc/nftables.conf -p wa -k firewall_change
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers

# 系统调用审计
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b64 -S clock_settime -k time_change
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k hostname_change

# 登录事件
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/utmp -p wa -k session

# 提权
-w /bin/su -p x -k priv_escalation
-w /usr/bin/sudo -p x -k priv_escalation

# 不可变（所有规则加载后锁定）
-e 2
EOF

augenrules --load
systemctl restart auditd
