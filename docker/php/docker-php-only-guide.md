# Docker PHP-FPM 安全安装指南（纯 PHP）
## CIS Benchmark / 最小权限 / 高性能 / 生产级

---

## 目录
1. [基础镜像选择](#基础镜像选择)
2. [Dockerfile](#dockerfile)
3. [php.ini 安全配置](#phpini-安全配置)
4. [PHP-FPM 配置](#php-fpm-配置)
5. [docker-compose（仅 PHP）](#docker-compose)
6. [Seccomp Profile](#seccomp-profile)
7. [验证清单](#验证清单)

---

## 基础镜像选择

```
php:8.3-fpm-alpine   ✅ 推荐（~30MB，最小攻击面）
php:8.3-fpm          ❌ Debian，体积臃肿（~150MB）
php:latest           ❌ 版本不固定，不可预测
```

---

## Dockerfile

```dockerfile
# =============================================================
# Stage 1: Builder（编译扩展，生产镜像不含编译工具）
# =============================================================
FROM php:8.3-fpm-alpine AS builder

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
    && pecl install redis-6.0.2 \
    && docker-php-ext-enable redis \
    && apk del $PHPIZE_DEPS \
    && rm -rf /tmp/pear /var/cache/apk/*

# Composer（仅用于安装依赖）
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY composer.json composer.lock ./

RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts \
    && composer clear-cache

COPY . .

# =============================================================
# Stage 2: Runtime（最终镜像，无任何编译工具）
# =============================================================
FROM php:8.3-fpm-alpine AS runtime

# 只安装运行时库
RUN apk add --no-cache \
    libpng \
    libjpeg-turbo \
    libwebp \
    freetype \
    oniguruma \
    libzip \
    icu-libs \
    libpq \
    tzdata \
    && rm -rf /var/cache/apk/*

# 从 builder 复制编译好的扩展和配置
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/    /usr/local/etc/php/conf.d/

# =============================================================
# 创建非 root 用户（CIS 4.6）
# =============================================================
RUN addgroup -g 1001 -S appgroup \
    && adduser -u 1001 -S appuser -G appgroup -h /app -s /sbin/nologin

# 创建必要目录
RUN mkdir -p /var/log/php-fpm /tmp/php \
    && chown -R appuser:appgroup /var/log/php-fpm /tmp/php \
    && chmod 700 /tmp/php

# 复制应用代码
COPY --from=builder --chown=appuser:appgroup /app /app

# 复制配置（root 拥有，只读）
COPY --chown=root:root docker/php/php.ini          /usr/local/etc/php/php.ini
COPY --chown=root:root docker/php/php-fpm.conf     /usr/local/etc/php-fpm.conf
COPY --chown=root:root docker/php/www.conf         /usr/local/etc/php-fpm.d/www.conf

RUN chmod 644 /usr/local/etc/php/php.ini \
    && chmod 644 /usr/local/etc/php-fpm.conf \
    && chmod 644 /usr/local/etc/php-fpm.d/www.conf

# 删除默认多余配置
RUN rm -f /usr/local/etc/php-fpm.d/docker.conf \
          /usr/local/etc/php-fpm.d/zz-docker.conf

# 删除应用内不需要的文件
RUN find /app -name ".git" -o -name ".env.example" \
    -o -name "Makefile" -o -name "phpunit*" \
    -o -name "*.md" 2>/dev/null | xargs rm -rf || true

WORKDIR /app

# 以非 root 用户运行
USER appuser

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD php-fpm -t 2>&1 | grep -q "syntax is OK" || exit 1

EXPOSE 9000

CMD ["php-fpm", "--nodaemonize", "--force-stderr"]
```

---

## php.ini 安全配置

```ini
; ============================================================
; docker/php/php.ini - 生产安全配置
; ============================================================

[PHP]

; ---- 信息泄露防护 ----
expose_php             = Off
display_errors         = Off
display_startup_errors = Off
html_errors            = Off
error_reporting        = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors             = On
error_log              = /var/log/php-fpm/php_errors.log

; ---- 文件操作安全 ----
allow_url_fopen    = Off          ; 禁止远程文件打开（防 SSRF）
allow_url_include  = Off          ; 禁止远程文件包含（防 RFI）
open_basedir       = /app:/tmp/php ; 文件系统沙箱

; 禁用危险函数
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,\
    curl_exec,curl_multi_exec,parse_ini_file,show_source,phpinfo,\
    pcntl_exec,posix_kill,posix_mkfifo,posix_setpgid,posix_setsid,\
    posix_setuid,posix_getpwuid,posix_uname,proc_get_status,\
    proc_nice,proc_terminate,symlink,link,readlink

; ---- 资源限制 ----
file_uploads           = On
upload_max_filesize    = 10M
max_file_uploads       = 5
post_max_size          = 12M
max_execution_time     = 30
max_input_time         = 30
memory_limit           = 128M
max_input_vars         = 1000
max_input_nesting_level = 64

; ---- Session 安全 ----
session.use_strict_mode    = 1
session.cookie_secure      = 1
session.cookie_httponly    = 1
session.cookie_samesite    = Strict
session.use_cookies        = 1
session.use_only_cookies   = 1
session.use_trans_sid      = 0
session.cookie_lifetime    = 0
session.gc_maxlifetime     = 1440
session.sid_length         = 48
session.sid_bits_per_character = 6
session.name               = __Secure-SSID

; ---- 其他 ----
default_charset    = "UTF-8"
date.timezone      = Asia/Shanghai
realpath_cache_size = 4096k
realpath_cache_ttl  = 600

; ============================================================
; OPcache（高性能）
; ============================================================
[opcache]
opcache.enable                   = 1
opcache.enable_cli               = 0
opcache.memory_consumption       = 128
opcache.interned_strings_buffer  = 16
opcache.max_accelerated_files    = 20000
opcache.validate_timestamps      = 0    ; 生产关闭，更新需重启容器
opcache.revalidate_freq          = 0
opcache.fast_shutdown            = 1
opcache.enable_file_override     = 1
opcache.optimization_level       = 0x7FFEBFFF
opcache.file_cache_consistency_checks = 1

; 预加载（可选，需创建 preload.php）
; opcache.preload      = /app/preload.php
; opcache.preload_user = appuser
```

---

## PHP-FPM 配置

### php-fpm.conf（主配置）

```ini
; docker/php/php-fpm.conf
[global]
pid                   = /tmp/php/php-fpm.pid
error_log             = /var/log/php-fpm/php-fpm.log
log_level             = warning
log_limit             = 4096
emergency_restart_threshold = 10
emergency_restart_interval  = 1m
process_control_timeout     = 10s
daemonize             = no

include=/usr/local/etc/php-fpm.d/www.conf
```

### www.conf（worker pool）

```ini
; docker/php/www.conf
[www]

user  = appuser
group = appgroup

; Unix Socket（比 TCP 快且更安全，与 Nginx 共享 volume）
listen            = /tmp/php/php-fpm.sock
listen.owner      = nobody      ; 改为你的 Nginx 运行用户
listen.group      = nobody
listen.mode       = 0660

; ---- 进程管理 ----
; 公式：max_children = 容器内存限制 / 单 worker 内存（通常 25~40MB）
; 示例：512MB / 30MB ≈ 17，保守取 15
pm                     = dynamic
pm.max_children        = 15
pm.start_servers       = 5
pm.min_spare_servers   = 3
pm.max_spare_servers   = 10
pm.max_requests        = 500    ; 防内存泄漏
pm.process_idle_timeout = 10s

; ---- 超时 ----
request_terminate_timeout = 30s
request_slowlog_timeout   = 5s
slowlog                   = /var/log/php-fpm/slow.log

; ---- 安全：清除宿主机环境变量 ----
clear_env = yes

; 只注入必要的环境变量
env[APP_ENV]      = $APP_ENV
env[DB_HOST]      = $DB_HOST
env[DB_PORT]      = $DB_PORT
env[DB_NAME]      = $DB_NAME
env[DB_USER]      = $DB_USER
env[DB_PASSWORD]  = $DB_PASSWORD

; ---- 状态监控（仅内网访问）----
pm.status_path = /fpm-status
ping.path      = /fpm-ping
ping.response  = pong

; ---- 安全 ----
security.limit_extensions = .php   ; 只允许执行 .php
chdir = /app
```

---

## docker-compose（仅 PHP）

```yaml
# docker-compose.yml

version: "3.9"

services:
  php:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
    image: myapp/php:8.3

    restart: unless-stopped

    # 非 root 运行（CIS 5.1）
    user: "1001:1001"

    # 只读根文件系统（CIS 5.4）
    read_only: true
    tmpfs:
      - /tmp/php:uid=1001,gid=1001,mode=0700,size=64m
      - /tmp:uid=1001,gid=1001,mode=1777,size=32m

    # 丢弃全部 Capabilities（CIS 5.3）
    cap_drop:
      - ALL

    # 防止权限提升（CIS 5.2）
    security_opt:
      - no-new-privileges:true
      - seccomp:docker/seccomp/php-fpm.json

    # 资源限制（CIS 5.7）
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 512M
        reservations:
          cpus: "0.5"
          memory: 256M

    volumes:
      # Socket 与 Nginx 共享（Nginx 容器挂同一个 volume）
      - php_socket:/tmp/php
      # 日志持久化
      - php_logs:/var/log/php-fpm

    # Secrets（不用明文环境变量）
    secrets:
      - db_password

    environment:
      APP_ENV:   production
      DB_HOST:   "your-db-host"
      DB_PORT:   "5432"
      DB_NAME:   myapp
      DB_USER:   appuser
      DB_PASSWORD_FILE: /run/secrets/db_password

    # 不对外暴露端口（通过 socket 或内部网络）
    expose:
      - "9000"

    # 只接入内部网络
    networks:
      - app_internal

    healthcheck:
      test: ["CMD", "php-fpm", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

networks:
  app_internal:
    driver: bridge
    internal: true    # 禁止直接访问外部网络

volumes:
  php_socket:
    driver: local
  php_logs:
    driver: local

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

---

## Seccomp Profile

```json
// docker/seccomp/php-fpm.json
// 白名单模式，只允许 PHP-FPM 必要的系统调用
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
  "syscalls": [
    {
      "names": [
        "accept4", "access", "arch_prctl", "bind", "brk",
        "clone", "clone3", "close", "connect",
        "dup", "dup2", "dup3",
        "epoll_create1", "epoll_ctl", "epoll_pwait", "epoll_wait",
        "execve", "exit", "exit_group",
        "faccessat", "fadvise64", "fchdir", "fchmod", "fchown",
        "fcntl", "flock", "fstat", "fstatfs", "fsync", "ftruncate",
        "futex", "getcwd", "getdents64",
        "getegid", "geteuid", "getgid", "getpid", "getppid",
        "getrandom", "getrlimit", "getsockname", "getsockopt",
        "gettid", "gettimeofday", "getuid",
        "inotify_add_watch", "inotify_init1", "inotify_rm_watch",
        "ioctl", "kill", "listen", "lseek", "lstat",
        "madvise", "mkdir", "mmap", "mprotect", "mremap", "munmap",
        "nanosleep", "newfstatat", "open", "openat", "openat2",
        "pipe", "pipe2", "poll", "ppoll", "prctl",
        "pread64", "prlimit64", "pwrite64",
        "read", "readlink", "readlinkat", "readv",
        "recvfrom", "recvmsg", "rename", "renameat", "renameat2",
        "rmdir", "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "sched_getaffinity", "sched_yield",
        "select", "sendmsg", "sendto",
        "set_robust_list", "set_tid_address",
        "setgid", "setgroups", "setitimer", "setrlimit",
        "setsockopt", "setuid", "shutdown", "sigaltstack",
        "socket", "socketpair", "splice",
        "stat", "statfs", "statx",
        "tgkill", "timerfd_create", "timerfd_settime",
        "umask", "uname", "unlink", "unlinkat",
        "utimensat", "wait4", "waitid",
        "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

---

## 验证清单

```bash
# 1. 构建
docker compose build --no-cache

# 2. 启动
docker compose up -d

# 3. 验证非 root 运行
docker compose exec php id
# ✅ uid=1001(appuser) gid=1001(appgroup)

# 4. 验证只读文件系统
docker compose exec php touch /test 2>&1
# ✅ Read-only file system

# 5. 验证 capabilities 全部丢弃
docker compose exec php cat /proc/self/status | grep Cap
# ✅ CapEff: 0000000000000000

# 6. 验证 open_basedir 沙箱
docker compose exec php php -r "file_get_contents('/etc/passwd');"
# ✅ Warning: open_basedir restriction in effect

# 7. 验证危险函数被禁用
docker compose exec php php -r "system('id');"
# ✅ Warning: system() has been disabled

# 8. 验证 OPcache 生效
docker compose exec php php -r "var_dump(opcache_get_status()['opcache_enabled']);"
# ✅ bool(true)

# 9. 镜像漏洞扫描
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp/php:8.3

# 10. CIS 合规自动检查
docker run --rm --net host --pid host --userns host \
  --cap-add audit_control \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc:/etc:ro \
  docker/docker-bench-security
```

---

## 目录结构

```
myapp/
├── docker/
│   ├── php/
│   │   ├── php.ini
│   │   ├── php-fpm.conf
│   │   └── www.conf
│   └── seccomp/
│       └── php-fpm.json
├── secrets/            # 加入 .gitignore
│   └── db_password.txt
├── src/
├── public/
│   └── index.php
├── composer.json
├── Dockerfile
└── docker-compose.yml
```

```bash
# 初始化 secrets 目录
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 > secrets/db_password.txt
chmod 600 secrets/db_password.txt
echo "secrets/" >> .gitignore
```

---

## CIS 对照（PHP 容器部分）

| 控制项 | 实现方式 | 状态 |
|---|---|---|
| 4.1 固定镜像版本 | `php:8.3-fpm-alpine` | ✅ |
| 4.2 最小化安装 | Alpine + 多阶段构建 | ✅ |
| 4.6 非 root 运行 | `USER appuser (1001)` | ✅ |
| 5.1 非特权模式 | 无 `privileged: true` | ✅ |
| 5.2 防权限提升 | `no-new-privileges:true` | ✅ |
| 5.3 丢弃 Capabilities | `cap_drop: ALL` | ✅ |
| 5.4 只读文件系统 | `read_only: true` + tmpfs | ✅ |
| 5.7 资源限制 | CPU + Memory limits | ✅ |
| 5.13 网络隔离 | `internal: true` 网络 | ✅ |
| 5.28 Seccomp | 自定义白名单 profile | ✅ |
