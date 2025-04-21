#!/bin/bash
# 定期获取 cloudflare 的IP让nginx可以获取到用户真实IP
rm /opt/conf.d/sites-available/cloudflare_ip.conf
echo "#Cloudflare" > /opt/conf.d/sites-available/cloudflare_ip.conf;
for i in `curl https://www.cloudflare.com/ips-v4`; do
        echo "set_real_ip_from $i;" >> /opt/conf.d/sites-available/cloudflare_ip.conf;
done
for i in `curl https://www.cloudflare.com/ips-v6`; do
        echo "set_real_ip_from $i;" >> /opt/conf.d/sites-available/cloudflare_ip.conf;
done
echo "" >> /opt/conf.d/sites-available/cloudflare_ip.conf;
echo "# use any of the following two" >> /opt/conf.d/sites-available/cloudflare_ip.conf;
echo "real_ip_header CF-Connecting-IP;" >> /opt/conf.d/sites-available/cloudflare_ip.conf;
echo "#real_ip_header X-Forwarded-For;" >> /opt/conf.d/sites-available/cloudflare_ip.conf;
chmod 600 /opt/conf.d/sites-available/cloudflare_ip.conf
systemctl restart nginx
