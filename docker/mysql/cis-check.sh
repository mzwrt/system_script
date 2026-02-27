#!/bin/bash
# ══════════════════════════════════════════════════════════
# CIS MySQL 8.0 Benchmark 自动检查脚本
# 执行：chmod +x cis-check.sh && ./cis-check.sh
# ══════════════════════════════════════════════════════════

set -uo pipefail

CONTAINER="mysql-prod"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"
PASS=0; FAIL=0; WARN=0

source "$ENV_FILE"

# 颜色
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { echo -e "${GREEN}✅ PASS${NC} CIS $1 | $2"; ((PASS++)); }
fail() { echo -e "${RED}❌ FAIL${NC} CIS $1 | $2 | 实际值: $3"; ((FAIL++)); }
warn() { echo -e "${YELLOW}⚠️  WARN${NC} CIS $1 | $2"; ((WARN++)); }

# 执行MySQL查询
q() {
  docker exec "$CONTAINER" mysql \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    --ssl-ca=/etc/mysql/certs/ca-cert.pem \
    -sNe "$1" 2>/dev/null
}

echo "════════════════════════════════════════════════"
echo "  CIS MySQL 8.0 Benchmark 检查 - $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════"
echo ""

# 容器状态检查
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "missing")
if [[ "$HEALTH" == "healthy" ]]; then
  pass "0.0" "容器健康状态 (healthy)"
else
  fail "0.0" "容器健康状态" "$HEALTH"
  echo "容器未就绪，请先启动 MySQL 再运行此检查。"
  exit 1
fi
echo ""

echo "── Section 2: 基础安全配置 ─────────────────────"
v=$(q "SHOW VARIABLES LIKE 'local_infile';" | awk '{print $2}')
[[ "$v" == "OFF" ]] && pass "2.1" "local_infile=OFF" || fail "2.1" "local_infile 应为OFF" "$v"

v=$(q "SHOW VARIABLES LIKE 'skip_grant_tables';" | awk '{print $2}')
[[ "$v" == "OFF" ]] && pass "2.2" "skip_grant_tables=OFF" || fail "2.2" "skip_grant_tables 应为OFF" "$v"

v=$(q "SHOW VARIABLES LIKE 'symbolic_links';" | awk '{print $2}')
[[ "$v" == "OFF" ]] && pass "2.3" "symbolic_links=OFF" || fail "2.3" "symbolic_links 应为OFF" "$v"

v=$(q "SHOW VARIABLES LIKE 'secure_file_priv';" | awk '{print $2}')
[[ -n "$v" && "$v" != "NULL" ]] && pass "2.4" "secure_file_priv 已设置: $v" || fail "2.4" "secure_file_priv 不应为空/NULL" "$v"

v=$(q "SHOW VARIABLES LIKE 'skip_show_database';" | awk '{print $2}')
[[ "$v" == "ON" ]] && pass "2.5" "skip_show_database=ON" || fail "2.5" "skip_show_database 应为ON" "$v"

echo ""
echo "── Section 4: 日志审计 ──────────────────────────"
v=$(q "SHOW VARIABLES LIKE 'log_error';" | awk '{print $2}')
[[ -n "$v" ]] && pass "4.1" "log_error 已配置: $v" || fail "4.1" "log_error 未配置" "$v"

v=$(q "SHOW VARIABLES LIKE 'log_error_verbosity';" | awk '{print $2}')
[[ "$v" -ge 2 ]] 2>/dev/null && pass "4.2" "log_error_verbosity=$v (>=2)" || fail "4.2" "log_error_verbosity 应>=2" "$v"

v=$(q "SHOW VARIABLES LIKE 'slow_query_log';" | awk '{print $2}')
[[ "$v" == "ON" ]] && pass "4.3" "slow_query_log=ON" || fail "4.3" "slow_query_log 应为ON" "$v"

v=$(q "SHOW VARIABLES LIKE 'log_bin';" | awk '{print $2}')
[[ "$v" == "ON" ]] && pass "4.4" "log_bin=ON (binlog开启)" || warn "4.4" "log_bin=$v，建议开启binlog用于灾难恢复"

echo ""
echo "── Section 5: 用户账号安全 ──────────────────────"
v=$(q "SELECT COUNT(*) FROM mysql.user WHERE User='';" )
[[ "$v" == "0" ]] && pass "5.1" "无匿名账号" || fail "5.1" "存在匿名账号，数量" "$v"

v=$(q "SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');")
[[ "$v" == "0" ]] && pass "5.2" "无远程root账号" || fail "5.2" "存在远程root账号，数量" "$v"

v=$(q "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test';")
[[ "$v" == "0" ]] && pass "5.3" "test库已删除" || fail "5.3" "test库仍然存在" "$v"

echo ""
echo "── Section 6: SSL/TLS 传输加密 ──────────────────"
v=$(q "SHOW VARIABLES LIKE 'have_ssl';" | awk '{print $2}')
[[ "$v" == "YES" ]] && pass "6.1" "SSL已启用" || fail "6.1" "SSL未启用" "$v"

v=$(q "SHOW VARIABLES LIKE 'require_secure_transport';" | awk '{print $2}')
[[ "$v" == "ON" ]] && pass "6.2" "require_secure_transport=ON" || fail "6.2" "require_secure_transport 应为ON" "$v"

v=$(q "SHOW VARIABLES LIKE 'tls_version';" | awk '{print $2}')
if echo "$v" | grep -qv "TLSv1\b" && echo "$v" | grep -qv "TLSv1.1"; then
  pass "6.3" "TLS版本安全: $v (无TLS1.0/1.1)"
else
  fail "6.3" "TLS版本包含不安全协议" "$v"
fi

echo ""
echo "── Section 7: 密码策略 ──────────────────────────"
v=$(q "SELECT PLUGIN_STATUS FROM information_schema.PLUGINS WHERE PLUGIN_NAME='validate_password';" 2>/dev/null || echo "NOT_FOUND")
[[ "$v" == "ACTIVE" ]] && pass "7.1" "validate_password 插件已激活" || fail "7.1" "validate_password 插件未激活" "$v"

v=$(q "SHOW VARIABLES LIKE 'validate_password.policy';" | awk '{print $2}')
[[ "$v" == "STRONG" ]] && pass "7.2" "validate_password.policy=STRONG" || fail "7.2" "密码策略应为STRONG" "$v"

v=$(q "SHOW VARIABLES LIKE 'default_password_lifetime';" | awk '{print $2}')
[[ "$v" -gt 0 ]] 2>/dev/null && pass "7.3" "default_password_lifetime=${v}天" || fail "7.3" "密码有效期未设置" "$v"

echo ""
echo "════════════════════════════════════════════════"
printf "  结果：${GREEN}通过 %d${NC} | ${RED}失败 %d${NC} | ${YELLOW}警告 %d${NC}\n" $PASS $FAIL $WARN
echo "════════════════════════════════════════════════"
[[ $FAIL -eq 0 ]] && echo -e "${GREEN}✅ 所有关键检查通过${NC}" || echo -e "${RED}❌ 有检查项未通过，请修复后重新检查${NC}"
