#!/bin/bash
set -euo pipefail

# ----------------------------
# 全局配置
# ----------------------------
SITE_OPT="/opt"
SITE_DIR="$SITE_OPT/nginx"
SITE_CONF_DIR="$SITE_DIR/conf.d/sites-available"
SITE_ENABLED_DIR="$SITE_DIR/conf.d/sites-enabled"
SITE_SSL_BASE_DIR="$SITE_DIR/ssl"
SITE_DHPARAM_FILE="$SITE_SSL_BASE_DIR/dhparam.pem"
SITE_TEMPLATE_URL="https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/example.com.conf"

SITE_NGINX_USER="www-data"
SITE_NGINX_GROUP="www-data"
SITE_NGINX_ROOT="/www"
SITE_NGINX_ROOT_DIR="/www/wwwroot"
SITE_ACME_ACCOUNT_CONF="/root/.acme.sh/account.conf"

# ----------------------------
# acme.sh 检查
# ----------------------------
SITE_ACME_ENV="$HOME/.acme.sh/acme.sh.env"
[ -f "$SITE_ACME_ENV" ] && . "$SITE_ACME_ENV"
export PATH="$HOME/.acme.sh:$PATH"

command -v acme.sh >/dev/null 2>&1 || {
    echo "❌ 未检测到 acme.sh，请先安装"
    read -p "是否要安装 acme.sh？ (y/n): " install_choice
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        read -p "请输入邮箱地址用于注册账户: " user_email
        echo "正在安装 acme.sh..."
        sudo apt update
        sudo apt install -y socat
        wget -O - https://get.acme.sh | sh -s email="$user_email"
        echo "acme.sh 安装完成"
    else
        exit 1
    fi
}

# ----------------------------
# 严格域名验证
# ----------------------------
validate_site_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# ----------------------------
# DH 参数生成（一次性）
# ----------------------------
generate_dhparam() {
    if [ ! -f "$SITE_DHPARAM_FILE" ]; then
        mkdir -p "$(dirname "$SITE_DHPARAM_FILE")"
        echo "正在生成 DH 参数，可能需要几分钟..."
        openssl dhparam -out "$SITE_DHPARAM_FILE" 2048 >/dev/null 2>&1
        chmod 640 "$SITE_DHPARAM_FILE"
        chown root:www-data "$SITE_DHPARAM_FILE"
        echo "✅ DH 参数生成完成：$SITE_DHPARAM_FILE"
    fi
}

# ----------------------------
# DNS 提供商选择
# ----------------------------
SITE_PROVIDER=""
select_dns_site_provider() {
    while true; do
        echo
        echo "请选择 DNS 提供商："
        echo "1) 阿里云"
        echo "2) Cloudflare"
        echo "0) 退出"
        read -r c
        case "$c" in
            1) SITE_PROVIDER="ali"; return ;;
            2) SITE_PROVIDER="cf"; return ;;
            0) exit 0 ;;
            *) echo "❌ 无效选项，请输入 1、2 或 0";;
        esac
    done
}

# ----------------------------
# DNS API 配置
# ----------------------------
setup_dns_api() {
    case "$SITE_PROVIDER" in
        ali)
            if ! grep -q 'Ali_Key' "$SITE_ACME_ACCOUNT_CONF" 2>/dev/null; then
                echo "首次使用阿里云 DNS，请输入 API 密钥"
                #read -r -p "请输入邮箱: " site_account_email
                read -r -p "Ali_Key: " Ali_Key
                read -r -p "Ali_Secret: " Ali_Secret
                export Ali_Key Ali_Secret
                #acme.sh --register-account --accountemail "$site_account_email"
            else
                echo "✅ 阿里云 DNS API 已配置"
            fi
            ;;
        cf)
            if ! grep -q 'CF_Token' "$SITE_ACME_ACCOUNT_CONF" 2>/dev/null; then
                echo "首次使用 Cloudflare DNS，请输入 API 密钥"
                #read -r -p "请输入邮箱: " site_account_email
                read -r -p "CF_Token: " CF_Token
                read -r -p "CF_Account: " CF_Account
                export CF_Token CF_Account
                #acme.sh --register-account --accountemail "$site_account_email"
            else
                echo "✅ Cloudflare DNS API 已配置"
            fi
            ;;
    esac
}

# ----------------------------
# 提取根域名
# ----------------------------
get_root_domain() {
    local DOMAIN="$1"
    # 仅适用于常规域名，例如 sub.example.com -> example.com
    echo "$DOMAIN" | awk -F. '{n=NF; print $(n-1)"."$n}'
}

# ----------------------------
# 证书申请（通配符）
# ----------------------------
declare -A CERT_APPLIED  # 用于记录已申请的根域名

issue_cert_wildcard() {
    local DOMAIN="$1"
    local ROOT_DOMAIN
    ROOT_DOMAIN=$(get_root_domain "$DOMAIN")
    
    if [[ -n "${CERT_APPLIED[$ROOT_DOMAIN]+x}" ]]; then
        echo "✅ 根域名 $ROOT_DOMAIN 已申请通配符证书，跳过"
        return
    fi

    local SSL_DIR="$SITE_SSL_BASE_DIR/$ROOT_DOMAIN"
    mkdir -p "$SSL_DIR"

    echo "📄 正在为根域名 $ROOT_DOMAIN 申请通配符证书..."
    if ! acme.sh --issue -d "*.$ROOT_DOMAIN" -d "$ROOT_DOMAIN" --dns dns_"$SITE_PROVIDER" --keylength ec-256; then
        echo "❌ 证书申请失败：$ROOT_DOMAIN"
        acme.sh --remove -d "*.$ROOT_DOMAIN" -d "$ROOT_DOMAIN" 2>/dev/null || true
        return 1
    fi

    acme.sh --install-cert -d "*.$ROOT_DOMAIN" -d "$ROOT_DOMAIN" \
        --key-file "$SSL_DIR/privkey.pem" \
        --fullchain-file "$SSL_DIR/fullchain.pem" \
        --ca-file "$SSL_DIR/ca.pem" \
        --reloadcmd "systemctl reload nginx"

    find "$SSL_DIR" -type f -exec chmod 640 {} \;

    CERT_APPLIED["$ROOT_DOMAIN"]=1
    echo "✅ 通配符证书申请完成：$ROOT_DOMAIN"
}

# ----------------------------
# Nginx 配置检查
# ----------------------------
nginx_reload() {
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        echo "✅ Nginx 配置检查通过，已重载"
    else
        echo "❌ Nginx 配置有错误，请手动检查"
        nginx -t
    fi
}

# ----------------------------
# 创建网站
# ----------------------------
create_site() {
    local DOMAINS="$1"

    generate_dhparam

    for DOMAIN in $DOMAINS; do
        DOMAIN="${DOMAIN// /}"
        validate_site_domain "$DOMAIN" || { echo "❌ 域名不合法：$DOMAIN"; continue; }

        local WEB_ROOT="$SITE_NGINX_ROOT_DIR/$DOMAIN"
        local CONF_FILE="$SITE_CONF_DIR/$DOMAIN.conf"

        mkdir -p "$WEB_ROOT"
        chown -R "$SITE_NGINX_USER:$SITE_NGINX_GROUP" "$WEB_ROOT"
        mkdir -p "$SITE_CONF_DIR" "$SITE_ENABLED_DIR" "$SITE_SSL_BASE_DIR"
        chmod 750 "$SITE_SSL_BASE_DIR"
        chown -R root:$SITE_NGINX_GROUP "$SITE_SSL_BASE_DIR"
        

        # 下载模板
        if [ ! -f "$CONF_FILE" ]; then
            curl -fsSL "$SITE_TEMPLATE_URL" -o "$CONF_FILE"
            chmod 640 "$CONF_FILE"
            ln -sf "$CONF_FILE" "$SITE_ENABLED_DIR/"
        fi

        # 替换变量
        sed -i \
            -e "s|%DOMAIN%|$DOMAIN|g" \
            -e "s|%WEB_ROOT%|$WEB_ROOT|g" \
            -e "s|%SSL_DIR%|$SITE_SSL_BASE_DIR/$(get_root_domain $DOMAIN)|g" \
            -e "s|%SITE_OPT%|$SITE_OPT|g" \
            "$CONF_FILE"

            
## 因为前面文件权限配置错误，这里修正权限，
## 1. 修正路径笔误：精准在 /opt/nginx/logs 内部创建 7 个缓存和临时目录
mkdir -p "$SITE_DIR/logs/uwsgi_temp" \
             "$SITE_DIR/logs/client_body_temp" \
             "$SITE_DIR/logs/scgi_temp" \
             "$SITE_DIR/logs/fastcgi_temp" \
             "$SITE_DIR/logs/nginx-fastcgi-cache" \
             "$SITE_DIR/logs/proxy_temp_dir" \
             "$SITE_DIR/logs/proxy_cache_dir" \
             "$SITE_DIR/logs/modsec_tmp" \
             "$SITE_DIR/logs/modsec_data" \
             "$SITE_CONF_DIR" "$SITE_ENABLED_DIR" "$SITE_SSL_BASE_DIR"

# 1. 强行创建专门收拢在 logs 下的 Modsec 读写特区
mkdir -p /opt/nginx/logs/modsec_tmp /opt/nginx/logs/modsec_data
touch /opt/nginx/logs/modsec_audit.log /opt/nginx/logs/modsec_debug.log

# 2. 批量微雕读写特区的权限，确保 www-data 组有权写入，root 拥有所有权
chown -R root:www-data /opt/nginx/logs/modsec_tmp /opt/nginx/logs/modsec_data
chmod -R 770 /opt/nginx/logs/modsec_tmp /opt/nginx/logs/modsec_data
chown root:www-data /opt/nginx/logs/modsec_audit.log /opt/nginx/logs/modsec_debug.log
chmod 660 /opt/nginx/logs/modsec_audit.log /opt/nginx/logs/modsec_debug.log

# 3. 规范你的规则库只读权限（防止被木马篡改）
chown -R root:www-data /opt/owasp/ /opt/nginx/src/ModSecurity/
find /opt/owasp/ -type d -exec chmod 750 {} \;
find /opt/owasp/ -type f -exec chmod 640 {} \;

# 精准锁定这三个核心动态库文件的属组为 www-data，并赋予 640 只读权限
chown root:www-data /usr/lib/libmodsecurity.so*
chmod 640 /usr/lib/libmodsecurity.so*

# 2. 允许 nginx 用户和组穿透 /opt 和 /opt/nginx 顶级目录
chmod g+x "$SITE_OPT"
chmod g+x "$SITE_DIR"

# 3. 将配置目录和证书目录的【属组】强行修改为 www-data 组
chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/conf"
chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/conf.d"
chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/ssl"  # 证书上级目录建议保持 root 拥有

# 特别注意：将证书私钥所在目录属组变更为 www-data，以便 Nginx 工作进程读取
chown -R root:"$SITE_NGINX_GROUP" "$SITE_SSL_BASE_DIR"

# 4. 严格规范 Nginx 配置与证书目录权限（750）与文件权限（640）
find "$SITE_DIR/conf" -type d -exec chmod 750 {} \;
find "$SITE_DIR/conf" -type f -exec chmod 640 {} \;

find "$SITE_DIR/conf.d" -type d -exec chmod 750 {} \;
find "$SITE_DIR/conf.d" -type f -exec chmod 640 {} \;

find "$SITE_SSL_BASE_DIR" -type d -exec chmod 750 {} \;
find "$SITE_SSL_BASE_DIR" -type f -exec chmod 640 {} \;


# 5. 允许 Nginx 进程穿透 /www 顶级目录
chmod g+x "$SITE_NGINX_ROOT"

# 6. 将网站根目录的属组变更为 www-data 组
chown -R root:"$SITE_NGINX_GROUP" "$SITE_NGINX_ROOT_DIR"

# 先全盘应用 750 / 640 严苛只读权限，锁死 WordPress 核心源码阻止木马篡改
find "$SITE_NGINX_ROOT_DIR" -type d -exec chmod 750 {} \;
find "$SITE_NGINX_ROOT_DIR" -type f -exec chmod 640 {} \;

# =======================================================================
# 1. 自动化下载与解压 WordPress（直接注入到你的变量路径）
# =======================================================================
echo "正在下载最新的 WordPress 官方源码..."
# 下载最新的 WordPress 压缩包，存放到 /tmp 目录
curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz

echo "正在解压并部署到网站根目录: $WEB_ROOT"
# 创建根目录（如果不存在）
mkdir -p "$WEB_ROOT"

# 解压并利用 --strip-components=1 直接把解压出的 wordpress 文件夹内部文件
# 释放到 $SITE_NGINX_ROOT_DIR 正下方，而不是多套一层名为 "wordpress" 的外壳
tar -zxf /tmp/wordpress.tar.gz -C "$WEB_ROOT" --strip-components=1

# 清理临时下载包
rm -f /tmp/wordpress.tar.gz

# 【关键追加】：精准放行 WP 媒体上传和多媒体目录，允许 www-data(PHP-FPM) 写入
# 如果你的 WordPress 下面有特殊的缓存目录（如 wp-content/cache），也按此法处理
if [ -d "$WEB_ROOT/wp-content" ]; then
    chown -R "$SITE_NGINX_USER":"$SITE_NGINX_GROUP" "$WEB_ROOT/wp-content"
    find "$WEB_ROOT/wp-content" -type d -exec chmod 775 {} \;
    find "$WEB_ROOT/wp-content" -type f -exec chmod 664 {} \;
fi

# 替换残留 NGINX 字段
sed -i "s|nginx/\$nginx_version|CloudFlare|g" "$SITE_DIR/conf/fastcgi.conf"

# 7. 确保 /opt/nginx/logs 目录及其子缓存目录允许 www-data 组绝对读写（770）
chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/logs"
chmod -R 770 "$SITE_DIR/logs"


        # 申请通配符证书
        issue_cert_wildcard "$DOMAIN" || echo "⚠️ $DOMAIN 证书申请失败，可重试"

        echo "✅ 网站创建完成：$DOMAIN"
        echo "📁 网站根目录：$WEB_ROOT"
        echo "📄 配置文件：$CONF_FILE"
        echo "🔒 SSL 证书目录：$SITE_SSL_BASE_DIR/$(get_root_domain $DOMAIN)"
    done

    nginx_reload
}

delete_site() {
    local DOMAINS="$1"

    for DOMAIN in $DOMAINS; do
        rm -f "$SITE_ENABLED_DIR/$DOMAIN.conf"

        read -p "删除网站目录 $DOMAIN？(y/n): " a
        [[ "$a" =~ ^[Yy]$ ]] && rm -rf "$SITE_NGINX_ROOT_DIR/$DOMAIN"

        read -p "删除配置文件 $DOMAIN？(y/n): " b
        [[ "$b" =~ ^[Yy]$ ]] && rm -f "$SITE_CONF_DIR/$DOMAIN.conf"

        local ROOT_DOMAIN
        ROOT_DOMAIN=$(get_root_domain "$DOMAIN")

        # 检查是否还有其他域名（顶级或二级）使用该根域名证书
        local REMAINING=0
        for d in $SITE_NGINX_ROOT_DIR/*; do
            [[ -d "$d" ]] || continue
            local DN
            DN=$(basename "$d")
            [[ "$DN" == "$DOMAIN" ]] && continue
            [[ "$(get_root_domain "$DN")" == "$ROOT_DOMAIN" ]] && REMAINING=1 && break
        done

        if [[ $REMAINING -eq 0 ]]; then
            if acme.sh --list | grep -qw "$ROOT_DOMAIN"; then
                acme.sh --remove -d "*.$ROOT_DOMAIN" -d "$ROOT_DOMAIN"
                echo "✅ 根域名 $ROOT_DOMAIN 通配符证书已撤销"
            fi
        else
            echo "⚠️ 根域名 $ROOT_DOMAIN 仍有其他域名使用，证书保留"
        fi

        echo "✅ 网站已删除：$DOMAIN"
    done

    nginx_reload
}

# ============================
# 主菜单
# ============================
while true; do
    echo
    echo "请选择操作："
    echo "1) 创建网站"
    echo "2) 删除网站"
    echo "0) 退出"
    read -r ACTION

    case "$ACTION" in
        1)
            read -r -p "请输入域名（空格分隔）: " DOMAIN
            select_dns_site_provider
            setup_dns_api
            create_site "$DOMAIN"
            ;;
        2)
            read -r -p "请输入域名（空格分隔）: " DOMAIN
            delete_site "$DOMAIN"
            ;;
        0)
            echo "👋 已退出"
            exit 0
            ;;
        *)
            echo "❌ 无效选项"
            ;;
    esac
done
