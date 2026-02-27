#!/bin/bash
# ══════════════════════════════════════════════════════════
# MySQL 生产环境一键部署脚本
# 执行前：先修改 .env 中的所有密码 和 init.sql 中的密码
# 执行：chmod +x deploy.sh && ./deploy.sh
# ══════════════════════════════════════════════════════════

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "════════════════════════════════════════════════"
echo "  MySQL 生产环境部署"
echo "════════════════════════════════════════════════"

# ── 1. 检查依赖 ───────────────────────────────────────────
echo ""
echo ">>> 检查环境依赖..."
for cmd in docker openssl; do
  command -v "$cmd" &>/dev/null || { echo -e "${RED}❌ 缺少命令: $cmd${NC}"; exit 1; }
done
docker compose version &>/dev/null || { echo -e "${RED}❌ 需要 Docker Compose V2${NC}"; exit 1; }
echo -e "${GREEN}✅ 依赖检查通过${NC}"

# ── 2. 检查密码是否已修改 ─────────────────────────────────
echo ""
echo ">>> 检查密码配置..."
if grep -q "CHANGE_THIS" .env; then
  echo -e "${RED}❌ .env 中仍有未修改的默认密码（CHANGE_THIS_*）${NC}"
  echo "   请先编辑 .env 文件，将所有密码替换为强密码，再重新运行。"
  exit 1
fi
if grep -q "CHANGE_THIS" init/01-security-init.sql; then
  echo -e "${RED}❌ init/01-security-init.sql 中仍有未修改的默认密码${NC}"
  echo "   请将 CHANGE_THIS_* 替换为与 .env 一致的强密码。"
  exit 1
fi
echo -e "${GREEN}✅ 密码已配置${NC}"

# ── 3. 生成TLS证书（如果不存在）──────────────────────────
echo ""
if [[ ! -f "certs/ca-cert.pem" ]]; then
  echo ">>> 生成TLS证书..."
  bash gen-certs.sh
else
  echo -e "${GREEN}✅ TLS证书已存在，跳过生成${NC}"
fi

# ── 4. 设置目录权限 ───────────────────────────────────────
echo ""
echo ">>> 设置目录权限..."
mkdir -p logs backup
# logs 目录需要容器内 mysql(999) 用户可写
chmod 777 logs
# 保护敏感文件
chmod 600 .env
chmod 700 certs
chmod 400 certs/*-key.pem 2>/dev/null || true
echo -e "${GREEN}✅ 权限设置完成${NC}"

# ── 5. 启动容器 ───────────────────────────────────────────
echo ""
echo ">>> 启动 MySQL 容器..."
docker compose up -d

# ── 6. 等待健康检查通过 ───────────────────────────────────
echo ""
echo ">>> 等待 MySQL 初始化（最多120秒）..."
WAIT=0
until [[ $(docker inspect --format='{{.State.Health.Status}}' mysql-prod 2>/dev/null) == "healthy" ]]; do
  sleep 5
  WAIT=$((WAIT+5))
  echo -n "."
  [[ $WAIT -ge 120 ]] && echo -e "\n${RED}❌ 超时，请查看日志：docker compose logs mysql${NC}" && exit 1
done
echo ""
echo -e "${GREEN}✅ MySQL 已就绪${NC}"

# ── 7. 设置备份定时任务 ───────────────────────────────────
echo ""
echo ">>> 配置自动备份（每天凌晨2点）..."
chmod +x backup.sh cis-check.sh
CRON_JOB="0 2 * * * ${SCRIPT_DIR}/backup.sh >> ${SCRIPT_DIR}/logs/backup.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "backup.sh"; then
  echo -e "${YELLOW}⚠️  备份任务已存在，跳过添加${NC}"
else
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  echo -e "${GREEN}✅ 备份定时任务已添加${NC}"
fi

echo ""
echo "════════════════════════════════════════════════"
echo -e "${GREEN}✅ 部署完成！${NC}"
echo ""
echo "  常用命令："
echo "  查看状态    docker compose ps"
echo "  查看日志    docker compose logs -f mysql"
echo "  进入容器    docker exec -it mysql-prod mysql -u root -p"
echo "  CIS检查     ./cis-check.sh"
echo "  手动备份    ./backup.sh"
echo "════════════════════════════════════════════════"
