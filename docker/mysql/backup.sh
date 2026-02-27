#!/bin/bash
# ══════════════════════════════════════════════════════════
# MySQL 自动备份脚本
# 建议 crontab：0 2 * * * /opt/mysql-prod/backup.sh >> /opt/mysql-prod/logs/backup.log 2>&1
# ══════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
BACKUP_DIR="$SCRIPT_DIR/backup"
DATE=$(date +%Y%m%d_%H%M%S)
CONTAINER="mysql-prod"
KEEP_DAYS=7        # 保留最近7天的备份
LOG_TAG="[MySQL-Backup]"

# 加载环境变量
if [[ ! -f "$ENV_FILE" ]]; then
  echo "$LOG_TAG ❌ .env 文件不存在: $ENV_FILE" >&2
  exit 1
fi
source "$ENV_FILE"

mkdir -p "$BACKUP_DIR"

# 检查容器健康状态
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "missing")
if [[ "$HEALTH" != "healthy" ]]; then
  echo "$LOG_TAG ❌ 容器 $CONTAINER 状态异常（$HEALTH），跳过本次备份" >&2
  exit 1
fi

BACKUP_FILE="$BACKUP_DIR/appdb_${DATE}.sql.gz"

echo "$LOG_TAG 开始备份 appdb -> $BACKUP_FILE"

# mysqldump + gzip 压缩，直接写入宿主机
docker exec "$CONTAINER" mysqldump \
  -u root \
  -p"${MYSQL_ROOT_PASSWORD}" \
  --ssl-ca=/etc/mysql/certs/ca-cert.pem \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  --hex-blob \
  --set-gtid-purged=OFF \
  appdb | gzip -9 > "$BACKUP_FILE"

# 验证备份文件非空
BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || echo 0)
if [[ "$BACKUP_SIZE" -lt 100 ]]; then
  echo "$LOG_TAG ❌ 备份文件异常，大小仅 ${BACKUP_SIZE} 字节" >&2
  rm -f "$BACKUP_FILE"
  exit 1
fi

echo "$LOG_TAG ✅ 备份成功，大小：$(du -sh "$BACKUP_FILE" | cut -f1)"

# 清理超期备份
DELETED=$(find "$BACKUP_DIR" -name "appdb_*.sql.gz" -mtime +${KEEP_DAYS} -print -delete | wc -l)
[[ "$DELETED" -gt 0 ]] && echo "$LOG_TAG 已清理 ${DELETED} 个过期备份"

echo "$LOG_TAG 完成 $(date '+%Y-%m-%d %H:%M:%S')"
