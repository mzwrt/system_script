#!/bin/bash

# 备份当前的 sshd_config 文件
echo "正在备份现有的 SSH 配置文件..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 下载新的 sshd_config 文件
echo "正在从指定链接下载新的 sshd_config 文件..."
sudo wget -O /etc/ssh/sshd_config https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/debian/system/sshd_config

# 提示用户修改 SSH 端口
while true; do
    read -p "请输入要修改的 SSH 端口（默认 22）： " SSH_PORT
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
        break
    elif [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1024 ] && [ "$SSH_PORT" -le 65535 ]; then
        break
    else
        echo "端口号无效，请输入 1024 到 65535 之间的数字。"
    fi
done

# 修改 sshd_config 文件中的端口设置
echo "正在修改 SSH 配置文件中的端口..."
sudo sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i "s/^Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config

# 自动检测所有拥有 SSH 登录权限的用户（排除 root 用户）
echo "正在检测所有拥有 SSH 登录权限的用户..."

ALLOW_USERS=$(getent passwd | awk -F: '{if (($7 == "/bin/bash" || $7 == "/bin/sh") && $1 != "root") print $1}' | tr '\n' ' ')

# 获取这些用户所在的组
ALLOW_GROUPS=$(getent passwd | awk -F: '{if (($7 == "/bin/bash" || $7 == "/bin/sh") && $1 != "root") print $4}' | tr '\n' ' ')

# 修改 AllowUsers 和 AllowGroups 字段
echo "正在修改 AllowUsers 和 AllowGroups 字段..."
sudo sed -i "/^#AllowUsers/ c\AllowUsers $ALLOW_USERS" /etc/ssh/sshd_config
sudo sed -i "/^AllowUsers/ c\AllowUsers $ALLOW_USERS" /etc/ssh/sshd_config

sudo sed -i "/^#AllowGroups/ c\AllowGroups $ALLOW_GROUPS" /etc/ssh/sshd_config
sudo sed -i "/^AllowGroups/ c\AllowGroups $ALLOW_GROUPS" /etc/ssh/sshd_config

# 提示用户是否重启 SSH 服务
while true; do
    read -p "是否重启 SSH 服务以应用配置更改？(Y/N): " RESTART_SSH
    case $RESTART_SSH in
        [Yy]* )
            echo "正在重新启动 SSH 服务..."
            sudo systemctl restart sshd
            break
            ;;
        [Nn]* )
            echo "SSH 服务未重启，请手动重启 SSH 服务以应用更改。"
            break
            ;;
        * )
            echo "请输入 Y 或 N。"
            ;;
    esac
done

# 自动检测防火墙类型并放通端口
echo "正在检测防火墙类型..."
if command -v ufw >/dev/null 2>&1; then
    # 使用 ufw 防火墙
    echo "检测到 ufw 防火墙，正在允许端口 $SSH_PORT..."
    sudo ufw allow $SSH_PORT/tcp
    sudo ufw reload
    echo "端口 $SSH_PORT 已允许通过 ufw。"
elif command -v firewall-cmd >/dev/null 2>&1; then
    # 使用 firewalld 防火墙
    echo "检测到 firewalld 防火墙，正在允许端口 $SSH_PORT..."
    sudo firewall-cmd --zone=public --add-port=$SSH_PORT/tcp --permanent
    sudo firewall-cmd --reload
    echo "端口 $SSH_PORT 已允许通过 firewalld。"
elif command -v iptables >/dev/null 2>&1; then
    # 使用 iptables 防火墙
    echo "检测到 iptables 防火墙，正在允许端口 $SSH_PORT..."
    sudo iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    sudo iptables-save
    echo "端口 $SSH_PORT 已允许通过 iptables。"
else
    echo "未检测到已知的防火墙类型，无法自动放通端口。"
fi

# 提示完成
echo "SSH 配置已更新，新的端口是：$SSH_PORT，允许登录的用户为：$ALLOW_USERS，允许登录的组为：$ALLOW_GROUPS。"
echo "如果无法通过 SSH 连接，请检查防火墙设置或确保新端口已打开。"
