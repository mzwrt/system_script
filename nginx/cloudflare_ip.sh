#!/bin/bash
# 定期获取 cloudflare 的IP让nginx可以获取到用户真实IP
set -euo pipefail

CLOUDFLARE_IP_CONF="%NGINX_DIR%/conf.d/sites-available/cloudflare_ip.conf"
CLOUDFLARE_IP_CONF_TMP="${CLOUDFLARE_IP_CONF}.tmp"

echo "#Cloudflare" > "$CLOUDFLARE_IP_CONF_TMP"
for i in $(curl --fail -sSL https://www.cloudflare.com/ips-v4); do
        echo "set_real_ip_from $i;" >> "$CLOUDFLARE_IP_CONF_TMP"
done
for i in $(curl --fail -sSL https://www.cloudflare.com/ips-v6); do
        echo "set_real_ip_from $i;" >> "$CLOUDFLARE_IP_CONF_TMP"
done
echo "" >> "$CLOUDFLARE_IP_CONF_TMP"
echo "# use any of the following two" >> "$CLOUDFLARE_IP_CONF_TMP"
echo "real_ip_header CF-Connecting-IP;" >> "$CLOUDFLARE_IP_CONF_TMP"
echo "#real_ip_header X-Forwarded-For;" >> "$CLOUDFLARE_IP_CONF_TMP"
mv -f "$CLOUDFLARE_IP_CONF_TMP" "$CLOUDFLARE_IP_CONF"
chmod 600 "$CLOUDFLARE_IP_CONF"
systemctl restart nginx
