# Docker PHP 安全加固安装指南
## CIS Benchmark / 最小权限 / 高性能 / 生产级

---

## 目录
1. [架构总览](#架构总览)
2. [基础镜像选择](#基础镜像选择)
3. [Dockerfile 安全加固](#dockerfile-安全加固)
4. [php.ini 安全配置](#phpini-安全配置)
5. [PHP-FPM 安全配置](#php-fpm-安全配置)
6. [docker-compose 安全配置](#docker-compose-安全配置)
7. [Nginx 配合配置](#nginx-配合配置)
8. [运行时安全控制](#运行时安全控制)
9. [网络隔离](#网络隔离)
10. [Secrets 管理](#secrets-管理)
11. [日志与审计](#日志与审计)
12. [CIS Docker Benchmark 检查清单](#cis-docker-benchmark-检查清单)
13. [性能调优](#性能调优)
14. [验证与测试](#验证与测试)

---

## 架构总览

```
Internet → Nginx (TLS termination) → PHP-FPM → App
                                         ↓
                                    Redis (Session)
                                    MySQL/PostgreSQL
```

- Nginx 与 PHP-FPM 通过 **Unix Socket** 通信（比 TCP 快且更安全）
- 每个服务独立容器，独立网络命名空间
- 所有容器以非 root 用户运行
- 只读根文件系统（必要目录除外）

---

## 基础镜像选择

### 推荐：php:8.3-fpm-alpine

```dockerfile
# ✅ 推荐：Alpine 最小化镜像，攻击面最小
FROM php:8.3-fpm-alpine

# ❌ 避免使用
# FROM php:8.3-fpm          # Debian full，体积大
# FROM php:latest           # 版本不固定，不可预测
# FROM ubuntu + apt install # 攻击面过大
```

**为什么选 Alpine：**
- 镜像约 ~30MB（vs Debian ~150MB）
- 使用 musl libc + busybox，大幅缩减攻击面
- 内置 `apk` 包签名验证
- 符合 CIS 最小化原则

---

## Dockerfile 安全加固

```dockerfile
# =============================================================
# 多阶段构建：builder + runtime 分离
# =============================================================

# ---- Stage 1: Builder ----
FROM php:8.3-fpm-alpine AS builder

# 锁定包版本（安全可追溯）
RUN apk add --no-cache \
    $PHPIZE_DEPS \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    oniguruma-dev \
    libzip-dev \
    icu-dev \
    postgresql-dev \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        pdo_pgsql \
        pdo_mysql \
        gd \
        mbstring \
        zip \
        intl \
        opcache \
        pcntl \
    # 安装 Redis 扩展（通过 PECL）
    && pecl install redis-6.0.2 \
    && docker-php-ext-enable redis \
    # 清理构建缓存
    && apk del $PHPIZE_DEPS \
    && rm -rf /tmp/pear /var/cache/apk/*

# 安装 Composer（验证 hash）
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY composer.json composer.lock ./

# 生产依赖，不安装 dev 包
RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts \
    && composer clear-cache

COPY . .

# ---- Stage 2: Runtime ----
FROM php:8.3-fpm-alpine AS runtime

# 只安装运行时依赖（无编译工具）
RUN apk add --no-cache \
    libpng \
    libjpeg-turbo \
    libwebp \
    freetype \
    oniguruma \
    libzip \
    icu-libs \
    libpq \
    # 审计和安全工具
    tzdata \
    && rm -rf /var/cache/apk/*

# 从 builder 复制编译好的扩展
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# =============================================================
# 创建非 root 用户（CIS 5.1 - 不以 root 运行）
# =============================================================
RUN addgroup -g 1001 -S appgroup \
    && adduser -u 1001 -S appuser -G appgroup -h /app -s /sbin/nologin

# 创建必要目录并设置权限
RUN mkdir -p /app /var/log/php-fpm /tmp/php \
    && chown -R appuser:appgroup /app /var/log/php-fpm /tmp/php \
    && chmod 750 /app \
    && chmod 700 /tmp/php

# 复制应用代码（从 builder）
COPY --from=builder --chown=appuser:appgroup /app /app

# 复制配置文件
COPY --chown=root:root docker/php/php.ini /usr/local/etc/php/php.ini
COPY --chown=root:root docker/php/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY --chown=root:root docker/php/www.conf /usr/local/etc/php-fpm.d/www.conf

# 权限锁定
RUN chmod 644 /usr/local/etc/php/php.ini \
    && chmod 644 /usr/local/etc/php-fpm.conf \
    && chmod 644 /usr/local/etc/php-fpm.d/www.conf

# 删除不必要文件（CIS 最小化）
RUN rm -f /usr/local/etc/php-fpm.d/docker.conf \
          /usr/local/etc/php-fpm.d/zz-docker.conf \
    && find /app -name "*.git" -o -name ".env.example" -o -name "*.md" \
       -o -name "Makefile" -o -name "phpunit*" 2>/dev/null | xargs rm -rf

WORKDIR /app

# 以非 root 用户运行
USER appuser

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD php-fpm -t 2>&1 | grep -q "syntax is OK" || exit 1

# 暴露端口（仅用于文档，实际使用 Socket）
EXPOSE 9000

CMD ["php-fpm", "--nodaemonize", "--force-stderr"]
```

---

## php.ini 安全配置

```ini
; ============================================================
; /usr/local/etc/php/php.ini - 生产安全配置
; 基于 CIS PHP Benchmark + OWASP 建议
; ============================================================

[PHP]
; ---------- 信息泄露防护 ----------
expose_php = Off                        ; 不在 HTTP 头暴露 PHP 版本
display_errors = Off                    ; 生产环境关闭错误显示
display_startup_errors = Off
html_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors = On
error_log = /var/log/php-fpm/php_errors.log

; ---------- 文件操作安全 ----------
allow_url_fopen = Off                   ; 禁止远程文件打开（防 SSRF）
allow_url_include = Off                 ; 禁止远程文件包含（防 RFI）
open_basedir = /app:/tmp/php            ; 限制文件访问目录（沙箱）
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,\
    curl_exec,curl_multi_exec,parse_ini_file,show_source,phpinfo,\
    pcntl_exec,pcntl_fork,pcntl_signal,symlink,link,readlink,\
    posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,posix_setuid,\
    posix_getpwuid,posix_uname,proc_get_status,proc_nice,proc_terminate

; ---------- 上传与资源限制 ----------
file_uploads = On
upload_max_filesize = 10M
max_file_uploads = 5
post_max_size = 12M
max_execution_time = 30
max_input_time = 30
memory_limit = 128M
max_input_vars = 1000
max_input_nesting_level = 64

; ---------- Session 安全 ----------
session.use_strict_mode = 1
session.cookie_secure = 1              ; 仅 HTTPS 传输
session.cookie_httponly = 1            ; 防 JavaScript 访问
session.cookie_samesite = Strict       ; 防 CSRF
session.use_cookies = 1
session.use_only_cookies = 1
session.use_trans_sid = 0
session.cookie_lifetime = 0
session.gc_maxlifetime = 1440
session.sid_length = 48
session.sid_bits_per_character = 6
session.save_handler = redis           ; 使用 Redis 存储（集中管理）
session.save_path = "tcp://redis:6379?auth=${REDIS_PASSWORD}"
session.name = __Secure-SSID           ; 安全 cookie 名前缀

; ---------- 序列化安全 ----------
; PHP 8.x 默认已较安全，额外限制
unserialize_callback_func =
; 允许反序列化的类（根据项目调整）
; unserialize_allowed_classes = false   ; 完全禁止（最严格）

; ---------- OPcache 高性能配置 ----------
[opcache]
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0        ; 生产关闭（性能提升，更新需重启）
opcache.revalidate_freq = 0
opcache.fast_shutdown = 1
opcache.enable_file_override = 1
opcache.optimization_level = 0x7FFEBFFF
; 安全：防止缓存投毒
opcache.file_cache_consistency_checks = 1

; ---------- 其他安全 ----------
default_charset = "UTF-8"
date.timezone = Asia/Shanghai
realpath_cache_size = 4096k
realpath_cache_ttl = 600
```

---

## PHP-FPM 安全配置

```ini
; ============================================================
; /usr/local/etc/php-fpm.d/www.conf
; ============================================================

[www]

; 以非 root 用户运行（与 Dockerfile USER 一致）
user = appuser
group = appgroup

; 使用 Unix Socket（比 TCP 安全 + 快）
listen = /tmp/php/php-fpm.sock
listen.owner = nginx
listen.group = nginx
listen.mode = 0660               ; 仅 nginx 可读写

; ---- 进程管理（dynamic 模式适合大多数场景）----
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500            ; 防内存泄漏，每 500 请求重启 worker
pm.process_idle_timeout = 10s

; ---- 请求超时 ----
request_terminate_timeout = 30s
request_slowlog_timeout = 5s
slowlog = /var/log/php-fpm/slow.log

; ---- 安全：清除环境变量 ----
clear_env = yes                  ; 清除所有环境变量（最安全）
; 只传入需要的变量：
env[APP_ENV] = $APP_ENV
env[DB_HOST] = $DB_HOST
env[DB_PASSWORD] = $DB_PASSWORD
env[REDIS_PASSWORD] = $REDIS_PASSWORD

; ---- 状态页（仅内部访问）----
pm.status_path = /fpm-status
ping.path = /fpm-ping
ping.response = pong

; ---- 安全限制 ----
security.limit_extensions = .php   ; 只允许执行 .php 文件
chdir = /app
```

---

## docker-compose 安全配置

```yaml
# docker-compose.yml - 生产级安全配置

version: "3.9"

services:

  # ============================================================
  # PHP-FPM
  # ============================================================
  php:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
      args:
        - BUILDKIT_INLINE_CACHE=1
    image: myapp/php:8.3-${APP_VERSION:-latest}
    restart: unless-stopped

    # CIS 5.1 - 不以 root 运行
    user: "1001:1001"

    # CIS 5.4 - 只读根文件系统
    read_only: true
    tmpfs:
      - /tmp/php:uid=1001,gid=1001,mode=0700,size=64m
      - /tmp:uid=1001,gid=1001,mode=1777,size=32m

    # CIS 5.3 - 删除 Linux Capabilities
    cap_drop:
      - ALL
    cap_add:
      - CHOWN             # 仅在需要时添加，通常也可去掉
      # 大多数 PHP-FPM 不需要任何 cap

    # CIS 5.2 - 防止权限提升
    security_opt:
      - no-new-privileges:true
      - seccomp:docker/seccomp/php-fpm.json  # 自定义 seccomp profile（见下文）

    # CIS 5.7 - 限制资源
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 512M
        reservations:
          cpus: "0.5"
          memory: 256M

    # 不挂载敏感主机路径
    volumes:
      - php_socket:/tmp/php          # 与 nginx 共享 socket
      - app_logs:/var/log/php-fpm    # 日志持久化

    # Secrets（不用环境变量明文传密码）
    secrets:
      - db_password
      - redis_password

    environment:
      APP_ENV: production
      DB_HOST: db
      DB_PORT: "5432"
      DB_NAME: myapp
      DB_USER: appuser
      # 密码从 secret 文件读取
      DB_PASSWORD_FILE: /run/secrets/db_password

    # 网络隔离
    networks:
      - app_internal    # PHP 与 Nginx
      - db_internal     # PHP 与数据库

    # 不开放端口到主机（通过 socket/网络通信）
    expose:
      - "9000"

    # 健康检查
    healthcheck:
      test: ["CMD", "php-fpm", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

    # 日志驱动
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  # ============================================================
  # Nginx
  # ============================================================
  nginx:
    image: nginx:1.27-alpine
    restart: unless-stopped
    user: "101:101"          # nginx 用户
    read_only: true
    tmpfs:
      - /var/cache/nginx:uid=101,size=64m
      - /var/run:uid=101,size=1m
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE     # 绑定 80/443 端口
    security_opt:
      - no-new-privileges:true
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/conf.d:/etc/nginx/conf.d:ro
      - php_socket:/tmp/php:ro          # 读取 FPM socket
      - ./certs:/etc/nginx/certs:ro     # TLS 证书
      - app_logs:/var/log/nginx
    networks:
      - app_internal
      - public
    depends_on:
      php:
        condition: service_healthy
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  # ============================================================
  # Redis（Session 存储）
  # ============================================================
  redis:
    image: redis:7.2-alpine
    restart: unless-stopped
    user: "999:999"
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    command: >
      redis-server
      --requirepass "${REDIS_PASSWORD}"
      --bind 127.0.0.1
      --protected-mode yes
      --maxmemory 128mb
      --maxmemory-policy allkeys-lru
      --save ""                    # 禁用持久化（仅 session 用）
      --loglevel warning
    networks:
      - db_internal
    tmpfs:
      - /data:uid=999,size=128m
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ============================================================
  # PostgreSQL
  # ============================================================
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    user: "70:70"
    read_only: true
    tmpfs:
      - /tmp:uid=70,size=64m
      - /var/run/postgresql:uid=70,size=1m
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    environment:
      POSTGRES_USER: appuser
      POSTGRES_DB: myapp
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./docker/postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro
    networks:
      - db_internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d myapp"]
      interval: 30s
      timeout: 10s
      retries: 5

# ============================================================
# 网络隔离（CIS 5.13 - 隔离容器网络）
# ============================================================
networks:
  public:
    driver: bridge
  app_internal:
    driver: bridge
    internal: true           # 不允许访问外部网络
  db_internal:
    driver: bridge
    internal: true

# ============================================================
# 卷
# ============================================================
volumes:
  php_socket:
    driver: local
  app_logs:
    driver: local
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/postgres  # 主机路径，需提前创建并设权限

# ============================================================
# Secrets（Docker Swarm 或文件方式）
# ============================================================
secrets:
  db_password:
    file: ./secrets/db_password.txt
  redis_password:
    file: ./secrets/redis_password.txt
```

---

## Nginx 配合配置

```nginx
# docker/nginx/conf.d/app.conf

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com;
    root /app/public;
    index index.php;

    # TLS 配置
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling        on;
    ssl_stapling_verify on;

    # 安全响应头
    add_header X-Frame-Options              "SAMEORIGIN"   always;
    add_header X-XSS-Protection             "1; mode=block" always;
    add_header X-Content-Type-Options       "nosniff"       always;
    add_header Referrer-Policy              "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy      "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; frame-ancestors 'none';" always;
    add_header Strict-Transport-Security    "max-age=63072000; includeSubDomains; preload" always;
    add_header Permissions-Policy           "geolocation=(), microphone=(), camera=()" always;
    server_tokens off;

    # 限制请求大小
    client_max_body_size 12M;
    client_body_timeout 30s;
    client_header_timeout 30s;

    # 不暴露 PHP 文件路径
    location ~ /\. {
        deny all;
        return 404;
    }
    location ~ \.(env|git|htaccess|log|sh|sql|bak|conf)$ {
        deny all;
        return 404;
    }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # PHP-FPM via Unix Socket
    location ~ \.php$ {
        # 防止 path info 攻击
        try_files $fastcgi_script_name =404;
        include        fastcgi_params;
        fastcgi_pass   unix:/tmp/php/php-fpm.sock;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param  HTTP_PROXY "";    # 防 httpoxy 漏洞
        fastcgi_index  index.php;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 30s;
        fastcgi_connect_timeout 5s;
    }
}
```

---

## 运行时安全控制

### Seccomp Profile（限制系统调用）

```bash
# docker/seccomp/php-fpm.json
# 创建精简 seccomp 配置
cat > docker/seccomp/php-fpm.json << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
  "syscalls": [
    {
      "names": [
        "accept", "accept4", "access", "arch_prctl", "bind", "brk",
        "clone", "clone3", "close", "connect", "dup", "dup2", "dup3",
        "epoll_create", "epoll_create1", "epoll_ctl", "epoll_pwait",
        "epoll_wait", "eventfd2", "execve", "exit", "exit_group",
        "faccessat", "fadvise64", "fallocate", "fchdir", "fchmod",
        "fchown", "fcntl", "fdatasync", "fgetxattr", "flock", "fork",
        "fstat", "fstatfs", "fsync", "ftruncate", "futex", "getcwd",
        "getdents64", "getegid", "geteuid", "getgid", "getpgrp",
        "getpid", "getppid", "getrandom", "getrlimit", "getsockname",
        "getsockopt", "gettid", "gettimeofday", "getuid", "inotify_add_watch",
        "inotify_init1", "inotify_rm_watch", "io_setup", "ioctl",
        "kill", "lchown", "lgetxattr", "listen", "lseek", "lstat",
        "madvise", "memfd_create", "mkdir", "mmap", "mprotect", "mremap",
        "munmap", "nanosleep", "newfstatat", "open", "openat", "openat2",
        "pipe", "pipe2", "poll", "ppoll", "prctl", "pread64", "prlimit64",
        "pwrite64", "read", "readlink", "readlinkat", "readv", "recvfrom",
        "recvmsg", "rename", "renameat", "renameat2", "rmdir", "rt_sigaction",
        "rt_sigprocmask", "rt_sigreturn", "rt_sigsuspend", "sched_getaffinity",
        "sched_yield", "select", "sendfile", "sendmsg", "sendto", "set_robust_list",
        "set_tid_address", "setgid", "setgroups", "setitimer", "setrlimit",
        "setsockopt", "setuid", "shutdown", "sigaltstack", "signalfd4",
        "socket", "socketpair", "splice", "stat", "statfs", "statx",
        "symlink", "tgkill", "timerfd_create", "timerfd_settime", "umask",
        "uname", "unlink", "unlinkat", "utimensat", "wait4", "waitid",
        "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
```

### AppArmor Profile（可选，Linux 主机）

```bash
# /etc/apparmor.d/docker-php-fpm
profile docker-php-fpm flags=(attach_disconnected, mediate_deleted) {
  include <abstractions/base>

  # 只允许访问应用目录
  /app/ r,
  /app/** r,
  /tmp/php/ rw,
  /tmp/php/** rw,
  /var/log/php-fpm/ w,
  /var/log/php-fpm/** w,

  # PHP 二进制
  /usr/local/bin/php mr,
  /usr/local/sbin/php-fpm mr,

  # 禁止访问主机敏感路径
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,
  deny /home/** rw,
  deny /proc/sysrq-trigger rw,
}
```

---

## Secrets 管理

```bash
# 生成强密码并存储（不提交到 git）
mkdir -p secrets
chmod 700 secrets

openssl rand -base64 32 > secrets/db_password.txt
openssl rand -base64 32 > secrets/redis_password.txt

chmod 600 secrets/*.txt

# .gitignore
echo "secrets/" >> .gitignore
echo ".env.local" >> .gitignore
```

**生产环境推荐：**
- AWS Secrets Manager / Azure Key Vault / HashiCorp Vault
- Docker Swarm Secrets（加密存储）
- Kubernetes Secrets + Sealed Secrets / External Secrets Operator

---

## 日志与审计

```bash
# 日志目录权限
mkdir -p logs/php-fpm logs/nginx
chmod 750 logs/

# 实时查看错误日志
docker compose logs -f php | grep -E "ERROR|WARN|CRITICAL"

# 审计容器行为（Falco）
docker run -d --name falco \
  --privileged \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  falcosecurity/falco:latest
```

---

## CIS Docker Benchmark 检查清单

```bash
# 安装 docker-bench-security 自动检查
docker run --rm -it \
  --net host \
  --pid host \
  --userns host \
  --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /etc:/etc:ro \
  docker/docker-bench-security

# 主要 CIS 控制项对照：
```

| CIS 控制项 | 配置实现 | 状态 |
|---|---|---|
| 4.1 不使用 latest tag | `php:8.3-fpm-alpine` 固定版本 | ✅ |
| 4.2 只安装必要包 | Alpine + 多阶段构建 | ✅ |
| 4.6 以非 root 运行 | `USER appuser(1001)` | ✅ |
| 4.9 使用受信任基础镜像 | 官方 Docker Hub php 镜像 | ✅ |
| 5.1 不以特权模式运行 | 无 `privileged: true` | ✅ |
| 5.2 no-new-privileges | `security_opt: no-new-privileges:true` | ✅ |
| 5.3 丢弃 Capabilities | `cap_drop: ALL` | ✅ |
| 5.4 只读文件系统 | `read_only: true` + tmpfs | ✅ |
| 5.7 限制内存 | `deploy.resources.limits` | ✅ |
| 5.13 网络隔离 | internal 网络分层 | ✅ |
| 5.15 不挂载主机敏感目录 | 无 `/etc`, `/proc` 挂载 | ✅ |
| 5.25 容器重启策略 | `restart: unless-stopped` | ✅ |
| 5.28 使用 seccomp | 自定义 seccomp profile | ✅ |

---

## 性能调优

### OPcache 预加载（PHP 8.x）

```php
<?php
// docker/php/preload.php - 预热热点类
// 在 php.ini 中添加：opcache.preload=/app/preload.php

function preload(string $dir): void {
    $files = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir)
    );
    foreach ($files as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            opcache_compile_file($file->getPathname());
        }
    }
}

preload('/app/src');
preload('/app/vendor/symfony');  // 根据项目调整
```

```ini
; php.ini 添加
opcache.preload = /app/preload.php
opcache.preload_user = appuser
```

### PHP-FPM 进程调优公式

```bash
# 计算最优 max_children
# max_children = 可用内存 / 单个 worker 内存
# 单个 worker 内存查看：
docker stats --no-stream php
# 假设每个 worker 约 30MB，容器限制 512MB：
# max_children = 512 / 30 ≈ 17（保留系统开销后取 15）

# 实时监控 FPM 状态
curl -s http://localhost/fpm-status?full | grep -E "active|idle|total"
```

---

## 验证与测试

```bash
# 1. 构建并启动
docker compose build --no-cache
docker compose up -d

# 2. 验证非 root 运行
docker compose exec php id
# 期望输出: uid=1001(appuser) gid=1001(appgroup)

# 3. 验证只读文件系统
docker compose exec php touch /test 2>&1
# 期望: Read-only file system

# 4. 验证 capabilities 被删除
docker compose exec php cat /proc/self/status | grep Cap
# CapEff 和 CapPrm 应该全为 0

# 5. 验证 open_basedir 生效
docker compose exec php php -r "file_get_contents('/etc/passwd');"
# 期望: Warning: open_basedir restriction in effect

# 6. 验证 phpinfo 被禁用
# 访问 phpinfo() 应报错

# 7. 扫描镜像漏洞
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp/php:8.3-latest

# 8. 性能压测
ab -n 10000 -c 100 https://yourdomain.com/

# 9. 安全扫描
docker run --rm owasp/zap2docker-stable zap-baseline.py \
  -t https://yourdomain.com -r zap_report.html
```

---

## 项目目录结构

```
myapp/
├── docker/
│   ├── php/
│   │   ├── php.ini
│   │   ├── php-fpm.conf
│   │   ├── www.conf
│   │   └── preload.php
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       └── app.conf
│   ├── postgres/
│   │   └── postgresql.conf
│   └── seccomp/
│       └── php-fpm.json
├── secrets/           # .gitignore 排除
│   ├── db_password.txt
│   └── redis_password.txt
├── certs/             # TLS 证书，.gitignore 排除
├── src/
├── public/
│   └── index.php
├── composer.json
├── Dockerfile
├── docker-compose.yml
└── .env.example       # 模板，不含真实密码
```

---

> **注意：** 生产部署前请务必
> 1. 替换所有 `${PLACEHOLDER}` 占位符
> 2. 使用正式 TLS 证书（Let's Encrypt 或商业证书）
> 3. 定期更新基础镜像（`docker pull php:8.3-fpm-alpine`）
> 4. 每次更新后重新运行 `trivy` 漏洞扫描
> 5. 启用 Docker Content Trust：`export DOCKER_CONTENT_TRUST=1`
