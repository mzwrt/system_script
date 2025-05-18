#!/bin/bash

# 选择操作类型
echo "请选择操作："
echo "1) 创建网站"
echo "2) 删除网站"
read -p "请输入选项（1 或 2）: " ACTION

# 输入域名
read -p "请输入域名（多个域名用空格分隔）: " DOMAIN_INPUT
FIRST_DOMAIN=$(echo "$DOMAIN_INPUT" | awk '{print $1}')
MAIN_DOMAIN=$(echo "$FIRST_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

WEB_ROOT="/www/wwwroot/$FIRST_DOMAIN"
CONF_DIR="/opt/nginx/conf.d/sites-available"
ENABLED_DIR="/opt/nginx/conf.d/sites-enabled"
CONF_FILE="$CONF_DIR/$FIRST_DOMAIN.conf"
ENABLED_LINK="$ENABLED_DIR/$FIRST_DOMAIN.conf"
SSL_DIR="/opt/nginx/ssl/$MAIN_DOMAIN"
DHPARAM_FILE="/opt/nginx/ssl/dhparam.pem"
TEMPLATE_URL="https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/example.com.conf"

if [ "$ACTION" == "1" ]; then
    # 创建网站根目录
    if [ ! -d "$WEB_ROOT" ]; then
        mkdir -p "$WEB_ROOT"
        echo "已创建网站目录：$WEB_ROOT"
    else
        echo "网站目录已存在：$WEB_ROOT，跳过创建"
    fi

    # 设置属主
    chown -R www-data:www-data "$WEB_ROOT"

    # 创建配置目录
    mkdir -p "$CONF_DIR" "$ENABLED_DIR"

    # 下载模板
    if [ ! -f "$CONF_FILE" ]; then
        curl -fsSL "$TEMPLATE_URL" -o "$CONF_FILE"
        if [ ! -f "$CONF_FILE" ]; then
            echo "❌ 模板下载失败，配置文件未创建"
            exit 1
        fi
        echo "已下载配置模板到：$CONF_FILE"
    else
        echo "配置文件已存在：$CONF_FILE，跳过下载"
    fi

    # 替换配置内容
    sed -i "s|server_name example.com;|server_name $DOMAIN_INPUT;|g" "$CONF_FILE"
    sed -i "s|/www/wwwroot/example.com|$WEB_ROOT|g" "$CONF_FILE"
    sed -i "s|/opt/nginx/ssl/.*/fullchain.pem|$SSL_DIR/fullchain.pem|g" "$CONF_FILE"
    sed -i "s|/opt/nginx/ssl/.*/privkey.pem|$SSL_DIR/privkey.pem|g" "$CONF_FILE"
    sed -i "s|/opt/nginx/ssl/.*/ca.pem|$SSL_DIR/ca.pem|g" "$CONF_FILE"

    # 创建 SSL 目录
    mkdir -p "$SSL_DIR"

    # 生成 dhparam.pem
    if [ ! -f "$DHPARAM_FILE" ]; then
        echo "正在生成 dhparam.pem，这可能需要几分钟..."
        openssl dhparam -out "$DHPARAM_FILE" 2048
        chmod 400 "$DHPARAM_FILE"
        echo "已生成 $DHPARAM_FILE 并设置权限为 400"
    fi

    # 创建软链接
    if [ ! -L "$ENABLED_LINK" ]; then
        ln -s "$CONF_FILE" "$ENABLED_LINK"
        echo "已创建软链接：$ENABLED_LINK"
    else
        echo "软链接已存在：$ENABLED_LINK，跳过"
    fi

    # 权限
    chmod 600 "$CONF_FILE"

    # 完成提示
    echo "##################################################"
    echo "✅ 网站 $DOMAIN_INPUT 已创建完成"
    echo "📁 网站根目录：$WEB_ROOT"
    echo "📄 配置文件：$CONF_FILE"
    echo "🔒 SSL 证书目录：$SSL_DIR"
    echo "⚠️ 请确保 SSL 证书已经安装或上传在：$SSL_DIR 目录"
    echo "🛡️ Diffie-Hellman 参数文件：$DHPARAM_FILE"
    echo "##################################################"
    echo "🔁 添加网站脚本位置：/root/site.sh "
    echo "🎯 需要添加/删除网站直接运行：bash /root/site.sh "
    echo "##################################################"


elif [ "$ACTION" == "2" ]; then
    # 删除软链接
    if [ -L "$ENABLED_LINK" ]; then
        rm -f "$ENABLED_LINK"
        echo "已删除软链接：$ENABLED_LINK"
    else
        echo "未找到软链接：$ENABLED_LINK"
    fi

    # 是否删除网站根目录
    read -p "是否删除网站根目录 $WEB_ROOT？(y/n): " DEL_WEB
    if [[ "$DEL_WEB" =~ ^[Yy]$ ]] && [ -d "$WEB_ROOT" ]; then
        rm -rf "$WEB_ROOT"
        echo "已删除网站目录：$WEB_ROOT"
    fi

    # 是否删除配置文件
    read -p "是否删除配置文件 $CONF_FILE？(y/n): " DEL_CONF
    if [[ "$DEL_CONF" =~ ^[Yy]$ ]] && [ -f "$CONF_FILE" ]; then
        rm -f "$CONF_FILE"
        echo "已删除配置文件：$CONF_FILE"
    fi

    # 是否删除 SSL 证书目录
    read -p "是否删除 SSL 证书目录 $SSL_DIR？(y/n): " DEL_SSL
    if [[ "$DEL_SSL" =~ ^[Yy]$ ]] && [ -d "$SSL_DIR" ]; then
        rm -rf "$SSL_DIR"
        echo "已删除 SSL 证书目录：$SSL_DIR"
    fi

    echo "✅ 网站 $DOMAIN_INPUT 删除操作已完成"
else
    echo "❌ 无效选项：$ACTION"
    exit 1
fi
