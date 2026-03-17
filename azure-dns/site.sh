# 监听 80 端口，重定向所有 HTTP 请求到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name dns.site.com;
    return 301 https://$host$request_uri;
}

# 监听 443 端口，启用 HTTP/3 和 SSL 配置
server {
    listen 443 quic;
    listen [::]:443 quic;
    http3 on;

    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name dns.site.com;
    index index.html;
    root /www/wwwroot/dns.site.com;

    # 当用户通过 HTTP 请求访问时，返回 497 状态码，要求使用 HTTPS
    error_page 497 https://$host$request_uri;

    # HTTP/3 特定头部，帮助浏览器发现 HTTP/3
    add_header Alt-Svc 'h3-23=":443"; ma=86400'; 
    add_header Cache-Control "no-store";

    # QUIC 设置
    http3_max_concurrent_streams 128;

    # SSL 配置
    ssl_certificate /opt/nginx/ssl/site.com/fullchain.pem;
    ssl_certificate_key /opt/nginx/ssl/site.com/privkey.pem;
    


    # 配置用于 OCSP 响应验证的受信任证书
    ssl_trusted_certificate /opt/nginx/ssl/site.com/ca.pem;

    # 强制启用 HTTP Strict Transport Security (HSTS)，提升 HTTPS 安全性
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # 配置内容安全策略（CSP）
    add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https: data:; style-src 'self' 'unsafe-inline' https: data:; img-src 'self' https: data:; font-src 'self' https: data:; frame-src 'self' https: data:; connect-src 'self' https: data: https://api.wordpress.org; object-src 'none'; base-uri 'self'; form-action 'self'; worker-src 'self' blob:; upgrade-insecure-requests; block-all-mixed-content;" always;


    # 速率限制
    limit_req  zone=general burst=30 nodelay;
    limit_conn perip 15;
    limit_conn perserver 200;

    # 限制只允许 POST PUT 和 DELETE OPTIONS 方法，其他方法拒绝
    # 启用每个IP的速率限制
    location / {

    # 应启用速率限制来限制 IP 地址在给定时间段内向服务器发出的请求数量。应根据应用程序的需求和组织政策设置配置值。
    # 限制每个 IP 的请求速率（可选）
    #limit_req_zone $binary_remote_addr zone=ratelimit:10m rate=5r/s;
    #limit_req zone=ratelimit burst=10 nodelay;

    # 限制只允许 POST PUT 和 DELETE OPTIONS 请求
    limit_except GET HEAD POST OPTIONS {
        deny all;
    }
    add_header Allow "GET, POST, HEAD, OPTIONS" always;

    }

    # 限制非法 Host 头的请求
    # 最简单的防盗链 修改为自己的域名 否则会导致网站不能访问
    #if ($host !~ ^(example\.com|www\.example\.com)$ ) {
    #    return 444;
    #}

    # 开启 PHP
    # 默认是注释掉的 安装了 PHP 可以打开 默认使用 PHP 8.4
    #include enable-php-84.conf;

    # 禁止访问隐藏文件（如 .htaccess、.git 等）
    location ~ ^/(\.user.ini|\.htaccess|\.git|\.env|\.svn|\.project|LICENSE|README.md|\.stfolder|\.stignore|\.well-known) {
        return 444;
    }

    # 拒绝常见爬虫的 User-Agent
    if ($http_user_agent ~* (HTTrack|crawler|scrapy|wget|curl|python|nikto|sqlmap|fimap|nmap|masscan)) {
        return 403;
    }

    # SSL 证书验证相关
    location ~ \.well-known {
        deny all;
    }

    # 禁止上传不安全的文件
    if ( $uri ~ "^/\.well-known/.*\.(php|jsp|py|js|css|lua|ts|go|zip|tar\.gz|rar|7z|sql|bak)$" ) {
        return 403;
    }

    # 配置图片文件缓存
    location ~ .*\.(gif|jpg|jpeg|png|bmp|swf)$ {
        expires 30d;
        error_log /dev/null;
        access_log /dev/null;
    }

    # 配置静态文件缓存
    location ~ .*\.(js|css)?$ {
        expires 12h;
        error_log /dev/null;
        access_log /dev/null; 
    }

    # 禁止访问隐藏文件（如 .htaccess、.htpasswd、.DS_Store 等）
    location ~ /\. {
        deny all;
    }

    # 引用本站 OWASP 规则集
    #modsecurity_rules_file /opt/owasp/conf/dns.site.com.conf;

    # 引入 wordpress 插件规则
    #include /opt/owasp/conf/nginx-wordpress.conf;

    # 配置日志文件
    access_log /opt/nginx/logs/dns.site.com.log security_audit buffer=8k flush=10s;
    error_log /opt/nginx/logs/dns.site.com.error.log warn;
}
