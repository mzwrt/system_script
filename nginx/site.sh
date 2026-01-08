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

# 检查 acme.sh 是否已安装
command -v acme.sh >/dev/null 2>&1 || {
    echo "❌ 未检测到 acme.sh，请先安装或检查 PATH"
    read -p "是否要安装 acme.sh？ (y/n): " install_choice
    if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
        # 提示用户输入邮箱并安装 acme.sh
        read -p "请输入邮箱地址用于注册账户: " user_email
        echo "正在安装 acme.sh..."
        sudo apt update
        sudo apt install socat
        wget -O -  https://get.acme.sh | sh -s email="$user_email"
        echo "acme.sh 安装完成"
    else
        echo "用户选择不安装，退出脚本。"
        exit 1
    fi
}

# ----------------------------
# 域名校验
# ----------------------------
validate_SITE_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

# ----------------------------
# DH 参数生成
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
# DNS 提供商选择（含退出）
# ----------------------------
SITE_provider=""
select_dns_SITE_provider() {
    while true; do
        echo
        echo "请选择 DNS 提供商："
        echo "1) 阿里云"
        echo "2) Cloudflare"
        echo "0) 退出"
        read -r c </dev/tty
        case "$c" in
            1) SITE_provider="ali"; return ;;
            2) SITE_provider="cf"; return ;;
            0) echo "已退出"; exit 0 ;;
            *) echo "❌ 无效选项，请输入 1、2 或 0";;
        esac
    done
}

# ----------------------------
# DNS API 检测
# ----------------------------
setup_dns_api() {
    case "$SITE_provider" in
        ali)
            if ! grep -q 'Ali_Key' "$SITE_ACME_ACCOUNT_CONF" 2>/dev/null; then
                echo "首次使用阿里云 DNS，请输入 API 密钥"
                read -r -p "请输入您的邮箱（例如 you@example.com）: " site_account_email  # 提示输入邮箱
                read -r -p "Ali_Key: " Ali_Key
                read -r -p "Ali_Secret: " Ali_Secret
                export Ali_Key Ali_Secret
                acme.sh --register-account --accountemail "$site_account_email" --dns dns_ali
            fi
            ;;
        cf)
            if ! grep -q 'CF_Token' "$SITE_ACME_ACCOUNT_CONF" 2>/dev/null; then
                echo "首次使用 Cloudflare DNS，请输入 API 密钥"
                read -r -p "请输入您的邮箱（例如 you@example.com）: " site_account_email  # 提示输入邮箱
                read -r -p "CF_Token: " CF_Token
                read -r -p "CF_Account: " CF_Account
                export CF_Token CF_Account
                acme.sh --register-account --accountemail "$site_account_email" --dns dns_cf
            fi
            ;;
    esac
}

# ----------------------------
# 证书申请（每个域名单独）
# ----------------------------
issue_cert() {
    local SITE_domain="$1"

    if acme.sh --list | grep -qw "$SITE_domain"; then
        echo "✅ 已存在 $SITE_domain 证书，跳过申请"
        return
    fi

    echo "📄 开始申请 $SITE_domain 证书..."
    if ! acme.sh --issue -d "$SITE_domain" --dns dns_"$SITE_provider" --keylength 2048; then
        echo "❌ 证书申请失败：$SITE_domain"
        acme.sh --remove -d "$SITE_domain" 2>/dev/null || true
        return 1
    fi

    mkdir -p "$SITE_SSL_BASE_DIR/$SITE_domain"
    chmod 700 "$SITE_SSL_BASE_DIR/$SITE_domain"
    acme.sh --install-cert -d "$SITE_domain" \
        --key-file "$SITE_SSL_BASE_DIR/$SITE_domain/privkey.pem" \
        --fullchain-file "$SITE_SSL_BASE_DIR/$SITE_domain/fullchain.pem" \
        --ca-file "$SITE_SSL_BASE_DIR/$SITE_domain/ca.pem" \
        --reloadcmd "systemctl reload nginx"
    # 查找目录下的所有文件，并设置权限为 600
    find "$SITE_SSL_BASE_DIR/$SITE_domain" -type f -exec chmod 600 {} \;

    echo "✅ $SITE_domain 证书申请完成"
}

# ----------------------------
# 检查 Nginx 配置并重载
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
    local SITE_SITE_domains="$1"

    for SITE_domain in $SITE_SITE_domains; do
        SITE_domain="${SITE_domain// /}"       # 去掉空格
        validate_SITE_domain "$SITE_domain" || { echo "❌ 域名不合法：$SITE_domain"; continue; }

        local SITE_web="/www/wwwroot/$SITE_domain"
        local SITE_conf="$SITE_CONF_DIR/$SITE_domain.conf"

        # 创建目录
        # 检查并创建必要的目录
        if [ ! -d "$SITE_web" ]; then
            mkdir -p "$SITE_web"
            chown -R "$SITE_NGINX_USER:$SITE_NGINX_GROUP" "$SITE_web"
        fi

        if [ ! -d "$SITE_CONF_DIR" ]; then
            mkdir -p "$SITE_CONF_DIR"
        fi

        if [ ! -d "$SITE_ENABLED_DIR" ]; then
            mkdir -p "$SITE_ENABLED_DIR"
        fi

        if [ ! -d "$SITE_SSL_BASE_DIR/$SITE_domain" ]; then
            mkdir -p "$SITE_SSL_BASE_DIR/$SITE_domain"
            chmod 700 "$SITE_SSL_BASE_DIR/$SITE_domain"
        fi

        # 下载模板
        if [ ! -f "$SITE_conf" ]; then
            curl -fsSL "$SITE_TEMPLATE_URL" -o "$SITE_conf"
            chmod 600 "$SITE_conf"
            ln -sf "$SITE_conf" "$SITE_ENABLED_DIR/"
        else
            echo "File already exists, skipping download."
        fi
        

        # 替换模板变量
        sed -i \
            -e "s|%DOMAIN%|$SITE_domain|g" \
            -e "s|%WEB_ROOT%|$SITE_web|g" \
            -e "s|%SSL_DIR%|$SITE_SSL_BASE_DIR/$SITE_domain|g" \
            -e "s|%SITE_OPT%|$SITE_OPT|g" \
            "$SITE_conf"

        generate_dhparam
        issue_cert "$SITE_domain" || echo "⚠️ $SITE_domain 证书申请失败，可重试"

        echo "✅ 网站创建完成：$SITE_domain"
        echo "📁 网站根目录：$SITE_web"
        echo "📄 配置文件：$SITE_conf"
        echo "🔒 SSL 证书目录：$SITE_SSL_BASE_DIR/$SITE_domain"
    done

    nginx_reload
}


# ----------------------------
# 删除网站
# ----------------------------
delete_site() {
    local SITE_SITE_domains="$1"

    for SITE_domain in $SITE_SITE_domains; do
        rm -f "$SITE_ENABLED_DIR/$SITE_domain.conf"

        read -p "删除网站目录 $SITE_domain？(y/n): " a
        [[ "$a" =~ ^[Yy]$ ]] && rm -rf "/www/wwwroot/$SITE_domain"

        read -p "删除配置文件 $SITE_domain？(y/n): " b
        [[ "$b" =~ ^[Yy]$ ]] && rm -f "$SITE_CONF_DIR/$SITE_domain.conf"

        if acme.sh --list | grep -qw "$SITE_domain"; then
            acme.sh --remove -d "$SITE_domain"
            echo "✅ $SITE_domain 证书已撤销"
        fi

        echo "✅ 网站已删除：$SITE_domain"
    done

    nginx_reload
}

# ============================
# 主菜单（含退出）
# ============================
while true; do
    echo
    echo "请选择操作："
    echo "1) 创建网站"
    echo "2) 删除网站"
    echo "0) 退出"
    read -r ACTION </dev/tty

    case "$ACTION" in
        1)
            read -r -p "请输入域名（空格分隔）: " SITE_domain </dev/tty
            create_site "$SITE_domain"
            select_dns_SITE_provider
            setup_dns_api
            ;;
        2)
            read -r -p "请输入域名（空格分隔）: " SITE_domain </dev/tty
            delete_site "$SITE_domain"
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
