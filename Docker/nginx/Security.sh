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

# 如果 proxy.conf 代理优化配置文件
if [ ! -f "$NGINX_DIR/conf/proxy.conf" ]; then
  wget -q --tries=5 --waitretry=2 --no-check-certificate -O "$NGINX_DIR/conf/proxy.conf" "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/proxy.conf"
  # 替换文件内容中的 $NGINX_DIR（写成 \$NGINX_DIR）为实际路径
  sed -i "s|\\%NGINX_DIR%|$NGINX_DIR|g" "$NGINX_DIR/conf/proxy.conf"
fi

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


# 规范文件权限
find $NGINX_DIR/conf -type d -exec chmod 700 {} \;
find $NGINX_DIR/conf -type f -exec chmod 600 {} \;
find $NGINX_DIR/conf.d -type d -exec chmod 600 {} \;
find $NGINX_DIR/conf.d -type f -exec chmod 600 {} \;
