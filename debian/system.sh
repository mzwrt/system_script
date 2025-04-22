#!/bin/bash

# ==========================
# 检查是否为 root 用户
# ==========================
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以 root 用户身份运行！"
    exit 1
fi

# ==========================
# 1. 用户输入部分
# ==========================
echo "请输入以下信息以开始系统配置："

# 提示用户输入用户名
while true; do
    read -p "请输入用户名: " USER
    if [ -z "$USER" ]; then
        echo "用户名不能为空，请重新输入。"
    else
        break
    fi
done

# 提示用户设置密码
while true; do
    read -sp "请输入密码: " PASSWORD
    echo
    if [ -z "$PASSWORD" ]; then
        echo "密码不能为空，请重新输入。"
    else
        break
    fi
done

# 提示用户输入 SSH 公钥
while true; do
    echo "请输入 SSH 公钥（复制并粘贴）："
    read -p "公钥: " SSH_KEY
    if [ -z "$SSH_KEY" ]; then
        echo "SSH 公钥不能为空，请重新输入。"
    else
        break
    fi
done

# 提示用户输入 SSH 端口
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

# ==========================
# 2. 替换 sysctl.conf 文件
# ==========================
echo "正在备份现有的 sysctl.conf 文件..."
cp /etc/sysctl.conf /etc/sysctl.conf.bak

echo "正在从指定链接下载新的 sysctl.conf 文件..."
wget -O /etc/sysctl.conf https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/debian/system/sysctl.conf

# 加载新的 sysctl 配置
echo "正在应用新的 sysctl 配置..."
sysctl -p

# ==========================
# 3. 系统更新及安装软件
# ==========================
echo "正在运行 apt-get clean 和 apt-get autoclean..."
apt-get clean && apt-get autoclean

echo "正在更新包列表..."
apt update -y

echo "正在升级已安装的软件包..."
apt upgrade -y

echo "正在安装常用软件包..."
apt install vim curl wget ufw sudo lsof htop -y

# 设置语言为中文简体
echo "正在设置系统语言为中文简体..."
update-locale LANG=zh_CN.UTF-8

# 设置时区为中国
echo "正在设置时区为中国..."
timedatectl set-timezone Asia/Shanghai

# ==========================
# 4. 用户设置与 SSH 配置
# ==========================
# 检查用户是否存在
if id "$USER" &>/dev/null; then
    echo "用户 $USER 已存在，继续操作..."
else
    echo "用户 $USER 不存在，正在创建用户..."
    # 创建用户并设置密码
    useradd -m -s /bin/bash "$USER"
    echo "$USER:$PASSWORD" | chpasswd
    echo "用户 $USER 创建完成并设置密码。"
fi

# 设置 SSH 公钥
SSH_DIR="/home/$USER/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
echo "正在为用户 $USER 创建 .ssh 目录和 authorized_keys 文件..."
mkdir -p $SSH_DIR
echo "$SSH_KEY" > $AUTHORIZED_KEYS

# 修正目录和文件所有者
echo "设置 .ssh 目录及 authorized_keys 文件所有者为 $USER..."
chown -R $USER:$USER $SSH_DIR

# 修改权限
echo "设置 .ssh 目录和 authorized_keys 文件的权限..."
chmod 700 $SSH_DIR
chmod 600 $AUTHORIZED_KEYS

# 自动编辑 sudoers 文件并添加权限
echo "正在为用户 $USER 自动添加 sudo 权限..."
if ! grep -q "^$USER" /etc/sudoers; then
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers > /dev/null
    echo "已成功为 $USER 添加 sudo 权限。"
else
    echo "$USER 已经具有 sudo 权限，无需修改。"
fi

# ==========================
# 5. 配置 SSH
# ==========================
# 备份当前的 sshd_config 文件
echo "正在备份现有的 SSH 配置文件..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 下载新的 sshd_config 文件
echo "正在从指定链接下载新的 sshd_config 文件..."
wget -O /etc/ssh/sshd_config https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/debian/system/sshd_config

# 修改 sshd_config 文件中的端口设置
echo "正在修改 SSH 配置文件中的端口为：$SSH_PORT..."
sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config

# 修改 AllowUsers 和 AllowGroups 字段
echo "正在修改 AllowUsers 和 AllowGroups 字段..."
sed -i "/^#AllowUsers/ c\AllowUsers $USER" /etc/ssh/sshd_config
sed -i "/^AllowUsers/ c\AllowUsers $USER" /etc/ssh/sshd_config

sed -i "/^#AllowGroups/ c\AllowGroups $USER" /etc/ssh/sshd_config
sed -i "/^AllowGroups/ c\AllowGroups $USER" /etc/ssh/sshd_config

# ==========================
# 6. 自动检测防火墙并放通端口
# ==========================
echo "正在检测防火墙类型..."
if command -v ufw >/dev/null 2>&1; then
    echo "检测到 ufw 防火墙，正在允许端口 $SSH_PORT..."
    ufw allow $SSH_PORT/tcp
    ufw reload
    echo "端口 $SSH_PORT 已允许通过 ufw。"
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "检测到 firewalld 防火墙，正在允许端口 $SSH_PORT..."
    firewall-cmd --zone=public --add-port=$SSH_PORT/tcp --permanent
    firewall-cmd --reload
    echo "端口 $SSH_PORT 已允许通过 firewalld。"
elif command -v iptables >/dev/null 2>&1; then
    echo "检测到 iptables 防火墙，正在允许端口 $SSH_PORT..."
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    iptables-save
    echo "端口 $SSH_PORT 已允许通过 iptables。"
else
    echo "未检测到已知的防火墙类型，无法自动放通端口。"
fi

# ==========================
# 7. 提示是否重启 SSH 服务
# ==========================
while true; do
    read -p "是否重启 SSH 服务以应用配置更改？(Y/N): " RESTART_SSH
    case $RESTART_SSH in
        [Yy]* )
            echo "正在重新启动 SSH 服务..."
            systemctl restart sshd
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

# ==========================
# 8. 是否安装 webmin
# ==========================
while true; do
    read -p "是否安装 webmin ？(Y/N): " INSTALL_WEBMIN
    case $INSTALL_WEBMIN in
        [Yy]* )
            echo "正在重新启动 SSH 服务..."
            curl -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh && chmod +x webmin-setup-repo.sh
            sh webmin-setup-repo.sh
            apt-get update
            apt-get install webmin --install-recommends
            echo "Webmin 已安装并且 SSH 服务已重启。"
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

# 设置 vi
wget -O /root/.vimrc https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/debian/.vimrc

# ==========================
# 8. 完成提示
# ==========================
echo "操作已完成！以下是系统配置的详细信息："
echo "===================================="
echo "系统语言已设置为中文简体，时区已设置为中国（上海）。"
echo "SSH 服务已配置，新的端口为：$SSH_PORT。"
echo "已为用户 $USER 配置了 SSH 登录权限，允许登录的组为：$USER。"
echo "已为用户 $USER 配置了 sudo 权限和 sudo 免密码登陆权限。"
echo "防火墙已配置，端口 $SSH_PORT 已成功放通。"
echo "如有需要，请重启 SSH 服务以确保配置生效。"
echo "已经将vi 配置文件下载到/root/.vimrc如果不喜欢配置风格可以使用此命令删除：rm -f /root/.vimrc"
