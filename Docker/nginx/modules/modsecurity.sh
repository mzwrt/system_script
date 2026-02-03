#!/bin/bash
# 如果存在，删除/usr/local/modsecurity目录重新安装
if [ -d "/usr/local/modsecurity" ]; then
    rm -rf /usr/local/modsecurity
fi
git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity ModSecurity
cd ModSecurity
git submodule update --recursive
git submodule init
git submodule update --recursive
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
if [ -f "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf" ]; then
  mv -f "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf" "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf.bak"
fi
wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/ModSecurity/modsecurity.conf"

# 规范文件权限
chown root:root "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf"
chmod 600 "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf"
if [ -f "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf.bak" ]; then
  chmod 600 "$NGINX_SRC_DIR/ModSecurity/modsecurity.conf.bak"
fi

ModSecurity-nginx 连接器
cd $NGINX_SRC_DIR
git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git
chown -R root:root "$NGINX_SRC_DIR/ModSecurity-nginx"

