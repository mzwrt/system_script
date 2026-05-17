#!/bin/bash
set -e

echo "🔄 开始整站全量统一划归 www-data 属主..."

SITE_DIR="/www/wwwroot/stiebultar.org"

# 1. 穿透父级目录（确保 www-data 可以进入）
chmod g+x /www /www/wwwroot

# 2. 一键全量更改属主和属组为 www-data
chown -R www-data:www-data "$SITE_DIR"

# 3. 规范目录权限：755（所有者可读写执行，组和其他人只读/可穿透）
find "$SITE_DIR" -type d -exec chmod 755 {} \;

# 4. 规范文件权限：644（所有者可读写，组和其他人严格只读）
find "$SITE_DIR" -type f -exec chmod 644 {} \;

# 5. 核心配置文件特殊保护（虽然属于 www-data，但也只给只读，防意外篡改）
chmod 440 "$SITE_DIR/wp-config.php"

echo "✅ [SUCCESS] 整站已成功统一为 www-data，结构已对齐！"
