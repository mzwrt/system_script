-- ══════════════════════════════════════════════════════════
-- MySQL 8.4 LTS CIS 安全初始化
-- ══════════════════════════════════════════════════════════

-- ── MySQL 8.4 安装 validate_password 组件 ─────────────────
-- 8.0 旧方式（8.4已废弃）：INSTALL PLUGIN validate_password SONAME ...
-- 8.4 新方式：
INSTALL COMPONENT 'file://component_validate_password';

-- ── 组件安装后立即配置密码策略（CIS 7.x）─────────────────
-- 这些变量必须在组件安装后才能设置，不能写在 my.cnf 里
SET GLOBAL validate_password.policy        = 'STRONG';
SET GLOBAL validate_password.length        = 14;
SET GLOBAL validate_password.mixed_case_count = 1;
SET GLOBAL validate_password.number_count    = 1;
SET GLOBAL validate_password.special_char_count = 1;

-- ── CIS 5.1 删除匿名账号 ──────────────────────────────────
DELETE FROM mysql.user WHERE User = '';

-- ── CIS 5.2 删除远程 root ─────────────────────────────────
DELETE FROM mysql.user
WHERE User = 'root'
  AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- ── CIS 5.3 删除默认 test 库 ──────────────────────────────
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db = 'test' OR Db = 'test\\_%';

FLUSH PRIVILEGES;

-- ── 业务数据库 ────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS `appdb`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- ── 应用账号：最小权限 + 强制TLS ──────────────────────────
CREATE USER IF NOT EXISTS 'appdb'@'%'
  IDENTIFIED WITH caching_sha2_password
  BY 'appdb'
  REQUIRE SSL
  PASSWORD EXPIRE INTERVAL 90 DAY
  FAILED_LOGIN_ATTEMPTS 5
  PASSWORD_LOCK_TIME 2;

GRANT
  SELECT, INSERT, UPDATE, DELETE,
  CREATE, DROP, INDEX, ALTER,
  CREATE TEMPORARY TABLES,
  LOCK TABLES, REFERENCES, TRIGGER
ON `appdb`.* TO 'appdb'@'%';

-- ── 只读账号 ──────────────────────────────────────────────
CREATE USER IF NOT EXISTS 'miiiiii'@'%'
  IDENTIFIED WITH caching_sha2_password
  BY 'miiiiii'
  REQUIRE SSL
  PASSWORD EXPIRE INTERVAL 90 DAY
  FAILED_LOGIN_ATTEMPTS 5
  PASSWORD_LOCK_TIME 2;

GRANT SELECT, SHOW VIEW, LOCK TABLES
  ON `miiiiii`.* TO 'miiiiii'@'%';

-- ── 监控账号 ──────────────────────────────────────────────
CREATE USER IF NOT EXISTS 'monitor'@'localhost'
  IDENTIFIED WITH caching_sha2_password
  BY 'CHANGE_THIS_MONITOR_PASSWORD'
  PASSWORD EXPIRE INTERVAL 180 DAY
  FAILED_LOGIN_ATTEMPTS 10
  PASSWORD_LOCK_TIME 1;

GRANT PROCESS, REPLICATION CLIENT
  ON *.* TO 'monitor'@'localhost';

FLUSH PRIVILEGES;
