# 安装 irqbalance
apt install -y irqbalance

# 配置：Azure VM 的网卡中断绑定到所有可用 CPU
cat > /etc/default/irqbalance << 'EOF'
ENABLED=1
ONESHOT=0
# 将网络中断分散到两个核心
OPTIONS="--powerthresh=0 --deepestcache=2"
EOF

systemctl enable --now irqbalance
