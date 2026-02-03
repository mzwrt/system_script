#!/bin/bash
# OWASP核心规则集下载-start 
# 下载 owasp 源码最新稳定版本
mkdir -p "$OPT_DIR/owasp"
chown -R "root:root $OPT_DIR/owasp"
# OWASP核心规则集下载 
cd "$OPT_DIR/owasp"

owasp_VERSION_NO_V="${owasp_VERSION//v}"
owasp_DOWNLOAD_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/$owasp_VERSION.tar.gz"

echo "正在下载最新版本：$owasp_VERSION"
if curl -L --retry 5 --retry-delay 2 --retry-connrefused -o "coreruleset-$owasp_VERSION.tar.gz" "$owasp_DOWNLOAD_URL"; then
    echo "下载完成：coreruleset-$owasp_VERSION.tar.gz"

    # 解压并检查
    tar -zxf "coreruleset-$owasp_VERSION.tar.gz"
    if [ ! -d "coreruleset-$owasp_VERSION_NO_V" ]; then
        echo "未能找到目录 coreruleset-$owasp_VERSION_NO_V，无法重命名。"
        exit 1
    fi

    # 备份旧配置
    if [ -f "$OPT_DIR/owasp/owasp-rules/crs-setup.conf" ]; then
        cp -f "$OPT_DIR/owasp/owasp-rules/crs-setup.conf" "/tmp/crs-setup.conf"
    fi

    # 删除旧规则目录
    rm -rf "$OPT_DIR/owasp/owasp-rules"

    # 移动新规则
    mv -f "coreruleset-$owasp_VERSION_NO_V" "$OPT_DIR/owasp/owasp-rules"

    # 恢复配置或下载默认配置
    if [ -f "/tmp/crs-setup.conf" ]; then
        cp -f "/tmp/crs-setup.conf" "$OPT_DIR/owasp/owasp-rules/crs-setup.conf"
    else
        wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/owasp-rules/crs-setup.conf" \
        "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/crs-setup.conf"
    fi

    # 设置权限
    chown -R root:root "$OPT_DIR/owasp/owasp-rules"
    chmod 600 "$OPT_DIR/owasp/owasp-rules/crs-setup.conf"

    # 删除压缩包
    rm -f "coreruleset-$owasp_VERSION.tar.gz"
else
    echo "下载最新版本 $owasp_VERSION 失败。"
    exit 1
fi
# OWASP核心规则集下载-END

# 开启 owasp 文件-start
# 创建引入文件
# 修改配置文件名
mkdir -p "$OPT_DIR/owasp/conf"
mkdir -p "$OPT_DIR/owasp/owasp-rules/plugins"

# 添加 WordPress 常用的 Nginx 拒绝规则配置文件
if [ ! -f $OPT_DIR/owasp/conf/nginx-wordpress.conf ]; then
   wget -c -T 20 --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/conf/nginx-wordpress.conf" "https://gist.githubusercontent.com/nfsarmento/57db5abba08b315b67f174cd178bea88/raw/b0768871c3349fdaf549a24268cb01b2be145a6a/nginx-wordpress.conf"
fi

echo "Downloading WordPress 规则排除插件"
# 下载 wordpress-rule-exclusions-before.conf 和 wordpress-rule-exclusions-config.conf 文件
if [ ! -f "$OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf" "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-before.conf"
fi

if [ ! -f "$OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf" "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-config.conf"
fi

# 重命名排除规则样例文件
if [ -f "$OPT_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example" ]; then
  mv "$OPT_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example" "$OPT_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf"
fi
if [ -f "$OPT_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example" ]; then
  mv -f "$OPT_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example" "$OPT_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf"
fi

# 下载 hosts.deny 文件并备份旧文件（如果存在）
echo "Downloading hosts.deny..."
if [ -f "$OPT_DIR/owasp/conf/hosts.deny" ]; then
  mv -f "$OPT_DIR/owasp/conf/hosts.deny" "$OPT_DIR/owasp/conf/hosts.deny.bak"
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/conf/hosts.deny" "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/hosts.deny"

# 下载 hosts.allow 文件并备份旧文件（如果存在）
echo "Downloading hosts.allow..."
if [ -f "$OPT_DIR/owasp/conf/hosts.allow" ]; then
  mv -f "$OPT_DIR/owasp/conf/hosts.allow" "$OPT_DIR/owasp/conf/hosts.allow.bak"
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/conf/hosts.allow" "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/hosts.allow"

# 下载 main.conf 文件并备份旧文件（如果存在）
echo "Downloading main.conf..."
if [ -f "$OPT_DIR/owasp/conf/main.conf" ]; then
  mv -f "$OPT_DIR/owasp/conf/main.conf" "$OPT_DIR/owasp/conf/main.conf.bak"
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$OPT_DIR/owasp/conf/main.conf" "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/main.conf"


# 规范规则文件权限
echo " 规范文件权限"
# 所有 .conf 文件设置为 root 权限 600
find "$OPT_DIR/owasp/conf" -type f -name "*.conf" -exec chmod 600 {} \; -exec chown root:root {} \;
find "$OPT_DIR/owasp/conf" -type f -name "*.conf.bak" -exec chmod 600 {} \; -exec chown root:root {} \;
# 所有文件夹设置为 700
find "$OPT_DIR/owasp" -type d -exec chmod 700 {} \;
chown -R root:root "$OPT_DIR/owasp"

chown -R root:root "$OPT_DIR/owasp/conf/hosts.allow"
chown -R root:root "$OPT_DIR/owasp/conf/hosts.deny"
chmod 600 "$OPT_DIR/owasp/conf/hosts.allow"
chmod 600 "$OPT_DIR/owasp/conf/hosts.deny"
