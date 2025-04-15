#!/bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
  echo "本脚本需要以 root 用户权限运行，请使用 sudo 执行。"
  exit 1
fi

# 定义安装路径和源码路径
NGINX_DIR="/opt"
INSTALL_DIR="/opt/nginx"  # 安装目录
SRC_DIR="/opt/nginx/src"   # 源代码和模块的存放目录


# 提示用户选择操作
echo "请选择操作模式："
echo "1. 安装"
echo "2. 卸载"
echo "3. 退出"
read -rp "输入 1、2 或 3 进行选择: " choice

# 根据用户选择进行不同操作
case $choice in
  1)
    MODE="install"
    echo "选择安装模式，开始安装..."
    # 执行安装操作
    # 你可以把原来的安装代码放到这个部分
    ;;
  2)
    MODE="uninstall"
    echo "选择卸载模式，开始卸载..."
    # 执行卸载操作
    # 你可以把原来的卸载代码放到这个部分
    ;;
  3)
    echo "退出脚本。"
    exit 0
    ;;
  *)
    echo "无效的选择，退出程序。"
    exit 1
    ;;
esac

# 安装 Nginx 的函数
install_nginx() {
# 创建安装目录和源码目录
mkdir -p $SRC_DIR

# 安装编译 Nginx 所需的依赖
echo "安装编译 Nginx 所需的依赖..."
apt-get update
apt-get install -y \
    apt-utils \
    build-essential \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libaio-dev \
    libjemalloc-dev \
    libgd-dev \
    libgeoip-dev \
    libxslt1-dev \
    libbrotli-dev \
    libcurl4-openssl-dev \
    libyaml-dev \
    unzip \
    git \
    cmake \
    gcc \
    g++ \
    make \
    wget \
    pkg-config \
    libpcre2-dev \
    libpcre2-8-0 \
    liblua5.3-dev \
    libmaxminddb0 \
    libmaxminddb-dev \
    liblmdb-dev \
    libyaml-dev \
    libssl-dev \
    libtool \
    liblzma-dev \
    libgeoip-dev \
    libjemalloc-dev \
    # 安装 Brotli 和 ModSecurity 相关的依赖
    autoconf \
    automake \
    libtool \
    pkg-config \
    libxml2-dev

# 获取最新的稳定版 Nginx 版本
echo "获取最新的稳定版 Nginx 版本..."
NGINX_VERSION=$(wget -qO- https://nginx.org/en/download.html | grep -oP 'nginx-\d+\.\d+\.\d+\.tar\.gz' | head -1 | sed 's/nginx-//;s/.tar.gz//')

# 下载 Nginx 源码包
echo "下载 Nginx 源代码..."
cd $INSTALL_DIR
wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz

# 解压源码
tar -zxvf nginx-${NGINX_VERSION}.tar.gz
rm -f nginx-${NGINX_VERSION}.tar.gz

# 下载并更新所需的模块
echo "下载和更新所需的模块..."

# ngx_cache_purge 模块（最新稳定版）
cd $SRC_DIR
wget https://github.com/FRiCKLE/ngx_cache_purge/archive/refs/tags/2.3.zip
unzip 2.3.zip
mv ngx_cache_purge-2.3 ngx_cache_purge
rm -f 2.3.zip

# ngx_http_headers_more_filter_module 模块（最新稳定版）
cd $SRC_DIR
wget https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v0.38.zip
unzip v0.38.zip
mv headers-more-nginx-module-0.38 headers-more-nginx-module
rm -f v0.38.zip


# ngx_http_proxy_connect_module 模块（最新稳定版）
cd $SRC_DIR
wget https://github.com/chobits/ngx_http_proxy_connect_module/archive/refs/tags/v0.0.7.zip
unzip v0.0.7.zip
mv ngx_http_proxy_connect_module-0.0.7 ngx_http_proxy_connect_module
rm -f v0.0.7.zip


# ngx_brotli 模块（最新稳定版）
cd $SRC_DIR
git clone --recursive https://github.com/google/ngx_brotli.git $SRC_DIR/ngx_brotli
cd ngx_brotli
git submodule update --init
cd ..


# 获取 OpenSSL 最新稳定版版本号
echo "获取最新 OpenSSL 稳定版版本..."
OPENSSL_VERSION=$(wget -qO- https://www.openssl.org/source/ | grep -oP 'openssl-\d+\.\d+\.\d+' | head -1 | sed 's/openssl-//')
cd $SRC_DIR
wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
tar -zxvf openssl-${OPENSSL_VERSION}.tar.gz
mv openssl-${OPENSSL_VERSION} openssl
rm -f openssl-${OPENSSL_VERSION}.tar.gz
cd ..

# 下载并解压 PCRE（必须手动下载和解压）
echo "下载并解压 PCRE..."
cd $SRC_DIR
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.zip
unzip pcre-8.45.zip
rm -f pcre-8.45.zip
cd ..

################################ ModSecurity start ########################################
# 下载 ModSecurity 源码最新稳定版本
mkdir -p $NGINX_DIR/owasp
chown -R root:root $NGINX_DIR/owasp

modsecurity_dir="/usr/local/modsecurity"

# 如果存在，删除/usr/local/modsecurity目录重新安装
if [ -d "$modsecurity_dir" ]; then
    echo "目录 $modsecurity_dir 已存在，正在删除..."
    rm -rf $modsecurity_dir
fi

cd $SRC_DIR

git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity ModSecurity
cd ModSecurity
git submodule init
git submodule update
# 配置 ModSecurity
./build.sh
./configure
make
make install
# 配置文件改名
if [ -f "$SRC_DIR/ModSecurity/modsecurity.conf-recommended" ]; then
        cp "$SRC_DIR/ModSecurity/modsecurity.conf-recommended" "$SRC_DIR/ModSecurity/modsecurity.conf"
fi

# 进入 ModSecurity 源码目录
cd $SRC_DIR

# 下载 ModSecurity-nginx 模块
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

# 设置目录和文件的所有者为 root:root
chown -R root:root $SRC_DIR/ModSecurity-nginx

echo "ModSecurity 和 ModSecurity-nginx 安装及配置完成。"


#################### OWASP核心规则集下载 ###########################################
cd $NGINX_DIR/owasp

# 获取最新版本号
LATEST_VERSION=$(curl -s "https://api.github.com/repos/coreruleset/coreruleset/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
if [ -z "$LATEST_VERSION" ]; then
    echo "无法获取最新版本号。请检查网络连接或稍后重试。"
    exit 1
fi
LATEST_VERSION_NO_V="${LATEST_VERSION//v}"
# 构建下载链接
DOWNLOAD_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/$LATEST_VERSION.tar.gz"

# 下载最新版本的核心规则集
echo "正在下载最新版本：$LATEST_VERSION"
if curl -L -o "coreruleset-$LATEST_VERSION.tar.gz" "$DOWNLOAD_URL"; then
    echo "下载完成：coreruleset-$LATEST_VERSION.tar.gz"

    # 解压文件
    tar -zxvf "coreruleset-$LATEST_VERSION.tar.gz"

    # 检查并重命名文件夹
    if [ -d "coreruleset-$LATEST_VERSION_NO_V" ]; then
        mv "coreruleset-$LATEST_VERSION_NO_V" "owasp-rules"

        # 修改文件夹权限
        chown -R root:root "owasp-rules"

        # 复制文件（如果存在）
        if [ -f "$NGINX_DIR/owasp/owasp-rules/crs-setup.conf.example" ]; then
            cp "$NGINX_DIR/owasp/owasp-rules/crs-setup.conf.example" "$NGINX_DIR/owasp/owasp-rules/crs-setup.conf"
        fi

        # 删除下载的压缩包
        rm -f "coreruleset-$LATEST_VERSION.tar.gz"
    else
        echo "未能找到目录 coreruleset-$LATEST_VERSION_NO_V，无法重命名。"
        exit 1
    fi
else
    echo "下载最新版本 $LATEST_VERSION 失败。"
    exit 1
fi
################### OWASP核心规则集下载-END##################

################### 开启ModSecurity文件-start##################
# 创建引入文件
# 修改配置文件名
mkdir -p $NGINX_DIR/owasp/conf

# 添加wordpress常用的nginx拒绝规则配置文件
wget -c -O $NGINX_DIR/owasp/conf/nginx-wordpress.conf https://gist.githubusercontent.com/nfsarmento/57db5abba08b315b67f174cd178bea88/raw/b0768871c3349fdaf549a24268cb01b2be145a6a/nginx-wordpress.conf -T 20


echo "Downloading WordPress 规则排除插件"
# 下载 wordpress-rule-exclusions-before.conf 和 wordpress-rule-exclusions-config.conf 文件
wget -q -O $NGINX_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/refs/heads/master/plugins/wordpress-rule-exclusions-before.conf"
wget -q -O $NGINX_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/refs/heads/master/plugins/wordpress-rule-exclusions-config.conf"

# 下载 crs-setup.conf 文件并备份旧文件（如果存在）
echo "Downloading crs-setup.conf..."
if [ -f $NGINX_DIR/owasp/owasp-rules/crs-setup.conf ]; then
  mv $NGINX_DIR/owasp/owasp-rules/crs-setup.conf $NGINX_DIR/owasp/owasp-rules/crs-setup.conf.bak  # 备份旧文件
fi
wget -q -O $NGINX_DIR/owasp/owasp-rules/crs-setup.conf "https://raw.githubusercontent.com/mzwrt/aapanel-6.8.37-backup/refs/heads/main/ModSecurity/crs-setup.conf"

#
mv $NGINX_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example $NGINX_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
mv $NGINX_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example $NGINX_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf

# 下载 modsecurity.conf 文件并备份旧文件（如果存在）
echo "Downloading modsecurity.conf..."
if [ -f $SRC_DIR/ModSecurity/modsecurity.conf ]; then
  mv $SRC_DIR/ModSecurity/modsecurity.conf $SRC_DIR/ModSecurity/modsecurity.conf.bak  # 备份旧文件
fi
wget -q -O $SRC_DIR/ModSecurity/modsecurity.conf "https://raw.githubusercontent.com/mzwrt/aapanel-6.8.37-backup/refs/heads/main/ModSecurity/modsecurity.conf"

# 下载 hosts.deny 文件并备份旧文件（如果存在）
echo "Downloading modsecurity.conf..."
if [ -f $NGINX_DIR/owasp/conf/hosts.deny ]; then
  mv $NGINX_DIR/owasp/conf/hosts.deny $NGINX_DIR/owasp/conf/hosts.deny.bak  # 备份旧文件
fi
wget -q -O $NGINX_DIR/owasp/conf/hosts.deny "https://raw.githubusercontent.com/mzwrt/aapanel-6.8.37-backup/refs/heads/main/ModSecurity/hosts.deny"

# 下载 hosts.deny 文件并备份旧文件（如果存在）
echo "Downloading hosts.allow..."
if [ -f $NGINX_DIR/owasp/conf/hosts.allow ]; then
  mv $NGINX_DIR/owasp/conf/hosts.allow $NGINX_DIR/owasp/conf/hosts.allow.bak  # 备份旧文件
fi
wget -q -O $NGINX_DIR/owasp/conf/hosts.allow "https://raw.githubusercontent.com/mzwrt/aapanel-6.8.37-backup/refs/heads/main/ModSecurity/hosts.allow"

# 下载 hosts.deny 文件并备份旧文件（如果存在）
echo "Downloading main.conf..."
if [ -f $NGINX_DIR/owasp/conf/main.conf ]; then
  mv $NGINX_DIR/owasp/conf/main.conf $NGINX_DIR/owasp/conf/main.conf.bak  # 备份旧文件
fi
wget -q -O $NGINX_DIR/owasp/conf/main.conf "https://raw.githubusercontent.com/mzwrt/aapanel-6.8.37-backup/refs/heads/main/ModSecurity/main.conf"

# 规范规则文件权限
echo " 规范文件权限"
chown -R root:root $NGINX_DIR/owasp/conf/*.conf
chown -R root:root $NGINX_DIR/owasp/owasp-rules/plugins/*.conf
chown -R root:root $NGINX_DIR/owasp/owasp-rules/crs-setup.conf
chown -R root:root $SRC_DIR/ModSecurity/modsecurity.conf
chown -R root:root $NGINX_DIR/owasp/conf/hosts.allow
chown -R root:root $NGINX_DIR/owasp/conf/hosts.deny

chmod 600 $NGINX_DIR/owasp/conf/*.conf
chmod 600 $NGINX_DIR/owasp/owasp-rules/plugins/*.conf
chmod 600 $NGINX_DIR/owasp/owasp-rules/crs-setup.conf
chmod 600 $SRC_DIR/ModSecurity/modsecurity.conf
chmod 600 $NGINX_DIR/owasp/owasp-rules/crs-setup.conf.bak
chmod 600 $SRC_DIR/ModSecurity/modsecurity.conf.bak
chmod 600 $NGINX_DIR/owasp/conf/main.conf.bak
chmod 600 $NGINX_DIR/owasp/conf/hosts.allow
chmod 600 $NGINX_DIR/owasp/conf/hosts.deny
################### 开启ModSecurity文件-END##################

# 规范文件权限
chmod 750 $INSTALL_DIR/modules
chmod 640 $INSTALL_DIR/modules/ngx_http_modsecurity_module.so
chmod 600 $SRC_DIR/ModSecurity/modsecurity.conf
chmod 600 $NGINX_DIR/owasp/owasp-rules/crs-setup.conf
chmod 600 $NGINX_DIR/owasp/conf/main.conf
chmod 600 $NGINX_DIR/owasp/conf/nginx-wordpress.conf
chmod 600 $NGINX_DIR/owasp/owasp-rules/rules/*.conf
find $NGINX_DIR/owasp/owasp-rules/ -type f -exec chmod 600 {} \;
######################## ModSecurity END ################################

# 配置编译选项
echo "配置 Nginx 编译选项..."
cd $INSTALL_DIR/nginx-${NGINX_VERSION}
./configure \
  --user=www-data \
  --group=www-data \
  --with-threads \
  --with-file-aio \
  --with-cc-opt='-O2 -fPIE -fPIC --param=ssp-buffer-size=4 -fstack-protector -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2 -march=native -mtune=native' \
  --with-ld-opt='-Wl,-E -flto -march=native -Bsymbolic-functions -fPIE -fPIC -pie -Wl,-z,relro -Wl,-z,now' \
  --prefix=$INSTALL_DIR \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-http_stub_status_module \
  --with-http_ssl_module \
  --with-http_image_filter_module \
  --with-http_gzip_static_module \
  --with-http_gunzip_module \
  --with-http_sub_module \
  --with-http_flv_module \
  --with-http_addition_module \
  --with-http_realip_module \
  --with-http_mp4_module \
  --with-http_auth_request_module \
  --with-ld-opt=-ljemalloc \
  --add-module=$SRC_DIR/ngx_cache_purge \
  --with-openssl=$SRC_DIR/openssl \
  --with-pcre=$SRC_DIR/pcre-8.45 \
  --add-module=$SRC_DIR/ngx_brotli \
  --add-dynamic-module=$SRC_DIR/ModSecurity-nginx \
  --add-module=$SRC_DIR/headers-more-nginx-module \
  --add-module=$SRC_DIR/ngx_http_proxy_connect_module



# 编译 Nginx
echo "开始编译 Nginx..."
make -j"$(nproc)"

# 安装 Nginx
echo "安装 Nginx..."
make install

# 设置 Nginx 服务
echo "设置 Nginx 服务..."
cp $INSTALL_DIR/sbin/nginx /usr/local/bin/nginx
cp $INSTALL_DIR/conf/nginx.conf /etc/nginx/nginx.conf
cp -r $INSTALL_DIR/conf.d /etc/nginx/conf.d
cp -r $INSTALL_DIR/html /usr/share/nginx/html

# 配置系统服务
cat <<EOL > /etc/systemd/system/nginx.service
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStart=/usr/local/bin/nginx -c /etc/nginx/nginx.conf
ExecReload=/usr/local/bin/nginx -s reload
ExecStop=/usr/local/bin/nginx -s stop
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOL

# 重新加载 systemd 并启动 Nginx
echo "重新加载 systemd 并启动 Nginx..."
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# 完成
echo "Nginx 安装完成！可以通过 http://your_server_ip 访问。"
}

# 卸载 Nginx 的函数
uninstall_nginx() {
    # 停止并禁用 Nginx 服务
    echo "停止 Nginx 服务..."
    systemctl stop nginx
    systemctl disable nginx

    # 删除 Nginx 服务文件
    if [ -f "/etc/systemd/system/nginx.service" ]; then
       rm -f /etc/systemd/system/nginx.service
    fi

    # 删除 Nginx 安装目录
    if [ -d "$INSTALL_DIR" ]; then
       rm -rf $INSTALL_DIR
    fi

    # 卸载 ModSecurity 并删除相关文件
    if [ -d "$modsecurity_dir" ]; then
       rm -rf $modsecurity_dir
    fi

    # 删除 Nginx 二进制文件
    if [ -f "/usr/local/bin/nginx" ]; then
       rm -f /usr/local/bin/nginx
    fi

    # 删除 Nginx 配置文件
    if [ -f "/etc/nginx/nginx.conf" ]; then
       rm -f /etc/nginx/nginx.conf
    fi

    # 删除配置文件夹
    if [ -d "/etc/nginx/conf.d" ]; then
       rm -rf /etc/nginx/conf.d
    fi

    # 删除 Nginx 默认网页目录
    if [ -d "/usr/share/nginx/html" ]; then
       rm -rf /usr/share/nginx/html
    fi

    echo "Nginx 卸载完成。"
}

# 根据选择执行安装或卸载
if [ "$MODE" == "install" ]; then
    install_nginx
elif [ "$MODE" == "uninstall" ]; then
    uninstall_nginx
fi
