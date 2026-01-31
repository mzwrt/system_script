#!/bin/bash

# 在脚本执行过程中遇到任何错误时立即退出
set -e

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
  echo "本脚本需要以 root 用户权限运行，请使用 sudo 执行。"
  exit 1
fi

# 定义安装路径和源码路径
# 可指定安装路径
OPT_DIR="/opt"
# 下面路径不可改动
NGINX_DIR="$OPT_DIR/nginx"  # 安装目录
NGINX_SRC_DIR="$OPT_DIR/nginx/src"   # 源代码和模块的存放目录


# ngx-fancyindex 模块
# 设置为 false 即不启用
USE_ngx_fancyindex=false

# PCRE2 模块
# 设置为 false 即不启用
USE_PCRE2=true

# ngx_cache_purge 模块
# 设置为 false 即不启用
USE_ngx_cache_purge=true

# ngx_http_headers_more_filter_module 模块
# 设置为 false 即不启用
USE_ngx_http_headers_more_filter_module=true

# ngx_http_proxy_connect_module 模块
# 设置为 false 即不启用
USE_ngx_http_proxy_connect_module=true

# ngx_brotli 模块
# 设置为 false 即不启用
USE_ngx_brotli=true

# openssl 模块
# 设置为 false 即不启用
USE_openssl=true

# modsecurity 模块
# 设置为 false 即不启用
USE_modsecurity=true

# owasp 规则集下载和添加使用示例
# 设置为 false 即不启用
USE_owasp=true

# modsecurity_nginx  模块
# 设置为 false 即不启用
USE_modsecurity_nginx=true

# 获取 OpenSSL 最新稳定版版本号
# 获取最新 OpenSSL 稳定版版本
#OPENSSL_VERSION=$(wget -qO- --tries=5 --waitretry=2 --no-check-certificate https://www.openssl.org/source/ | grep -oP 'openssl-\d+\.\d+\.\d+' | head -1 | sed 's/openssl-//')
# 手动指定版本号
OPENSSL_VERSION=3.5.4

# 手动指定 NGINX 版本
# NGINX_VERSION=1.28.1
# 这个是获取最新稳定版
NGINX_VERSION=$(wget -qO- --tries=5 --waitretry=2 --no-check-certificate https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\d+\.\d+\.\d+' | head -n 1 | grep -oP '\d+\.\d+\.\d+')
# 获取 Nginx 主线版本
#NGINX_VERSION=$(curl -s --retry 5 --retry-delay 2 --no-check-certificate  --retry-connrefused -L https://nginx.org/en/download.html | grep -oP 'Mainline version.*?nginx-\d+\.\d+\.\d+' | head -n 1 | sed -E 's/.*nginx-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')


# 创建 $NGINX_DIR/src 目录
if [ ! -d "$NGINX_SRC_DIR" ]; then
    mkdir -p "$NGINX_SRC_DIR"
    chmod 750 "$NGINX_SRC_DIR"
    chown -R root:root "$NGINX_SRC_DIR"
fi

ngx_fancyindex_install() {
# 获取 ngx-fancyindex- 最新稳定版版本号
#echo "获取最新 OpenSSL 稳定版版本..."
#fancyindex_VERSION=$(wget --tries=5 --waitretry=2 --no-check-certificate -qO- https://www.openssl.org/source/ | grep -oP 'openssl-\d+\.\d+\.\d+' | head -1 | sed 's/openssl-//')
fancyindex_VERSION=0.5.2
cd $NGINX_SRC_DIR || exit 1
wget --tries=5 --waitretry=2 --no-check-certificate https://github.com/aperezdc/ngx-fancyindex/releases/download/v${fancyindex_VERSION}/ngx-fancyindex-${fancyindex_VERSION}.tar.xz
tar -xJvf ngx-fancyindex-${fancyindex_VERSION}.tar.xz
mv ngx-fancyindex-${fancyindex_VERSION} ngx_fancyindex
rm -f ngx-fancyindex-${fancyindex_VERSION}.tar.xz
}

openssl_install() {
# 获取 OpenSSL 最新稳定版版本号
#echo "获取最新 OpenSSL 稳定版版本..."
#OPENSSL_VERSION=$(wget -qO- --tries=5 --waitretry=2 --no-check-certificate https://www.openssl.org/source/ | grep -oP 'openssl-\d+\.\d+\.\d+' | head -1 | sed 's/openssl-//')
#OPENSSL_VERSION=3.5.4
cd $NGINX_SRC_DIR || exit 1
wget --tries=5 --waitretry=2 --no-check-certificate https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
tar -zxvf openssl-${OPENSSL_VERSION}.tar.gz
mv openssl-${OPENSSL_VERSION} openssl
rm -f openssl-${OPENSSL_VERSION}.tar.gz
cd ..
}

ngx_brotli_install() {
# ngx_brotli 模块（最新稳定版）
cd $NGINX_SRC_DIR || exit 1
git clone --recursive https://github.com/google/ngx_brotli.git $NGINX_SRC_DIR/ngx_brotli
cd ngx_brotli  || exit 1
git submodule update --init
}

ngx_http_proxy_connect_module_install() {
# ngx_http_proxy_connect_module 模块（最新稳定版）
# 获取最新 tag（版本号）
cd $NGINX_SRC_DIR || exit 1

ngx_http_proxy_connect_module_version=$(curl -s --retry 5 --retry-delay 2  --retry-connrefused -L https://api.github.com/repos/chobits/ngx_http_proxy_connect_module/tags | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4)

if [ -z "$ngx_http_proxy_connect_module_version" ]; then
  echo "错误：未能获取 ngx_http_proxy_connect_module 的最新版本"
  exit 1
fi

# 下载并解压模块
wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/chobits/ngx_http_proxy_connect_module/archive/refs/tags/$ngx_http_proxy_connect_module_version.zip"
if [ $? -ne 0 ]; then
  echo "错误：下载 ngx_http_proxy_connect_module 失败"
  exit 1
fi

unzip $ngx_http_proxy_connect_module_version.zip
if [ $? -ne 0 ]; then
  echo "错误：解压 ngx_http_proxy_connect_module 失败"
  exit 1
fi

rm -f $ngx_http_proxy_connect_module_version.zip
mv ngx_http_proxy_connect_module-${ngx_http_proxy_connect_module_version#v} ngx_http_proxy_connect_module

# 应用补丁
cd $NGINX_DIR || exit 1
cp $NGINX_DIR/src/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch $NGINX_DIR/nginx
cd nginx || exit 1

patch -p1 -f < proxy_connect_rewrite_102101.patch
if [ $? -ne 0 ]; then
  echo "错误：ngx_http_proxy_connect_module 模块应用补丁失败"
  exit 1
fi

# 删除补丁文件
if [ -f proxy_connect_rewrite_102101.patch ]; then
  rm -rf proxy_connect_rewrite_102101.patch
else
  echo "补丁文件未找到，跳过删除。"
fi
}

ngx_http_headers_more_filter_module_install() {
  # ngx_http_headers_more_filter_module 模块（获取最新版本）
  cd "$NGINX_SRC_DIR" || exit 1

  # 获取最新 tag（版本号），例如 v0.38
  #ngx_http_headers_more_filter_module_version="v0.38" # 制定版本使用
  ngx_http_headers_more_filter_module_version=$(curl -s --retry 5 --retry-delay 2  --retry-connrefused -L https://api.github.com/repos/openresty/headers-more-nginx-module/tags | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4 | sed 's/^v//') # 默认自动获取最新版

  # 下载并解压 .tar.gz
  wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${ngx_http_headers_more_filter_module_version}.tar.gz"
  tar -xzf "v${ngx_http_headers_more_filter_module_version}.tar.gz"
  mv "headers-more-nginx-module-${ngx_http_headers_more_filter_module_version#v}" headers-more-nginx-module
  rm -f "v${ngx_http_headers_more_filter_module_version}.tar.gz"
}


ngx_cache_purge_install() {
    # 获取最新版本标签
    #ngx_cache_purge_version="2.3" # 制定版本使用
    ngx_cache_purge_version=$(curl -s --retry 5 --retry-delay 2  --retry-connrefused -L https://api.github.com/repos/FRiCKLE/ngx_cache_purge/tags | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4) # 默认自动获取最新版

    cd "$NGINX_SRC_DIR" || { echo "无法切换到 ngx_cache_purge 目录 $NGINX_SRC_DIR"; exit 1; }

    # 下载对应版本的 ZIP 文件
    wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/FRiCKLE/ngx_cache_purge/archive/refs/tags/$ngx_cache_purge_version.zip" || { echo "下载 ngx_cache_purge 版本 $ngx_cache_purge_version 失败"; exit 1; }

    # 解压下载的文件
    unzip "$ngx_cache_purge_version.zip" || { echo "解压 ngx_cache_purge 文件失败"; exit 1; }

    # 重命名文件夹
    mv "ngx_cache_purge-$ngx_cache_purge_version" ngx_cache_purge || { echo "重命名 ngx_cache_purge 文件夹失败"; exit 1; }

    # 删除 ZIP 文件
    rm -f "$ngx_cache_purge_version.zip" || { echo "删除 ngx_cache_purge ZIP 文件失败"; exit 1; }
}


# PCRE2 模块下载
pcre2_install() {
    echo "正在获取 PCRE2 最新版本..."
    #pcre2_version="pcre2-10.45" # 制定版本使用
    pcre2_version=$(curl -sSL --retry 5 --retry-delay 2  --retry-connrefused -L https://api.github.com/repos/PhilipHazel/pcre2/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+') # 默认自动获取最新版

    if [ -z "$pcre2_version" ]; then
        echo "获取 PCRE2 版本失败，请检查网络连接或 GitHub API。"
        exit 1
    fi

    cd "$NGINX_SRC_DIR" || exit 1

    if [ -d "pcre2" ]; then
        echo "pcre2 目录已存在，跳过安装。"
        return
    fi

    echo "正在下载并安装 PCRE2：$pcre2_version"
    wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/PhilipHazel/pcre2/releases/download/$pcre2_version/$pcre2_version.tar.gz"

    if [ ! -f "$pcre2_version.tar.gz" ]; then
        echo "下载 pcre2 失败，请检查链接或网络。"
        exit 1
    fi

    tar -zxf "$pcre2_version.tar.gz" || { echo "解压 pcre2 文件失败"; exit 1; }
    mv "$pcre2_version" pcre2 || { echo "重命名 pcre2 文件夹失败"; exit 1; }
    rm -f "$pcre2_version.tar.gz" || { echo "删除 pcre2 tar.gz 文件失败"; exit 1; }
}

modsecurity_install() {
modsecurity_dir_install="/usr/local/modsecurity"
# 如果存在，删除/usr/local/modsecurity目录重新安装
if [ -d "$modsecurity_dir_install" ]; then
    echo "目录 $modsecurity_dir_install 已存在，正在删除..."
    rm -rf $modsecurity_dir_install
fi

cd $NGINX_SRC_DIR || exit 1

git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity ModSecurity
cd ModSecurity || exit 1
git submodule update --recursive
git submodule init
git submodule update
# 配置 ModSecurity（禁用 jemalloc）
# jemalloc 与 ModSecurity 不兼容
# 所以添加 JEMALLOC_CFLAGS="" JEMALLOC_LIBS="" 和 --disable-shared 
# 让 ModSecurity 变为静态模块
./build.sh
./configure --with-pcre2
make -j$(nproc) || make
make install
# 下载 modsecurity.conf 文件并备份旧文件（如果存在）
echo "Downloading modsecurity.conf..."
if [ -f $NGINX_SRC_DIR/ModSecurity/modsecurity.conf ]; then
  mv -f $NGINX_SRC_DIR/ModSecurity/modsecurity.conf $NGINX_SRC_DIR/ModSecurity/modsecurity.conf.bak  # 备份旧文件
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O $NGINX_SRC_DIR/ModSecurity/modsecurity.conf "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/ModSecurity/modsecurity.conf"

# 规范文件权限
chown root:root $NGINX_SRC_DIR/ModSecurity/modsecurity.conf
chmod 600 $NGINX_SRC_DIR/ModSecurity/modsecurity.conf
if [ -f $NGINX_SRC_DIR/ModSecurity/modsecurity.conf.bak ]; then
  chmod 600 $NGINX_SRC_DIR/ModSecurity/modsecurity.conf.bak
fi
}

modsecurity_nginx_install() {
# 进入 ModSecurity 源码目录
cd $NGINX_SRC_DIR || exit 1

# 下载 ModSecurity-nginx 模块
git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git
chown -R root:root $NGINX_SRC_DIR/ModSecurity-nginx
}

owasp_install() {
# OWASP核心规则集下载-start 
# 下载 owasp 源码最新稳定版本
mkdir -p $OPT_DIR/owasp
chown -R root:root $OPT_DIR/owasp
# OWASP核心规则集下载 
cd $OPT_DIR/owasp  || exit 1

# 获取最新版本号
# 获取版本号
owasp_VERSION=$(curl -s --retry 5 --retry-delay 2  --retry-connrefused -L "https://api.github.com/repos/coreruleset/coreruleset/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
if [ -z "$owasp_VERSION" ]; then
    echo "无法获取最新版本号。请检查网络连接或稍后重试。"
    exit 1
fi

owasp_VERSION_NO_V="${owasp_VERSION//v}"
owasp_DOWNLOAD_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/$owasp_VERSION.tar.gz"

echo "正在下载最新版本：$owasp_VERSION"
if curl -L --retry 5 --retry-delay 2  --retry-connrefused -L -o "coreruleset-$owasp_VERSION.tar.gz" "$owasp_DOWNLOAD_URL"; then
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
mkdir -p $OPT_DIR/owasp/conf
mkdir -p "$OPT_DIR/owasp/owasp-rules/plugins"

# 添加 WordPress 常用的 Nginx 拒绝规则配置文件
if [ ! -f $OPT_DIR/owasp/conf/nginx-wordpress.conf ]; then
   wget -c -T 20 --tries=5 --waitretry=2 --no-check-certificate -O $OPT_DIR/owasp/conf/nginx-wordpress.conf \
   https://gist.githubusercontent.com/nfsarmento/57db5abba08b315b67f174cd178bea88/raw/b0768871c3349fdaf549a24268cb01b2be145a6a/nginx-wordpress.conf
fi

echo "Downloading WordPress 规则排除插件"
# 下载 wordpress-rule-exclusions-before.conf 和 wordpress-rule-exclusions-config.conf 文件
if [ ! -f $OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O $OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf \
  https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-before.conf
fi

if [ ! -f $OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O $OPT_DIR/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf \
  https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-config.conf
fi

# 重命名排除规则样例文件
if [ -f $OPT_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example ]; then
  mv $OPT_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
     $OPT_DIR/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
fi
if [ -f $OPT_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example ]; then
  mv -f $OPT_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example \
        $OPT_DIR/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
fi

# 下载 hosts.deny 文件并备份旧文件（如果存在）
echo "Downloading hosts.deny..."
if [ -f $OPT_DIR/owasp/conf/hosts.deny ]; then
  mv -f $OPT_DIR/owasp/conf/hosts.deny $OPT_DIR/owasp/conf/hosts.deny.bak
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O $OPT_DIR/owasp/conf/hosts.deny \
https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/hosts.deny

# 下载 hosts.allow 文件并备份旧文件（如果存在）
echo "Downloading hosts.allow..."
if [ -f $OPT_DIR/owasp/conf/hosts.allow ]; then
  mv -f $OPT_DIR/owasp/conf/hosts.allow $OPT_DIR/owasp/conf/hosts.allow.bak
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O $OPT_DIR/owasp/conf/hosts.allow \
https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/hosts.allow

# 下载 main.conf 文件并备份旧文件（如果存在）
echo "Downloading main.conf..."
if [ -f $OPT_DIR/owasp/conf/main.conf ]; then
  mv -f $OPT_DIR/owasp/conf/main.conf $OPT_DIR/owasp/conf/main.conf.bak
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O $OPT_DIR/owasp/conf/main.conf \
https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/main.conf


# 规范规则文件权限
echo " 规范文件权限"
# 所有 .conf 文件设置为 root 权限 600
find "$OPT_DIR/owasp/conf" -type f -name "*.conf" -exec chmod 600 {} \; -exec chown root:root {} \;
find "$OPT_DIR/owasp/conf" -type f -name "*.conf.bak" -exec chmod 600 {} \; -exec chown root:root {} \;
# 所有文件夹设置为 700
find "$OPT_DIR/owasp" -type d -exec chmod 700 {} \;
chown -R root:root "$OPT_DIR/owasp"

chown -R root:root $OPT_DIR/owasp/conf/hosts.allow
chown -R root:root $OPT_DIR/owasp/conf/hosts.deny
chmod 600 $OPT_DIR/owasp/conf/hosts.allow
chmod 600 $OPT_DIR/owasp/conf/hosts.deny
}

# 安装 Nginx 的函数
install_nginx() {

read -p "您喜欢将nginx伪装成一个什么名字 禁止使用任何特殊符号仅限英文大小写和空格（例如：OWASP WAF） 留空将不修改使用默认值 默认值是ngixn： " nginx_fake_name
read -p "请输入自定义的nginx版本号（例如：5.1.24）留空将不修改使用默认版本号： " nginx_version_number

# 安装编译 Nginx 所需的依赖
echo "安装编译 Nginx 所需的依赖..."
apt-get update
apt-get install -y \
    apt-utils \
    build-essential \
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
    libtool \
    liblzma-dev \
    autoconf \
    automake \
    gawk \
    libyajl-dev \
    libxml2-dev || { echo "依赖安装失败，开始卸载..."; uninstall_nginx; exit 1; }

# 这个是获取最新稳定版
#NGINX_VERSION=$(wget -qO- --tries=5 --waitretry=2 --no-check-certificate https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\d+\.\d+\.\d+' | head -n 1 | grep -oP '\d+\.\d+\.\d+')

# 获取 Nginx 主线版本
#NGINX_VERSION=$(curl -s --retry 5 --retry-delay 2  --retry-connrefused -L https://nginx.org/en/download.html | grep -oP 'Mainline version.*?nginx-\d+\.\d+\.\d+' | head -n 1 | sed -E 's/.*nginx-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$NGINX_VERSION" ]; then
    echo "未能获取 Nginx 主线版本，请检查下载页面结构"
    exit 1
fi

# 下载 Nginx 源码包
echo "下载 Nginx 源代码..."
cd $NGINX_DIR || exit 1
wget --tries=5 --waitretry=2 --no-check-certificate https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz || { echo "nginx下载失败"; exit 1; }

# 解压源码
tar -zxvf nginx-${NGINX_VERSION}.tar.gz
if [ -d "$NGINX_DIR/nginx" ]; then
    rm -rf $NGINX_DIR/nginx
fi
mv nginx-${NGINX_VERSION} nginx
chown -R root:root $NGINX_DIR/nginx
rm -f nginx-${NGINX_VERSION}.tar.gz


# 替换 Nginx 版本信息和错误页标签
if [ -n "$nginx_fake_name" ] || [ -n "$nginx_version_number" ]; then
    # 处理特殊字符，但不替换空格
    nginx_fake_name=$(echo "$nginx_fake_name" | sed 's/[&/\]/\\&/g')
    nginx_version_number=$(echo "$nginx_version_number" | sed 's/[&/\]/\\&/g')

    # 替换 HTTP 响应头的 server 参数
    if [ -n "$nginx_fake_name" ]; then
        sed -i "s/static u_char ngx_http_server_string\[\] = \"Server: nginx\" CRLF;/static u_char ngx_http_server_string\[\] = \"Server: ${nginx_fake_name}\" CRLF;/g" $NGINX_DIR/nginx/src/http/ngx_http_header_filter_module.c
        sed -i "s/static u_char ngx_http_server_full_string\[\] = \"Server: \" NGINX_VER CRLF;/static u_char ngx_http_server_full_string\[\] = \"Server: ${nginx_fake_name}\" CRLF;/g" $NGINX_DIR/nginx/src/http/ngx_http_header_filter_module.c
        sed -i "s/static u_char ngx_http_server_build_string\[\] = \"Server: \" NGINX_VER_BUILD CRLF;/static u_char ngx_http_server_build_string\[\] = \"Server: ${nginx_fake_name}\" CRLF;/g" $NGINX_DIR/nginx/src/http/ngx_http_header_filter_module.c
    fi

    # 替换 默认错误页的底部标签
    if [ -n "$nginx_fake_name" ]; then
        sed -i "s/<hr><center>\" NGINX_VER_BUILD \"<\/center>\" CRLF/<hr><center>${nginx_fake_name}<\/center>\" CRLF/" $NGINX_DIR/nginx/src/http/ngx_http_special_response.c
        sed -i "s/<hr><center>nginx<\/center>\" CRLF/<hr><center>${nginx_fake_name}<\/center>\" CRLF/" $NGINX_DIR/nginx/src/http/ngx_http_special_response.c
        sed -i "s/<hr><center>\" NGINX_VER \"<\/center>\" CRLF/<hr><center>${nginx_fake_name}<\/center>\" CRLF/" $NGINX_DIR/nginx/src/http/ngx_http_special_response.c
    fi

    # 替换 整体宏标签
    # 注释掉替换 NGINX_VERSION，因为这个已经不必要
    # if [ -n "$nginx_version_number" ]; then
    #     sed -i "s/#define NGINX_VERSION      \".*\"/#define NGINX_VERSION      \"${nginx_version_number}\"/" $NGINX_DIR/nginx/src/core/nginx.h
    # fi

    # if [ -n "$nginx_fake_name" ]; then
    #     sed -i "s/#define NGINX_VER          \"nginx\/\" NGINX_VERSION/#define NGINX_VER          \"${nginx_fake_name}\"/" $NGINX_DIR/nginx/src/core/nginx.h
    # fi

    # 输出替换结果
    if [ -n "$nginx_fake_name" ]; then
        echo "Nginx 伪装名称已设置为: \"$nginx_fake_name\""
    fi

    if [ -n "$nginx_version_number" ]; then
        echo "自定义版本号已设置为: $nginx_version_number"
    fi
else
    echo "未输入任何修改信息，文件未做任何更改。"
fi
# 替换nginx信息 EMD


# 下载并更新所需的模块
echo "下载和更新所需的模块..."

# ngx_cache_purge 模块控制
if [ "$USE_ngx_cache_purge" == "true" ]; then
    echo "正在安装 ngx_cache_purge..."
    ngx_cache_purge_install
    ngx_cache_purge_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_cache_purge"
else
    echo "跳过 ngx_cache_purge 安装..."
    ngx_cache_purge_CONFIG=""
fi

# ngx_http_headers_more_filter_module 模块控制
if [ "$USE_ngx_http_headers_more_filter_module" == "true" ]; then
    echo "正在安装 ngx_http_headers_more_filter_module..."
    ngx_http_headers_more_filter_module_install
    ngx_http_headers_more_filter_module_CONFIG="--add-module=$NGINX_SRC_DIR/headers-more-nginx-module"
else
    echo "跳过 ngx_cache_purge 安装..."
    ngx_http_headers_more_filter_module_CONFIG=""
fi

# ngx_http_proxy_connect_module 模块控制
if [ "$USE_ngx_http_proxy_connect_module" == "true" ]; then
    echo "正在安装 ngx_http_proxy_connect_module..."
    ngx_http_proxy_connect_module_install
    ngx_http_proxy_connect_module_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_http_proxy_connect_module"
else
    echo "跳过 ngx_http_proxy_connect_module 安装..."
    ngx_http_proxy_connect_module_CONFIG=""
fi

# PCRE2 模块控制
if [ "$USE_PCRE2" == "true" ]; then
    echo "正在安装 PCRE2..."
    pcre2_install
    PCRE2_CONFIG="--with-pcre=$NGINX_SRC_DIR/pcre2"
else
    echo "跳过 PCRE2 安装..."
    PCRE2_CONFIG=""
fi

# ngx_brotli 模块控制
if [ "$USE_ngx_brotli" == "true" ]; then
    echo "正在安装 ngx_brotli..."
    ngx_brotli_install
    ngx_brotli_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_brotli"
else
    echo "跳过 ngx_brotli 安装..."
    ngx_brotli_CONFIG=""
fi

# ngx_fancyindex 模块控制
if [ "$USE_ngx_fancyindex" == "true" ]; then
    echo "正在安装 openssl..."
    ngx_fancyindex_install
    ngx_fancyindex_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_fancyindex"
else
    echo "跳过 openssl 安装..."
    ngx_fancyindex_CONFIG=""
fi

# openssl 模块控制
if [ "$USE_openssl" == "true" ]; then
    echo "正在安装 openssl..."
    openssl_install
    openssl_CONFIG="--with-openssl=$NGINX_SRC_DIR/openssl"
else
    echo "跳过 openssl 安装..."
    openssl_CONFIG=""
fi

# modsecurity 模块控制
if [ "$USE_modsecurity" == "true" ]; then
    echo "正在安装 modsecurity..."
    modsecurity_install
else
    echo "跳过 modsecurity 安装..."
fi

# modsecurity_nginx 模块控制
if [ "$USE_modsecurity_nginx" == "true" ]; then
    echo "正在安装 modsecurity_nginx..."
    modsecurity_nginx_install
    # 因为与jemalloc不兼容，所以改为静态模块
    #modsecurity_nginx_CONFIG="--add-dynamic-module=$NGINX_SRC_DIR/ModSecurity-nginx"
    modsecurity_nginx_CONFIG="--add-module=$NGINX_SRC_DIR/ModSecurity-nginx"
else
    echo "跳过 modsecurity_nginx 安装..."
    modsecurity_nginx_CONFIG=""
fi

# owasp 模块控制
if [ "$USE_owasp" == "true" ]; then
    echo "正在安装 owasp..."
    owasp_install
else
    echo "跳过 owasp 安装..."
fi


# 将目录的所有权设置为 root 用户
chown -R root:root $NGINX_DIR



# 配置编译选项
echo "配置 Nginx 编译选项..."
cd $NGINX_DIR/nginx || exit 1
./configure \
  --prefix=$NGINX_DIR \
  --user=www-data \
  --group=www-data \
  --with-threads \
  --with-file-aio \
  --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_auth_request_module \
  --with-http_sub_module \
  --with-http_flv_module \
  --with-http_mp4_module \
  --with-http_addition_module \
  --with-http_image_filter_module \
  --with-http_gunzip_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-compat \
  --with-cc-opt='-O3 -pipe -fPIE -fPIC -march=native -mtune=native -flto=auto -fstack-protector-strong -Wformat -Werror=format-security -D_FORTIFY_SOURCE=3' \
  --with-ld-opt='-ljemalloc -flto=auto -fPIE -fPIC -pie -Wl,-z,relro,-z,now -Wl,-O2 -Wl,--as-needed' \
  $ngx_cache_purge_CONFIG \
  $ngx_brotli_CONFIG \
  $ngx_http_headers_more_filter_module_CONFIG \
  $ngx_http_proxy_connect_module_CONFIG \
  $modsecurity_nginx_CONFIG \
  $openssl_CONFIG \
  $PCRE2_CONFIG \
  $ngx_fancyindex_CONFIG

# 编译 Nginx
echo "开始编译 Nginx..."
make -j$(nproc)

# 安装 Nginx
echo "安装 Nginx..."
make install

# 根据modsecurity官方文档定义文件权限 
[ -d "$NGINX_DIR/modules" ] && chmod 750 "$NGINX_DIR/modules"
[ -f "$NGINX_DIR/modules/ngx_http_modsecurity_module.so" ] && chmod 640 "$NGINX_DIR/modules/ngx_http_modsecurity_module.so"
[ -f "$NGINX_DIR/modules/ngx_stream_module.so" ] && chmod 640 "$NGINX_DIR/modules/ngx_stream_module.so"
[ -f "$NGINX_DIR/modules/ngx_http_image_filter_module.so" ] && chmod 640 "$NGINX_DIR/modules/ngx_http_image_filter_module.so"
# END 

# 设置 Nginx 服务
echo "设置 Nginx 服务..."
cp -f $NGINX_DIR/sbin/nginx /usr/local/bin/nginx

if [ -d "$NGINX_DIR/nginx/conf" ] && [ ! -d "$NGINX_DIR/conf" ]; then
    cp -r "$NGINX_DIR/nginx/conf" "$NGINX_DIR/conf"
    find "$NGINX_DIR/conf" -type d -exec chmod 700 {} \;
    find "$NGINX_DIR/conf" -type f -exec chmod 600 {} \;
fi


# 创建ssl证书文件夹
if [ ! -d "$NGINX_DIR/ssl" ]; then
    mkdir -p "$NGINX_DIR/ssl"
    chmod 700 $NGINX_DIR/ssl
    chown root:root $NGINX_DIR/ssl
fi

# 根据 CIS nginx 2.4.2
# 创建默认网站证书文件夹
if [ ! -d "$NGINX_DIR/ssl/default" ]; then
    mkdir -p "$NGINX_DIR/ssl/default"
    chmod 700 "$NGINX_DIR/ssl/default"
    chown root:root "$NGINX_DIR/ssl/default"
fi

# 根据 CIS nginx 2.4.2
# 创建默认证书
if [ ! -f $NGINX_DIR/ssl/default/default.key ] || [ ! -f $NGINX_DIR/ssl/default/default.pem ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout $NGINX_DIR/ssl/default/default.key \
      -out $NGINX_DIR/ssl/default/default.pem \
      -subj "/C=XX/ST=Default/L=Default/O=Default/CN=localhost"
    chmod 400 $NGINX_DIR/ssl/default/default.key 
    chmod 600 $NGINX_DIR/ssl/default/default.pem
fi

# 创建网站配置文件文件夹
for dir in conf.d conf.d/sites-available conf.d/sites-enabled; do
    conf_d_full_path="$NGINX_DIR/$dir"
    if [ ! -d "$conf_d_full_path" ]; then
        mkdir -p "$conf_d_full_path"
        chmod 700 "$conf_d_full_path"
        chown root:root "$conf_d_full_path"
    fi
done

# 创建网站根目录文件夹
if [ ! -d "/www/wwwroot" ]; then
    mkdir -p /www/wwwroot
    chmod -R 755 /www
    chown -R root:root /www
fi

# 根据 CIS nginx 2.5.2
# 创建默认页目录及文件
if [ ! -d "/www/wwwroot/html" ]; then
    mkdir -p /www/wwwroot/html
    wget -q --tries=5 --waitretry=2 --no-check-certificate -O "/www/wwwroot/html/index.html" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/index.html"
fi
# 设置属主
chown -R www-data:www-data /www/wwwroot/html
# 设置目录权限，确保可读取和进入
chmod 755 /www/wwwroot/html
# 所有文件只读
find /www/wwwroot/html -type f -exec chmod 444 {} \;

# 配置系统服务
wget -q --tries=5 --waitretry=2 --no-check-certificate -O /etc/systemd/system/nginx.service "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/nginx.service"
# 替换文件中的 $NGINX_DIR 为实际的路径
sed -i "s|\\%NGINX_DIR%|$NGINX_DIR|g" "/etc/systemd/system/nginx.service"

# 创建 pid 文件
touch "$NGINX_DIR/logs/nginx.pid"
chmod u-x,go-wx "$NGINX_DIR/logs/nginx.pid"

# 如果 proxy.conf 代理优化配置文件
if [ ! -f "$NGINX_DIR/conf/proxy.conf" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$NGINX_DIR/conf/proxy.conf" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/proxy.conf"
  # 替换文件内容中的 $NGINX_DIR（写成 \$NGINX_DIR）为实际路径
  sed -i "s|\\%NGINX_DIR%|$NGINX_DIR|g" "$NGINX_DIR/conf/proxy.conf"
fi

# 如果 cloudflare_ip.sh 代理优化配置文件
# 判断 cloudflare_ip.sh 文件是否存在，若存在则删除
if [ -f "/root/cloudflare_ip.sh" ]; then
  rm -f "/root/cloudflare_ip.sh"
fi
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "/root/cloudflare_ip.sh" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/cloudflare_ip.sh"
  # 替换文件内容中的 $NGINX_DIR（写成 \$NGINX_DIR）为实际路径
  sed -i "s|\\%NGINX_DIR%|$NGINX_DIR|g" "/root/cloudflare_ip.sh"
    # 给 cloudflare_ip.sh 文件添加执行权限
  chmod +x "/root/cloudflare_ip.sh"
  chmod 600 "/root/cloudflare_ip.sh"
  chown root:root "/root/cloudflare_ip.sh"
  # 运行 添加获取真实IP文件
   echo "#Cloudflare" > $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  for i in `curl https://www.cloudflare.com/ips-v4`; do
          echo "set_real_ip_from $i;" >> $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  done
  for i in `curl https://www.cloudflare.com/ips-v6`; do
          echo "set_real_ip_from $i;" >> $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  done
  echo "" >> $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  echo "# use any of the following two" >> $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  echo "real_ip_header CF-Connecting-IP;" >> $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  echo "#real_ip_header X-Forwarded-For;" >> $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf;
  chmod 600 $NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf
  if [ -f "$NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf" ]; then
    ln -s "$NGINX_DIR/conf.d/sites-available/cloudflare_ip.conf" "$NGINX_DIR/conf.d/sites-enabled/cloudflare_ip.conf"
  fi
  # 添加每月1号执行的定时任务
  echo "0 0 1 * * /root/cloudflare_ip.sh && (crontab -l | grep -v '/root/cloudflare_ip.sh' | crontab -)" | crontab -


# 设置 nginx 用户
\mv -f "$NGINX_DIR/conf/nginx.conf" "$NGINX_DIR/conf/nginx.conf.bak"
wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$NGINX_DIR/conf/nginx.conf" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/nginx.conf"
# 替换文件中的 $NGINX_DIR 为实际的路径
sed -i "s|\\%NGINX_DIR%|$NGINX_DIR|g" "$NGINX_DIR/conf/nginx.conf"

# php 配置文件 -- START
# 下载 pathinfo.conf 为后期开启 PHP 作准备
if [ ! -f "$NGINX_DIR/conf/pathinfo.conf" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$NGINX_DIR/conf/pathinfo.conf" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/php/pathinfo.conf"
  chmod 600 $NGINX_DIR/conf/pathinfo.conf
fi

# 下载 enable-php-84.conf 为后期开启 PHP 作准备 
if [ ! -f "$NGINX_DIR/conf/enable-php-84.conf" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$NGINX_DIR/conf/enable-php-84.conf" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/php/enable-php-84.conf"
  chmod 600 $NGINX_DIR/conf/enable-php-84.conf
fi
# php 配置文件 -- END

# 日志配置
if [ ! -f "/etc/logrotate.d/nginx" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "/etc/logrotate.d/nginx" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/nginx"
  # 替换文件内容中的 $NGINX_DIR（写成 \$NGINX_DIR）为实际路径
  sed -i "s|\\%NGINX_DIR%|$NGINX_DIR|g" "/etc/logrotate.d/nginx"
fi

# 添加网站添加脚本
if [ ! -f "/root/site.sh" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "/root/site.sh" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/site.sh"
  # 替换文件内容中的 $NGINX_DIR（写成 \$NGINX_DIR）为实际路径
  sed -i "s|/opt|$OPT_DIR|g" "/root/site.sh"
  chmod 600 /root/site.sh
fi

# 规范文件权限
find $NGINX_DIR/conf -type d -exec chmod 700 {} \;
find $NGINX_DIR/conf -type f -exec chmod 600 {} \;
find $NGINX_DIR/conf.d -type d -exec chmod 600 {} \;
find $NGINX_DIR/conf.d -type f -exec chmod 600 {} \;

# 重新加载 systemd 并启动 Nginx
echo "重新加载 systemd 并启动 Nginx..."
systemctl daemon-reload
systemctl enable nginx
sleep 2  # 确保 daemon-reload 完全执行
nginx -t  || true

# 直接执行启动命令，即使失败也继续执行
systemctl start nginx || true

# 完成
echo "############# 安装说明 ################"
echo "🎉 恭喜 nginx 安装完成"
echo "📁 nginx 安装目录：$NGINX_DIR"
echo "📄 网站配置文件存放目录：$NGINX_DIR/conf.d"
echo "🔒 网站SSL证书存放目录：$NGINX_DIR/ssl"
echo "🌐 网站根目录：/www/wwwroot"
echo "🛡️ ModSecurity防火墙配置文件目录：$OPT_DIR/owasp/conf"
echo "⚠️ 注意：未配置默认网站，不能直接访问IP"
echo "⚠📢 网站配置文件详解："
echo "   $NGINX_DIR/conf.d/sites-available  —— 存放网站配置原始文件"
echo "   $NGINX_DIR/conf.d/sites-enabled    —— 启用的网站配置文件软连接"
echo "🧠 创建网站流程："
echo "   在 sites-available 文件夹内创建网站配置文件。"
echo "   使用 ln -s 将配置文件软连接到 sites-enabled 文件夹内启用网站。"
echo "   停用网站只需删除 sites-enabled 内的软连接即可，便于管理。"
echo "   路径 /root/cloudflare_ip.sh 脚本用于获取用户真实IP添加每月执行一次"
echo "#####################################"
# 是否删除网站根目录
read -p "是否加网站？Y将运行添加网站脚本，N退出 (y/n): " ADD_WEB_INSTALL
echo "#####################################"
if [[ "$ADD_WEB_INSTALL" =~ ^[Yy]$ ]]; then
    bash /root/site.sh
else
    echo "##################################################"
    echo "🚫 已取消添加网站"
    echo "🔁 添加网站脚本位置：/root/site.sh "
    echo "🎯 需要添加/删除网站直接运行：bash /root/site.sh "
    echo "📌 你可以将它放到任意位置和改为自己喜欢的名字以 .sh 结尾即可 "
    echo "##################################################"

fi

}


# 升级 Nginx 的函数
upgrade_nginx() {
  echo "正在升级 Nginx..."

  # 停止nginx
  systemctl stop nginx

  read -p "您喜欢将nginx伪装成一个什么名字 禁止使用任何特殊符号仅限英文大小写和空格（例如：OWASP WAF） 留空将不修改使用默认值 默认值是ngixn： " nginx_fake_name
  read -p "请输入自定义的nginx版本号（例如：5.1.24）留空将不修改使用默认版本号： " nginx_version_number

  # 备份配置文件
  mkdir -p /tmp/nginx-bak
  cp -a $NGINX_DIR/conf /tmp/nginx-bak
  cp -a $NGINX_DIR/conf.d /tmp/nginx-bak
  cp -a $NGINX_DIR/ssl /tmp/nginx-bak
  cp -a $NGINX_DIR/logs /tmp/nginx-bak
  cp -a $NGINX_DIR/src/ModSecurity/modsecurity.conf /tmp/nginx-bak

  # 删除nginx
  rm -rf "$OPT_DIR/nginx-bak"
  mkdir -p "$OPT_DIR/nginx-bak"


shopt -s dotglob nullglob
for item in $NGINX_DIR/* $NGINX_DIR/.[!.]* $NGINX_DIR/..?*; do
  case "$item" in
    "$NGINX_DIR/logs" | "$NGINX_DIR") ;;
    *) mv "$item" $OPT_DIR/nginx-bak/ ;;
  esac
done
shopt -u dotglob nullglob

# 备份运行文件
[ -f /usr/local/bin/nginx ] && cp -af /usr/local/bin/nginx /usr/local/bin/nginx.bak

# 重新创建 $NGINX_DIR/src 目录
if [ ! -d "$NGINX_SRC_DIR" ]; then
    mkdir -p "$NGINX_SRC_DIR"
    chmod 750 "$NGINX_SRC_DIR"
    chown -R root:root "$NGINX_SRC_DIR"
fi

# 获取最新的稳定版 Nginx 版本
echo "获取最新的稳定版 Nginx 版本..."

# 这个是获取最新稳定版
#NGINX_VERSION=$(wget -qO- --tries=5 --waitretry=2 --no-check-certificate https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\d+\.\d+\.\d+' | head -n 1 | grep -oP '\d+\.\d+\.\d+')

# 获取 Nginx 主线版本
#NGINX_VERSION=$(curl -s --retry 5 --retry-delay 2  --retry-connrefused -L --no-check-certificate https://nginx.org/en/download.html | grep -oP 'Mainline version.*?nginx-\d+\.\d+\.\d+' | head -n 1 | sed -E 's/.*nginx-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$NGINX_VERSION" ]; then
    echo "未能获取 Nginx 主线版本，请检查下载页面结构"
    exit 1
fi

# 下载 Nginx 源码包
echo "下载 Nginx 源代码..."
cd $NGINX_DIR || exit 1
wget --tries=5 --waitretry=2 --no-check-certificate https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz || { echo "nginx下载失败"; exit 1; }

# 解压源码
tar -zxvf nginx-${NGINX_VERSION}.tar.gz
if [ -d "$NGINX_DIR/nginx" ]; then
    rm -rf $NGINX_DIR/nginx
fi
mv nginx-${NGINX_VERSION} nginx
chown -R root:root $NGINX_DIR/nginx
rm -f nginx-${NGINX_VERSION}.tar.gz


# 替换 Nginx 版本信息和错误页标签
if [ -n "$nginx_fake_name" ] || [ -n "$nginx_version_number" ]; then
    # 处理特殊字符，但不替换空格
    nginx_fake_name=$(echo "$nginx_fake_name" | sed 's/[&/\]/\\&/g')
    nginx_version_number=$(echo "$nginx_version_number" | sed 's/[&/\]/\\&/g')

    # 替换 HTTP 响应头的 server 参数
    if [ -n "$nginx_fake_name" ]; then
        sed -i "s/static u_char ngx_http_server_string\[\] = \"Server: nginx\" CRLF;/static u_char ngx_http_server_string\[\] = \"Server: ${nginx_fake_name}\" CRLF;/g" $NGINX_DIR/nginx/src/http/ngx_http_header_filter_module.c
        sed -i "s/static u_char ngx_http_server_full_string\[\] = \"Server: \" NGINX_VER CRLF;/static u_char ngx_http_server_full_string\[\] = \"Server: ${nginx_fake_name}\" CRLF;/g" $NGINX_DIR/nginx/src/http/ngx_http_header_filter_module.c
        sed -i "s/static u_char ngx_http_server_build_string\[\] = \"Server: \" NGINX_VER_BUILD CRLF;/static u_char ngx_http_server_build_string\[\] = \"Server: ${nginx_fake_name}\" CRLF;/g" $NGINX_DIR/nginx/src/http/ngx_http_header_filter_module.c
    fi

    # 替换 默认错误页的底部标签
    if [ -n "$nginx_fake_name" ]; then
        sed -i "s/<hr><center>\" NGINX_VER_BUILD \"<\/center>\" CRLF/<hr><center>${nginx_fake_name}<\/center>\" CRLF/" $NGINX_DIR/nginx/src/http/ngx_http_special_response.c
        sed -i "s/<hr><center>nginx<\/center>\" CRLF/<hr><center>${nginx_fake_name}<\/center>\" CRLF/" $NGINX_DIR/nginx/src/http/ngx_http_special_response.c
        sed -i "s/<hr><center>\" NGINX_VER \"<\/center>\" CRLF/<hr><center>${nginx_fake_name}<\/center>\" CRLF/" $NGINX_DIR/nginx/src/http/ngx_http_special_response.c
    fi

    # 替换 整体宏标签
    # 注释掉替换 NGINX_VERSION，因为这个已经不必要
    # if [ -n "$nginx_version_number" ]; then
    #     sed -i "s/#define NGINX_VERSION      \".*\"/#define NGINX_VERSION      \"${nginx_version_number}\"/" $NGINX_DIR/nginx/src/core/nginx.h
    # fi

    # if [ -n "$nginx_fake_name" ]; then
    #     sed -i "s/#define NGINX_VER          \"nginx\/\" NGINX_VERSION/#define NGINX_VER          \"${nginx_fake_name}\"/" $NGINX_DIR/nginx/src/core/nginx.h
    # fi

    # 输出替换结果
    if [ -n "$nginx_fake_name" ]; then
        echo "Nginx 伪装名称已设置为: \"$nginx_fake_name\""
    fi

    if [ -n "$nginx_version_number" ]; then
        echo "自定义版本号已设置为: $nginx_version_number"
    fi
else
    echo "未输入任何修改信息，文件未做任何更改。"
fi
# 替换nginx信息 EMD


# 下载并更新所需的模块
echo "下载和更新所需的模块..."

# ngx_cache_purge 模块控制
if [ "$USE_ngx_cache_purge" == "true" ]; then
    echo "正在安装 ngx_cache_purge..."
    ngx_cache_purge_install
    ngx_cache_purge_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_cache_purge"
else
    echo "跳过 ngx_cache_purge 安装..."
    ngx_cache_purge_CONFIG=""
fi

# ngx_http_headers_more_filter_module 模块控制
if [ "$USE_ngx_http_headers_more_filter_module" == "true" ]; then
    echo "正在安装 ngx_http_headers_more_filter_module..."
    ngx_http_headers_more_filter_module_install
    ngx_http_headers_more_filter_module_CONFIG="--add-module=$NGINX_SRC_DIR/headers-more-nginx-module"
else
    echo "跳过 ngx_cache_purge 安装..."
    ngx_http_headers_more_filter_module_CONFIG=""
fi

# ngx_http_proxy_connect_module 模块控制
if [ "$USE_ngx_http_proxy_connect_module" == "true" ]; then
    echo "正在安装 ngx_http_proxy_connect_module..."
    ngx_http_proxy_connect_module_install
    ngx_http_proxy_connect_module_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_http_proxy_connect_module"
else
    echo "跳过 ngx_http_proxy_connect_module 安装..."
    ngx_http_proxy_connect_module_CONFIG=""
fi

# PCRE2 模块控制
if [ "$USE_PCRE2" == "true" ]; then
    echo "正在安装 PCRE2..."
    pcre2_install
    PCRE2_CONFIG="--with-pcre=$NGINX_SRC_DIR/pcre2"
else
    echo "跳过 PCRE2 安装..."
    PCRE2_CONFIG=""
fi

# ngx_brotli 模块控制
if [ "$USE_ngx_brotli" == "true" ]; then
    echo "正在安装 ngx_brotli..."
    ngx_brotli_install
    ngx_brotli_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_brotli"
else
    echo "跳过 ngx_brotli 安装..."
    ngx_brotli_CONFIG=""
fi

# ngx_fancyindex 模块控制
if [ "$USE_ngx_fancyindex" == "true" ]; then
    echo "正在安装 openssl..."
    ngx_fancyindex_install
    ngx_fancyindex_CONFIG="--add-module=$NGINX_SRC_DIR/ngx_fancyindex"
else
    echo "跳过 openssl 安装..."
    ngx_fancyindex_CONFIG=""
fi

# openssl 模块控制
if [ "$USE_openssl" == "true" ]; then
    echo "正在安装 openssl..."
    openssl_install
    openssl_CONFIG="--with-openssl=$NGINX_SRC_DIR/openssl"
else
    echo "跳过 openssl 安装..."
    openssl_CONFIG=""
fi

# modsecurity 模块控制
if [ "$USE_modsecurity" == "true" ]; then
    echo "正在安装 modsecurity..."
    modsecurity_install
else
    echo "跳过 modsecurity 安装..."
fi

# modsecurity_nginx 模块控制
if [ "$USE_modsecurity_nginx" == "true" ]; then
    echo "正在安装 modsecurity_nginx..."
    modsecurity_nginx_install
    # 因为与jemalloc不兼容，所以改为静态模块
    #modsecurity_nginx_CONFIG="--add-dynamic-module=$NGINX_SRC_DIR/ModSecurity-nginx"
    modsecurity_nginx_CONFIG="--add-module=$NGINX_SRC_DIR/ModSecurity-nginx"
else
    echo "跳过 modsecurity_nginx 安装..."
    modsecurity_nginx_CONFIG=""
fi

# owasp 模块控制
if [ "$USE_owasp" == "true" ]; then
    echo "正在安装 owasp..."
    owasp_install
else
    echo "跳过 owasp 安装..."
fi

# 规范 nginx文件权限
chown -R root:root $NGINX_DIR



# 配置编译选项
echo "配置 Nginx 编译选项..."
cd $NGINX_DIR/nginx || exit 1
./configure \
  --prefix=$NGINX_DIR \
  --user=www-data \
  --group=www-data \
  --with-threads \
  --with-file-aio \
  --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_auth_request_module \
  --with-http_sub_module \
  --with-http_flv_module \
  --with-http_mp4_module \
  --with-http_addition_module \
  --with-http_image_filter_module \
  --with-http_gunzip_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-compat \
  --with-cc-opt='-O3 -fPIE -fPIC -march=native -mtune=native -flto -fstack-protector-strong -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2' \
  --with-ld-opt='-ljemalloc -flto -fPIE -fPIC -pie -Wl,-E -Wl,-z,relro,-z,now -Wl,-O1' \
  $ngx_cache_purge_CONFIG \
  $ngx_brotli_CONFIG \
  $ngx_http_headers_more_filter_module_CONFIG \
  $ngx_http_proxy_connect_module_CONFIG \
  $modsecurity_nginx_CONFIG \
  $openssl_CONFIG \
  $PCRE2_CONFIG \
  $ngx_fancyindex_CONFIG

# 编译 Nginx
echo "开始编译 Nginx..."
make -j$(nproc)

# 安装 Nginx
echo "安装 Nginx..."
make install


# 设置 Nginx 服务
echo "设置 Nginx 服务..."
cp -f $NGINX_DIR/sbin/nginx /usr/local/bin/nginx

# 恢复配置文件
cp -af /tmp/nginx-bak/conf $NGINX_DIR/
cp -af /tmp/nginx-bak/conf.d $NGINX_DIR/
cp -af /tmp/nginx-bak/ssl $NGINX_DIR/
cp -af /tmp/nginx-bak/logs $NGINX_DIR/
cp -af /tmp/nginx-bak/modsecurity.conf $NGINX_DIR/src/ModSecurity/
rm -rf /tmp/nginx-bak

# 规范文件权限
[ -f "root:root $NGINX_SRC_DIR/ModSecurity/modsecurity.conf" ] && chown -R root:root "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf"
[ -f "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf" ] && chmod 600 "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf"

[ -f "$NGINX_DIR/modules/ngx_http_modsecurity_module.so" ] && chmod 640 "$NGINX_DIR/modules/ngx_http_modsecurity_module.so"
[ -f "$NGINX_DIR/modules/ngx_stream_module.so" ] && chmod 640 "$NGINX_DIR/modules/ngx_stream_module.so"
[ -f "$NGINX_DIR/modules/ngx_http_image_filter_module.so" ] && chmod 640 "$NGINX_DIR/modules/ngx_http_image_filter_module.so"
[ -d "$NGINX_DIR/modules" ] && chmod 750 "$NGINX_DIR/modules"

find $NGINX_DIR/conf -type d -exec chmod 700 {} \;
find $NGINX_DIR/conf -type f -exec chmod 600 {} \;

# 重新加载 systemd 并启动 Nginx
echo "重新加载 systemd 并启动 Nginx..."
systemctl daemon-reload
systemctl enable nginx
systemctl restart nginx

# 检查 Nginx 是否正常运行
if systemctl is-active --quiet nginx; then
    echo "Nginx 启动成功，清理备份目录..."
    rm -rf "$OPT_DIR/nginx-bak"
    rm -rf "/usr/local/bin/nginx.bak"
    echo "Nginx 升级完成！"
else
    echo "Nginx启动失败导致升级失败！请检查配置文件。原版本备份目录 $OPT_DIR/nginx-bak 以便排查问题"
    echo "运行 systemctl status nginx 或 nginx -t 查看启动失败的原因"
    echo "找不到原因也可以运行以下命令恢复到升级前版本"
    echo "rm -rf $NGINX_DIR && mv $OPT_DIR/nginx-bak $NGINX_DIR && cp -f /usr/local/bin/nginx.bak /usr/local/bin/nginx && systemctl restart nginx"
fi
}

# 卸载 Nginx 的函数
uninstall_nginx() {
    echo "停止 Nginx 服务..."

    if command -v nginx >/dev/null 2>&1; then
        echo "检测到 Nginx 已安装，正在尝试停止和禁用服务..."

        # 如果 nginx.service 存在才尝试操作 systemd 服务
        if systemctl list-unit-files | grep -q '^nginx\.service'; then
            systemctl stop nginx || true
            systemctl disable nginx || true
        fi

        # 删除可能存在的服务文件
        [ -d "/usr/local/modsecurity" ] && rm -rf "/etc/systemd/system/nginx.service /lib/systemd/system/nginx.service"

        # 刷新 systemd 状态
        systemctl daemon-reexec
        systemctl daemon-reload
    else
        echo "未检测到已安装的 Nginx，跳过服务操作。"
    fi

    echo "清理 Nginx 安装目录中除 conf / conf.d / ssl /logs 外的内容..."
    if [ -d "$NGINX_DIR" ]; then
        shopt -s dotglob
        for item in "$NGINX_DIR"/* "$NGINX_DIR"/.*; do
            case "$item" in
                "$NGINX_DIR" | "$NGINX_DIR/conf" | "$NGINX_DIR/conf.d" | "$NGINX_DIR/ssl" | "$NGINX_DIR/logs")
                    ;;
                *)
                    rm -rf "$item"
                    ;;
            esac
        done
        shopt -u dotglob
    fi

    # 卸载 ModSecurity 并删除相关文件
    [ -d "/usr/local/modsecurity" ] && rm -rf "/usr/local/modsecurity"
    
    #删除 cloudflare_ip.sh 定时任务
    (crontab -l | grep -v '/root/cloudflare_ip.sh') | crontab -
    # 删除脚本
    [ -f "/root/cloudflare_ip.sh" ] && rm -f "/root/cloudflare_ip.sh"

    echo "删除 Nginx 二进制文件..."
    [ -f "/usr/local/bin/nginx" ] && rm -f "/usr/local/bin/nginx"

    # 删除 owasp 规则 保留 crs-setup.conf 配置文件
    [ -d "$OPT_DIR/owasp/owasp-rules" ] && find "$OPT_DIR/owasp/owasp-rules/" ! -name 'crs-setup.conf' ! -path "$OPT_DIR/owasp/owasp-rules/" -exec rm -rf {} +

    echo "########### 说明 #######################"

    echo "卸载时保留的文件夹：$NGINX_DIR/conf, $NGINX_DIR/conf.d, $NGINX_DIR/ssl, $OPT_DIR/owasp, $NGINX_DIR/logs"
    echo "如需完全清除 Nginx，请运行：rm -rf $NGINX_DIR $OPT_DIR/owasp"
    echo "如需清除网站数据和删除网站根目录，请运行：rm -rf /www"
    echo "Nginx 卸载完成。"
    echo "######################################"
}


# 如果通过参数调用（非交互模式）
if [[ -n "$1" ]]; then
  MODE="$1"
  case "$MODE" in
    install) install_nginx ;;
    upgrade) upgrade_nginx ;;
    uninstall)
      read -rp "你确定要卸载 Nginx 吗？(Y/N): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        uninstall_nginx
      else
        echo "已取消卸载操作。"
      fi
      ;;
    *) echo "无效参数。用法: $0 [install|upgrade|uninstall]"; exit 1 ;;
  esac
  exit 0
fi

# 交互模式
while true; do
  echo "请选择操作模式："
  echo "1. 安装"
  echo "2. 更新"
  echo "3. 卸载"
  echo "4. 退出"
  read -rp "输入 1、2、3 或 4 进行选择: " choice

  case "$choice" in
    1) install_nginx; break ;;
    2) upgrade_nginx; break ;;
    3)
      read -rp "你确定要卸载 Nginx 吗？(Y/N): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        uninstall_nginx
      else
        echo "已取消卸载操作。"
      fi
      break
      ;;
    4) echo "退出脚本。"; exit 0 ;;
    *) echo "无效的选择，请输入 1、2、3 或 4。" ;;
  esac
done
