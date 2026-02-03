#!/bin/bash
# 下载并解压模块
wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/chobits/ngx_http_proxy_connect_module/archive/refs/tags/$USE_ngx_http_proxy_connect_module_version.zip"

unzip $USE_ngx_http_proxy_connect_module_version.zip

rm -f $USE_ngx_http_proxy_connect_module_version.zip
mv ngx_http_proxy_connect_module-${USE_ngx_http_proxy_connect_module_version#v} ngx_http_proxy_connect_module

# 应用补丁
cd $NGINX_DIR
cp $NGINX_DIR/src/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch $NGINX_DIR/nginx
cd nginx

patch -p1 -f < proxy_connect_rewrite_102101.patch

# 删除补丁文件
if [ -f proxy_connect_rewrite_102101.patch ]; then
  rm -rf proxy_connect_rewrite_102101.patch >/dev/null 2>&1
fi
