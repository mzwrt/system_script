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
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]
}

# ----------------------------
# DH 参数生成（一次性）
# ----------------------------
generate_dhparam() {
    if [ ! -f "$SITE_DHPARAM_FILE" ]; then
        mkdir -p "$(dirname "$SITE_DHPARAM_FILE")"
        echo "正在生成 DH 参数，可能需要几分钟..."
        openssl dhparam -out "$SITE_DHPARAM_FILE" 2048 >/dev/null 2>&1
        chmod 400 "$SITE_DHPARAM_FILE"
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
                read -r -p "请输入邮箱: " site_account_email
                read -r -p "Ali_Key: " Ali_Key
                read -r -p "Ali_Secret: " Ali_Secret
                export Ali_Key Ali_Secret
                acme.sh --register-account --accountemail "$site_account_email"
            else
                echo "✅ 阿里云 DNS API 已配置"
            fi
            ;;
        cf)
            if ! grep -q 'CF_Token' "$SITE_ACME_ACCOUNT_CONF" 2>/dev/null; then
                echo "首次使用 Cloudflare DNS，请输入 API 密钥"
                read -r -p "请输入邮箱: " site_account_email
                read -r -p "CF_Token: " CF_Token
                read -r -p "CF_Account: " CF_Account
                export CF_Token CF_Account
                acme.sh --register-account --accountemail "$site_account_email"
            else
                echo "✅ Cloudflare DNS API 已配置"
            fi
            ;;
    esac
}

# ----------------------------
# 证书申请
# ----------------------------
issue_cert() {
    local DOMAIN="$1"
    local SSL_DIR="$SITE_SSL_BASE_DIR/$DOMAIN"

    if [ -f "$SSL_DIR/fullchain.pem" ]; then
        echo "✅ $DOMAIN 证书已存在，跳过申请"
        return
    fi

    echo "📄 正在申请 $DOMAIN 证书..."
    if ! acme.sh --issue -d "$DOMAIN" --dns dns_"$SITE_PROVIDER" --keylength 2048; then
        echo "❌ 证书申请失败：$DOMAIN"
        acme.sh --remove -d "$DOMAIN" 2>/dev/null || true
        return 1
    fi

    mkdir -p "$SSL_DIR"
    chmod 700 "$SSL_DIR"
    acme.sh --install-cert -d "$DOMAIN" \
        --key-file "$SSL_DIR/privkey.pem" \
        --fullchain-file "$SSL_DIR/fullchain.pem" \
        --ca-file "$SSL_DIR/ca.pem" \
        --reloadcmd "systemctl reload nginx"

    find "$SSL_DIR" -type f -exec chmod 600 {} \;
    echo "✅ $DOMAIN 证书申请完成"
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

        local WEB_ROOT="/www/wwwroot/$DOMAIN"
        local CONF_FILE="$SITE_CONF_DIR/$DOMAIN.conf"

        mkdir -p "$WEB_ROOT"
        chown -R "$SITE_NGINX_USER:$SITE_NGINX_GROUP" "$WEB_ROOT"
        mkdir -p "$SITE_CONF_DIR" "$SITE_ENABLED_DIR" "$SITE_SSL_BASE_DIR/$DOMAIN"
        chmod 700 "$SITE_SSL_BASE_DIR/$DOMAIN"

        # 下载模板
        if [ ! -f "$CONF_FILE" ]; then
            curl -fsSL "$SITE_TEMPLATE_URL" -o "$CONF_FILE"
            chmod 600 "$CONF_FILE"
            ln -sf "$CONF_FILE" "$SITE_ENABLED_DIR/"
        fi

        # 替换变量
        sed -i \
            -e "s|%DOMAIN%|$DOMAIN|g" \
            -e "s|%WEB_ROOT%|$WEB_ROOT|g" \
            -e "s|%SSL_DIR%|$SITE_SSL_BASE_DIR/$DOMAIN|g" \
            -e "s|%SITE_OPT%|$SITE_OPT|g" \
            "$CONF_FILE"

        # 申请证书
        issue_cert "$DOMAIN" || echo "⚠️ $DOMAIN 证书申请失败，可重试"

        echo "✅ 网站创建完成：$DOMAIN"
        echo "📁 网站根目录：$WEB_ROOT"
        echo "📄 配置文件：$CONF_FILE"
        echo "🔒 SSL 证书目录：$SITE_SSL_BASE_DIR/$DOMAIN"
    done

    nginx_reload
}

# ----------------------------
# 删除网站
# ----------------------------
delete_site() {
    local DOMAINS="$1"

    for DOMAIN in $DOMAINS; do
        rm -f "$SITE_ENABLED_DIR/$DOMAIN.conf"

        read -p "删除网站目录 $DOMAIN？(y/n): " a
        [[ "$a" =~ ^[Yy]$ ]] && rm -rf "/www/wwwroot/$DOMAIN"

        read -p "删除配置文件 $DOMAIN？(y/n): " b
        [[ "$b" =~ ^[Yy]$ ]] && rm -f "$SITE_CONF_DIR/$DOMAIN.conf"

        if acme.sh --list | grep -qw "$DOMAIN"; then
            acme.sh --remove -d "$DOMAIN"
            echo "✅ $DOMAIN 证书已撤销"
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
