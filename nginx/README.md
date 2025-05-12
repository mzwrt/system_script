# 🚀 自动构建集成多模块的 Nginx 脚本
本脚本用于从源码自动构建一套高度定制化的 Nginx，集成多种增强功能模块，适用于对性能、安全性、功能性有更高需求的用户或生产环境部署。<br>
本脚本微调即可适配 CIS Benchmarks 和 STIG（Security Technical Implementation Guides）	NIST SP 800 系列	等多个安全基准

# 📌 脚本作用
| 功能     | 说明                                                                           |
| ------ | ---------------------------------------------------------------------------- |
| 自动下载源码 | 自动从官方源获取 Nginx、依赖库和各类模块源码                                                    |
| 自动集成模块 | 自动集成 Brotli、Headers More、ModSecurity、OWASP CRS、Proxy Connect、Cache Purge 等模块 |
| 自动构建   | 一键编译并安装优化后的 Nginx                                                            |
| 高可维护性  | 模块版本自动匹配、脚本结构清晰、便于扩展或集成更多模块                                                  |


# 🛠️ 集成模块一览
| 模块名称                     | 功能说明                                 | 来源                                                                                                    |
| ------------------------ | ------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| **PCRE2**                | 支持正则表达式（用于 `rewrite`、`location` 等指令） | 官方源码                                                                                                  |
| **OpenSSL（自定义版本）**       | 启用 TLS 1.3、HTTP/2、安全加密支持             | 官方源码                                                                                                  |
| **Brotli Module**        | 提供高效的压缩算法，提升网页加载速度                   | [Google Brotli](https://github.com/google/ngx_brotli)                                                 |
| **Headers More**         | 允许添加、修改、删除响应头                        | [openresty/headers-more-nginx-module](https://github.com/openresty/headers-more-nginx-module)         |
| **ModSecurity 3.x**      | Web 应用防火墙引擎，提供强大的请求过滤能力              | [SpiderLabs/ModSecurity](https://github.com/SpiderLabs/ModSecurity)                                   |
| **OWASP CRS**            | OWASP 推荐的 Web 安全规则集                  | [coreruleset/coreruleset](https://github.com/coreruleset/coreruleset)                                 |
| **Proxy Connect Module** | 实现 CONNECT 请求代理（用于 HTTPS 代理穿透）       | [chobits/ngx\_http\_proxy\_connect\_module](https://github.com/chobits/ngx_http_proxy_connect_module) |
| **Cache Purge Module**   | 支持缓存清除功能（如 Nginx 缓存反向代理）             | [FRiCKLE/ngx\_cache\_purge](https://github.com/FRiCKLE/ngx_cache_purge)                               |
| **HTTP2 / HTTP3**   | 启用对 HTTP/2 和 HTTP/3（QUIC）的支持，提升连接并发能力和页面加载速度，减少延迟 | 内置于 NGINX（HTTP/2 通过 `--with-http_v2_module`，HTTP/3 通过 Cloudflare 的 [quiche 分支](https://github.com/cloudflare/quiche) 实现） |


⚙️ 编译特性
| 特性       | 描述                                         |
| -------- | ------------------------------------------ |
| 自定义路径支持  | 可指定源码下载目录、安装路径                             |
| 模块版本自动获取 | 支持通过 GitHub API 获取各模块最新版本                  |
| 多模块集成支持  | 支持同时编译多个第三方模块并链接入 Nginx                    |
| 安全增强     | 启用 ModSecurity + OWASP CRS 规则集，防御常见 Web 攻击 |
| 性能优化     | 启用 Brotli 压缩与 OpenSSL 最新加密协议               |
| 插件化      | 所有模块配置集中，便于按需开关或更换版本                       |

# 📌 文件说明
| 特性       | 描述                                         |
| -------- | ------------------------------------------ |
| nginx-install.sh  | 这个是 Nginx 自动化脚本文件                             |
| nginx.conf | 是 Nginx 配置文件，添加许多优化和安全参数根据 CIS Benchmarks 安全基准配置                  |
| nginx.service  |  Nginx systemd 单元文件 里面配置了很多安全参数和优化参数，对于高安全环境非常实用                   |
| proxy.conf     | 反响代理优化和一些安全参数 |
| cloudflare_ip.sh     | 自动化获取 CloudFlare IP 创建cloudflare_ip.conf 文件供 Nginx 来获取真实 IP               |
| XXXX.com.conf      | 这个是网站配置文件，根据 CIS Benchmarks 配置同时开启 http3 和 http2                        |
| crs-setup.conf  | 这个是 OWSCP CRS 规则配置文件，默认安全级别为：3 阻拦代码：403                             |
| modsecurity.conf  | 这个是 ModSecurity 配置文件                             |
| main.conf  | 这个是 OWSCP CRS 规则引入文件                             |
| hosts.deny  | 这个是 OWSCP CRS 规则 IP 黑名单文件。里面有详细说明                             |
| hosts.allow  | 这个是 OWSCP CRS 规则 IP 白名单文件。里面有详细说明                            |
| enable.sh  | 这个是 OWSCP CRS 开启文件，留作备用                             |


📥 支持平台
Debian / Ubuntu / 其他基于 APT 的系统
