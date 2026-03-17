user  www-data www-data;
worker_processes 2;                # = vCPU 数
worker_cpu_affinity 01 10;         # 绑核，减少上下文切换
worker_priority -5;                # 轻微提升调度优先级
error_log /opt/nginx/logs/nginx_error.log crit;  # 设置错误日志级别为 crit
pid /opt/nginx/logs/nginx.pid;  # 设置 Nginx 进程 ID 文件路径
worker_rlimit_nofile 65535;  # 设置工作进程可打开的最大文件数

events {
    # 1GB 下每 worker 连接数适度：2048
    # 2 worker × 2048 = 最大 4096 并发（足够 DNS 服务场景）
    worker_connections 2048;
    multi_accept       on;
    use                epoll;
}

http {
    ##############################################################
    ## 基础设置
    ##############################################################
    include mime.types;  # 包含 MIME 类型配置
    default_type application/octet-stream;

    # 字符集
    charset utf-8;

    # sendfile + tcp_nopush 组合：减少系统调用次数
    sendfile        on;
    tcp_nopush      on;

    # 禁用 Nagle 算法（小包立即发送，降低延迟）
    tcp_nodelay     on;

    # Keepalive（复用 TCP 连接，减少握手开销）
    keepalive_timeout          65;
    keepalive_requests         10000;

    # 请求超时
    client_header_timeout      15s;
    client_body_timeout        15s;
    send_timeout               15s;
    reset_timedout_connection  on;

    ##############################################################
    ## 缓冲区（防止大请求/响应导致的临时文件 I/O）
    ##############################################################
    client_header_buffer_size   4k;
    large_client_header_buffers 4 16k;
    client_body_buffer_size     128k;
    client_max_body_size        10m;

    # 输出缓冲
    output_buffers  2 32k;
    postpone_output 1460;

    ##############################################################
    ## 连接池（upstream keepalive）
    ##############################################################
    # 若有后端 upstream，在 upstream 块中添加：
    # keepalive 64;
    # keepalive_requests 1000;
    # keepalive_timeout 60s;

    ##############################################################
    ## 文件缓存（减少 stat() 系统调用）
    ##############################################################
    open_file_cache          max=10000 inactive=60s;
    open_file_cache_valid    30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors   on;
    
    ##############################################################
    ## brotli 压缩
    ##############################################################
    brotli on;
    brotli_comp_level 4;    # 动态压缩建议 4-6，兼顾 CPU 和压缩率
    brotli_buffers 16 8k;   # 建议稍微调大，应对 2026 年更复杂的 JS 框架
    brotli_min_length 20;   # 极小文件也压缩，适合你的高精度需求
    brotli_static always;   # 即使客户端不支持 br，也尝试寻找 .br 文件
    brotli_window 512k;     # 标准窗口大小，适合大多数场景
    
    # 修正后的类型列表
    brotli_types
        text/plain
        text/css
        text/javascript
        text/xml
        text/x-component
        application/json
        application/javascript
        application/x-javascript
        application/xml
        application/xml+rss
        application/atom+xml
        application/vnd.ms-fontobject
        application/x-font-ttf
        font/opentype
        image/svg+xml
        image/x-icon; # 仅在此处加分号

    ##############################################################
    ## Gzip 压缩
    ##############################################################
    gzip              on;
    gzip_vary         on;
    gzip_proxied      any;
    gzip_comp_level   4;         # 1-9，4 是速度/压缩比最佳平衡点
    gzip_buffers      16 8k;
    gzip_http_version 1.1;
    gzip_min_length   256;
    gzip_types
        text/plain
        text/css
        text/javascript
        text/xml
        text/x-component
        application/json
        application/javascript
        application/x-javascript
        application/xml
        application/xml+rss
        application/atom+xml
        application/vnd.ms-fontobject
        application/x-font-ttf
        font/opentype
        image/svg+xml
        image/x-icon;

    ##############################################################
    ## 日志格式（PCI-DSS 10.x 合规，包含必要审计字段）
    ##############################################################
    log_format main
        '$remote_addr - $remote_user [$time_local] '
        '"$request" $status $body_bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '$request_time $upstream_response_time '
        '$request_id';

    log_format security_audit
        '$time_iso8601 | $remote_addr | $request_method | '
        '$host$request_uri | $status | $body_bytes_sent | '
        '$http_user_agent | $request_time | '
        '$ssl_protocol/$ssl_cipher';

    # 访问日志（PCI-DSS 10.3 要求记录 IP、时间、操作、状态）
    access_log /var/log/nginx/access.log main buffer=16k flush=5s;

    ##############################################################
    ## TLS 全局设置（PCI-DSS 4.2.1 要求 TLS ≥ 1.2）
    ##############################################################
    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers  on;
    ssl_ciphers
        'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:'
        'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:'
        'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:'
        'DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';

    # DH 参数（PCI-DSS 要求 ≥ 2048 bit）
    # 若文件不存在则生成：openssl dhparam -out /etc/nginx/dhparam.pem 2048
    # ssl_dhparam /etc/nginx/dhparam.pem;

    # Session 缓存（性能优化，减少 TLS 握手）
    ssl_session_cache    shared:SSL:50m;
    ssl_session_timeout  1d;
    ssl_session_tickets  off;      # PCI-DSS 4.2.1

    # OCSP Stapling（减少客户端证书验证 RTT）
    ssl_stapling         on;
    ssl_stapling_verify  on;
    resolver             127.0.0.1 valid=300s;
    resolver_timeout     5s;

    # HSTS（强制 HTTPS）
    # 在 server 块中添加：
    # add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    ##############################################################
    ## 安全响应头（CIS Nginx Benchmark）
    ##############################################################
    server_tokens          off;    # 隐藏 Nginx 版本号
    more_clear_headers     'Server';  # 需要 headers-more 模块
    more_set_headers       'Server: ';

    add_header X-Frame-Options           "SAMEORIGIN"   always;
    add_header X-Content-Type-Options    "nosniff"      always;
    add_header X-XSS-Protection          "1; mode=block" always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy        "geolocation=(), microphone=(), camera=()" always;

    ##############################################################
    ## 速率限制区（配合 OWASP CRS 防暴力破解）
    ##############################################################
    # 按 IP 限制请求速率
    limit_req_zone  $binary_remote_addr  zone=general:10m  rate=30r/s;
    limit_req_zone  $binary_remote_addr  zone=api:10m      rate=10r/s;
    limit_req_zone  $binary_remote_addr  zone=login:10m    rate=5r/m;

    # 按 IP 限制并发连接数
    limit_conn_zone $binary_remote_addr  zone=perip:10m;
    limit_conn_zone $server_name         zone=perserver:10m;

    limit_req_status  429;
    limit_conn_status 429;
    
    ##############################################################
    # 启用 ModSecurity
    ##############################################################
    modsecurity on;  # 启用 ModSecurity WAF


    ##############################################################
    # 根据 CIS
    # 默认拦截 HTTP 和 HTTPS 请求
    ##############################################################
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        return 444;
    }

    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;
        ssl_certificate     /opt/nginx/ssl/default/default.pem;
        ssl_certificate_key /opt/nginx/ssl/default/default.key;
        return 444;
    }

    ##############################################################
    ## 包含子配置
    ##############################################################
    include /opt/nginx/conf.d/sites-enabled/*.conf;
}
