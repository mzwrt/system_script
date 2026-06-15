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
                read -r -p "Ali_Key: " Ali_Key
                read -r -p "Ali_Secret: " Ali_Secret
                export Ali_Key Ali_Secret
            else
                echo "✅ 阿里云 DNS API 已配置"
            fi
            ;;
        cf)
            if ! grep -q 'CF_Token' "$SITE_ACME_ACCOUNT_CONF" 2>/dev/null; then
                echo "首次使用 Cloudflare DNS，请输入 API 密钥"
                read -r -p "CF_Token: " CF_Token
                read -r -p "CF_Account: " CF_Account
                export CF_Token CF_Account
            else
                echo "✅ Cloudflare DNS API 已配置"
            fi
            ;;
    esac
}

# ----------------------------
# 二级公共后缀白名单
#
# 原理说明：
#   全球部分国家/地区使用"二级公共后缀"，例如：
#     edu.cn / ac.id / edu.pl / ac.in / co.uk
#   这些后缀本身【不可注册】，不是真正的"根域名"。
#   例如 lib.wszs.edu.pl 的可注册根域名是 wszs.edu.pl，
#   而不是 edu.pl（edu.pl 是公共后缀，任何人都不能单独注册它）。
#
#   通配符证书必须针对"可注册根域名"申请，
#   因此必须识别出正确的根域名，才能申请 *.wszs.edu.pl 而不是 *.edu.pl。
# ----------------------------
SITE_SECOND_LEVEL_TLDS=(
    # 中国
    "edu.cn" "gov.cn" "com.cn" "net.cn" "org.cn" "ac.cn" "mil.cn"
    # 英国
    "co.uk" "edu.uk" "gov.uk" "ac.uk" "org.uk" "me.uk" "net.uk" "ltd.uk" "plc.uk"
    # 澳大利亚
    "com.au" "edu.au" "gov.au" "net.au" "org.au" "id.au" "asn.au"
    # 印度
    "co.in" "edu.in" "gov.in" "ac.in" "org.in" "net.in" "res.in" "mil.in"
    # 印度尼西亚
    "co.id" "ac.id" "edu.id" "or.id" "gov.id" "net.id" "sch.id" "web.id" "my.id"
    # 波兰
    "edu.pl" "gov.pl" "com.pl" "org.pl" "net.pl" "ac.pl" "mil.pl"
    # 巴西
    "com.br" "edu.br" "gov.br" "org.br" "net.br" "mil.br" "art.br" "coop.br"
    # 日本
    "co.jp" "ac.jp" "ed.jp" "go.jp" "or.jp" "ne.jp" "ad.jp"
    # 韩国
    "co.kr" "ac.kr" "go.kr" "or.kr" "ne.kr" "re.kr" "mil.kr"
    # 南非
    "co.za" "ac.za" "edu.za" "gov.za" "org.za" "net.za" "mil.za"
    # 新西兰
    "co.nz" "ac.nz" "edu.nz" "gov.nz" "net.nz" "org.nz"
    # 阿根廷
    "com.ar" "edu.ar" "gov.ar" "org.ar" "net.ar" "mil.ar"
    # 墨西哥
    "com.mx" "edu.mx" "gob.mx" "org.mx" "net.mx"
    # 安哥拉（你的实际业务场景）
    "co.ao" "ed.ao" "gv.ao" "og.ao" "pb.ao" "it.ao"
    # 葡萄牙
    "edu.pt" "gov.pt" "com.pt" "org.pt" "net.pt"
    # 越南
    "edu.vn" "gov.vn" "com.vn" "net.vn" "org.vn" "ac.vn"
    # 新加坡
    "edu.sg" "gov.sg" "com.sg" "net.sg" "org.sg" "per.sg"
    # 香港
    "edu.hk" "gov.hk" "com.hk" "idv.hk" "net.hk" "org.hk"
    # 台湾
    "edu.tw" "gov.tw" "com.tw" "org.tw" "net.tw" "idv.tw" "mil.tw"
    # 菲律宾
    "edu.ph" "gov.ph" "com.ph" "net.ph" "org.ph" "mil.ph"
    # 马来西亚
    "edu.my" "gov.my" "com.my" "net.my" "org.my" "mil.my"
    # 泰国
    "ac.th" "co.th" "go.th" "net.th" "or.th" "in.th"
    # 巴基斯坦
    "edu.pk" "gov.pk" "com.pk" "net.pk" "org.pk" "mil.pk"
    # 尼日利亚
    "edu.ng" "gov.ng" "com.ng" "net.ng" "org.ng" "mil.ng"
    # 肯尼亚
    "ac.ke" "co.ke" "go.ke" "ne.ke" "or.ke"
    # 埃及
    "edu.eg" "gov.eg" "com.eg" "net.eg" "org.eg"
    # 俄罗斯
    "edu.ru" "gov.ru" "com.ru" "net.ru" "org.ru" "mil.ru"
    # 乌克兰
    "edu.ua" "gov.ua" "com.ua" "net.ua" "org.ua" "mil.ua"
    # 意大利（部分地区性后缀）
    "edu.it" "gov.it"
    # 西班牙
    "edu.es" "gob.es" "com.es" "org.es" "nom.es"
    # 哥伦比亚
    "edu.co" "gov.co" "com.co" "net.co" "org.co" "mil.co"
    # 秘鲁
    "edu.pe" "gob.pe" "com.pe" "net.pe" "org.pe" "mil.pe"
    # 智利
    "edu.cl" "gov.cl" "com.cl" "net.cl" "org.cl" "mil.cl"
)

# ----------------------------
# 提取根域名（支持二级公共后缀）
#
# 工作流程：
#   1. 去掉通配符前缀 "*."（如果有）
#   2. 提取域名最后两段，组成"疑似后缀"
#   3. 在白名单中查找：如果命中 → 取最后三段作为根域名
#                      如果未命中 → 取最后两段作为根域名
#
# 示例：
#   lib.wszs.edu.pl  → 后缀 edu.pl 命中白名单 → 根域名 wszs.edu.pl
#   sub.example.com  → 后缀 example.com 未命中  → 根域名 example.com
#   portal.ac.id     → 后缀 ac.id 命中白名单   → 根域名 portal.ac.id（仅2段+后缀，原样返回）
# ----------------------------
get_root_domain() {
    local DOMAIN="$1"
    # 去掉可能存在的通配符前缀 "*."
    DOMAIN="${DOMAIN#\*.}"

    # 提取最后两段，作为"疑似公共后缀"进行白名单匹配
    local SUFFIX
    SUFFIX=$(echo "$DOMAIN" | awk -F. '{n=NF; print $(n-1)"."$n}')

    local is_second_level=0
    for tld in "${SITE_SECOND_LEVEL_TLDS[@]}"; do
        if [[ "$SUFFIX" == "$tld" ]]; then
            is_second_level=1
            break
        fi
    done

    if [[ "$is_second_level" -eq 1 ]]; then
        # 命中二级公共后缀：取最后三段作为根域名
        # 如果域名本身总段数不足三段（如直接输入 edu.pl），则原样返回
        echo "$DOMAIN" | awk -F. '{
            n=NF
            if (n >= 3) print $(n-2)"."$(n-1)"."$n
            else print $0
        }'
    else
        # 普通后缀：取最后两段作为根域名
        echo "$DOMAIN" | awk -F. '{n=NF; print $(n-1)"."$n}'
    fi
}

# ----------------------------
# 证书申请（通配符）
# ----------------------------
declare -A CERT_APPLIED  # 记录本次运行中已申请的根域名，避免重复申请

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
# Nginx 配置检查与重载
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

        # 替换模板变量
        sed -i \
            -e "s|%DOMAIN%|$DOMAIN|g" \
            -e "s|%WEB_ROOT%|$WEB_ROOT|g" \
            -e "s|%SSL_DIR%|$SITE_SSL_BASE_DIR/$(get_root_domain $DOMAIN)|g" \
            -e "s|%SITE_OPT%|$SITE_OPT|g" \
            "$CONF_FILE"

        # 创建缓存和临时目录
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

        # 创建 ModSecurity 日志文件
        mkdir -p /opt/nginx/logs/modsec_tmp /opt/nginx/logs/modsec_data
        touch /opt/nginx/logs/modsec_audit.log /opt/nginx/logs/modsec_debug.log

        # 设置 ModSecurity 读写目录权限
        chown -R root:www-data /opt/nginx/logs/modsec_tmp /opt/nginx/logs/modsec_data
        chmod -R 770 /opt/nginx/logs/modsec_tmp /opt/nginx/logs/modsec_data
        chown root:www-data /opt/nginx/logs/modsec_audit.log /opt/nginx/logs/modsec_debug.log
        chmod 660 /opt/nginx/logs/modsec_audit.log /opt/nginx/logs/modsec_debug.log

        # 规范规则库只读权限（防止木马篡改）
        chown -R root:www-data /opt/owasp/ /opt/nginx/src/ModSecurity/
        find /opt/owasp/ -type d -exec chmod 750 {} \;
        find /opt/owasp/ -type f -exec chmod 640 {} \;

        # 锁定核心动态库权限
        chown root:www-data /usr/lib/libmodsecurity.so*
        chmod 644 /usr/lib/libmodsecurity.so*

        # 允许 nginx 用户穿透 /opt 和 /opt/nginx 顶级目录
        chmod g+x "$SITE_OPT"
        chmod g+x "$SITE_DIR"

        # 修正配置目录和证书目录属组
        chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/conf"
        chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/conf.d"
        chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/ssl"
        chown -R root:"$SITE_NGINX_GROUP" "$SITE_SSL_BASE_DIR"

        # 规范配置目录权限
        find "$SITE_DIR/conf" -type d -exec chmod 750 {} \;
        find "$SITE_DIR/conf" -type f -exec chmod 640 {} \;

        find "$SITE_DIR/conf.d" -type d -exec chmod 750 {} \;
        find "$SITE_DIR/conf.d" -type f -exec chmod 640 {} \;

        find "$SITE_SSL_BASE_DIR" -type d -exec chmod 750 {} \;
        find "$SITE_SSL_BASE_DIR" -type f -exec chmod 640 {} \;

        # 允许 Nginx 进程穿透 /www 顶级目录
        chmod g+x "$SITE_NGINX_ROOT"

        # 修正网站根目录属组
        chown -R root:"$SITE_NGINX_GROUP" "$SITE_NGINX_ROOT_DIR"

        # 全盘锁定网站根目录权限（防木马篡改 WordPress 核心源码）
        find "$SITE_NGINX_ROOT_DIR" -type d -exec chmod 750 {} \;
        find "$SITE_NGINX_ROOT_DIR" -type f -exec chmod 640 {} \;

        # 修正 logs 目录权限
        chown -R root:"$SITE_NGINX_GROUP" "$SITE_DIR/logs"
        chmod -R 750 "$SITE_DIR/logs"

        # 下载并部署 WordPress
        echo "正在下载最新的 WordPress 官方源码..."
        curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz

        echo "正在解压并部署到网站根目录: $WEB_ROOT"
        mkdir -p "$WEB_ROOT"
        tar -zxf /tmp/wordpress.tar.gz -C "$WEB_ROOT" --strip-components=1

        # 修正 WordPress 目录权限
        chmod g+x "$SITE_NGINX_ROOT" "$SITE_NGINX_ROOT_DIR"
        chown -R www-data:www-data "$WEB_ROOT"
        find "$WEB_ROOT" -type d -exec chmod 755 {} \;
        find "$WEB_ROOT" -type f -exec chmod 644 {} \;
        chmod 440 "$WEB_ROOT/wp-config-sample.php"

        # 清理临时文件
        rm -f /tmp/wordpress.tar.gz

        # 放行 WordPress 媒体上传目录写权限
        if [ -d "$WEB_ROOT/wp-content" ]; then
            chown -R "$SITE_NGINX_USER":"$SITE_NGINX_GROUP" "$WEB_ROOT/wp-content"
            find "$WEB_ROOT/wp-content" -type d -exec chmod 775 {} \;
            find "$WEB_ROOT/wp-content" -type f -exec chmod 664 {} \;
        fi

        # 隐藏 nginx 版本信息
        sed -i "s|nginx/\$nginx_version|CloudFlare|g" "$SITE_DIR/conf/fastcgi.conf"

        # 申请通配符证书
        issue_cert_wildcard "$DOMAIN" || echo "⚠️ $DOMAIN 证书申请失败，可重试"

        echo "✅ 网站创建完成：$DOMAIN"
        echo "📁 网站根目录：$WEB_ROOT"
        echo "📄 配置文件：$CONF_FILE"
        echo "🔒 SSL 证书目录：$SITE_SSL_BASE_DIR/$(get_root_domain $DOMAIN)"
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
        [[ "$a" =~ ^[Yy]$ ]] && rm -rf "$SITE_NGINX_ROOT_DIR/$DOMAIN"

        read -p "删除配置文件 $DOMAIN？(y/n): " b
        [[ "$b" =~ ^[Yy]$ ]] && rm -f "$SITE_CONF_DIR/$DOMAIN.conf"

        local ROOT_DOMAIN
        ROOT_DOMAIN=$(get_root_domain "$DOMAIN")

        # 检查是否还有其他域名使用该根域名的证书
        local REMAINING=0
        for d in "$SITE_NGINX_ROOT_DIR"/*; do
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

# ----------------------------
# 主菜单
# ----------------------------
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
