#!/bin/bash

# 提示用户输入用户名
while true; do
    read -p "请输入用户名: " USER
    if [ -z "$USER" ]; then
        echo "用户名不能为空，请重新输入。"
    else
        break
    fi
done

# 检查用户是否存在
if id "$USER" &>/dev/null; then
    echo "用户 $USER 已存在，继续操作..."
else
    echo "用户 $USER 不存在，正在创建用户..."

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

    # 创建用户并设置密码
    sudo useradd -m -s /bin/bash "$USER"
    echo "$USER:$PASSWORD" | sudo chpasswd
    
    echo "用户 $USER 创建完成并设置密码。"
fi

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

# 设置路径
SSH_DIR="/home/$USER/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# 创建 .ssh 目录和 authorized_keys 文件
echo "创建 .ssh 目录和 authorized_keys 文件..."
mkdir -p $SSH_DIR
echo "$SSH_KEY" > $AUTHORIZED_KEYS

# 修正目录和文件所有者
echo "设置文件所有者为 $USER..."
sudo chown -R $USER:$USER $SSH_DIR

# 修改权限
echo "设置 .ssh 目录和 authorized_keys 文件权限..."
sudo chmod 700 $SSH_DIR
sudo chmod 600 $AUTHORIZED_KEYS

# 自动编辑 sudoers 文件并添加权限
echo "自动添加 sudo 权限..."

# 检查 sudoers 文件是否已经有该用户的配置
if ! sudo grep -q "^$USER" /etc/sudoers; then
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers > /dev/null
    echo "已成功为 $USER 添加 sudo 权限。"
else
    echo "$USER 已经具有 sudo 权限，无需修改。"
fi

# 结束脚本
echo "用户设置完毕。"
