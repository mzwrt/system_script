# ══ 修复脚本 ══════════════════════════════════════════════
cat > /usr/local/bin/network-tuning.sh << 'TUNING_EOF'
#!/bin/bash
set -e
IFACE="eth0"
NCPU=$(nproc)
CPU_MASK=$(python3 -c "print(hex((1 << $NCPU) - 1).replace('0x',''))")

echo "[network-tuning] 开始: IFACE=${IFACE} CPU=${NCPU} MASK=${CPU_MASK}"

# ── RPS（接收包软件分发）──────────────────────────────────
RX_QUEUES=$(ls /sys/class/net/${IFACE}/queues/ 2>/dev/null | grep -c "^rx-" || echo 0)
echo "[network-tuning] 检测到 RX 队列数: ${RX_QUEUES}"

if [ "$RX_QUEUES" -gt 0 ]; then
    for rx in /sys/class/net/${IFACE}/queues/rx-*; do
        echo "$CPU_MASK" > "$rx/rps_cpus"    && echo "  rps_cpus   → $rx"
        echo "8192"      > "$rx/rps_flow_cnt" && echo "  rps_flow_cnt → $rx"
    done
else
    echo "[network-tuning] 无 RX 队列，跳过 RPS 配置"
fi

# ── RFS（正确的 sysctl 节点）────────────────────────────────
# 注意：节点名是 rps_sock_flow_entries，不是 rfs_entries
RFS_PATH="/proc/sys/net/core/rps_sock_flow_entries"
if [ -f "$RFS_PATH" ]; then
    echo 16384 > "$RFS_PATH"
    echo "[network-tuning] rps_sock_flow_entries = 16384"
else
    echo "[network-tuning] rps_sock_flow_entries 不存在（内核未启用 RFS，跳过）"
fi

# ── fq qdisc（配合 BBR）──────────────────────────────────
if tc qdisc replace dev ${IFACE} root fq 2>/dev/null; then
    echo "[network-tuning] fq qdisc 已设置"
else
    echo "[network-tuning] fq qdisc 设置失败（非致命，跳过）"
fi

# ── 网卡 Offload ──────────────────────────────────────────
if ethtool -K ${IFACE} gro on gso on tso on 2>/dev/null; then
    echo "[network-tuning] offload 已启用"
else
    echo "[network-tuning] offload 设置失败（驱动不支持，跳过）"
fi

echo "[network-tuning] 全部完成"
TUNING_EOF

chmod +x /usr/local/bin/network-tuning.sh

# 查看当前队列深度
ethtool -g eth0 2>/dev/null

# 若支持，增大 RX/TX ring buffer
ethtool -G eth0 rx 4096 tx 4096 2>/dev/null || \
    echo "该网卡驱动不支持调整 ring buffer（Azure hv_netvsc 正常）"

# 开启网卡 GRO/GSO（减少中断次数）
ethtool -K eth0 gro on gso on tso on 2>/dev/null
ethtool -K eth0 rx-checksumming on tx-checksumming on 2>/dev/null

# ══ 同步修复 sysctl 配置（使用正确的参数名）══════════════
# 把之前写错的 rfs_entries 改为正确名称
sed -i 's/^net\.core\.rfs_entries.*/net.core.rps_sock_flow_entries = 16384/' \
    /etc/sysctl.d/99-b2ats-1gb-tuning.conf

# 确认
grep "rps_sock" /etc/sysctl.d/99-b2ats-1gb-tuning.conf

# ══ 重新加载 sysctl ═══════════════════════════════════════
sysctl --system 2>&1 | grep -E "rps_sock|error" || true

# ══ 重启服务验证 ══════════════════════════════════════════
systemctl daemon-reload
systemctl restart network-tuning.service
sleep 1
systemctl status network-tuning.service --no-pager -l
