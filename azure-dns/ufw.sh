ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward
ufw logging low

# SSH
ufw allow 22/tcp comment 'SSH'

# Nginx
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# DoT（WireGuard 子网，暂不开放公网）
ufw allow from 172.16.1.0/24 to any port 853 proto tcp comment 'DoT-WG'

# DNS（仅本机和 WireGuard，绝不对公网）
ufw allow from 127.0.0.0/8   to any port 53 comment 'DNS-local'
ufw allow from 172.16.1.0/24 to any port 53 comment 'DNS-WG'

# ICMP 速率限制
cat >> /etc/ufw/before.rules << 'UFW_ICMP'

# === 限速 ICMP ===
-A ufw-before-input -p icmp --icmp-type echo-request \
   -m limit --limit 5/s --limit-burst 10 -j ACCEPT
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP
UFW_ICMP

ufw --force enable
ufw status numbered
echo "✓ UFW 配置完成"
