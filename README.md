注意：私人文件，不懂不要乱用，乱用导致的损失自己承担
# - debian 配置脚本
   ```bash
   wget -O /tmp/system.sh https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/debian/system.sh && bash /tmp/system.sh && rm -f /tmp/system.sh
```

# - nginx 安装脚本 (注意：卸载会删除所有文件，都在/opt里面注意备份)
默认安装到`/opt`目录里面，包括`ModSecurity`防火墙和规则，有wordpress规则
   ```bash
   wget -O /tmp/nginx-install.sh https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/nginx-install.sh && bash /tmp/nginx-install.sh && rm -f /tmp/nginx-install.sh
```

# - xray 安装脚本
默认安装到`/mnt`目录里面
   ```bash
   wget -O /tmp/install-xray.sh https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/xray/install-xray.sh && bash /tmp/install-xray.sh && rm -f /tmp/install-xray.sh
```
