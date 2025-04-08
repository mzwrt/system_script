#!/bin/bash

# 确保脚本在 root 权限下执行
if [ "$(id -u)" -ne 0 ]; then
  echo "当前用户不是 root，正在切换到 root 用户..."
  
  # 从文件中读取 root 密码
  root_password=$(cat /etc/root_password.txt)

  # 使用 sudo 执行后续命令
  sudo bash -c '
    # 询问新用户名并修改
    echo "请输入新的用户名:"
    read new_user

    # 确保用户名不为空
    if [ -z "$new_user" ]; then
      echo "用户名不能为空，退出脚本"
      exit 1
    fi

    # 修改用户名
    usermod -l $new_user jnfyic136dth24st2cqw7ke80m
    groupmod -n $new_user jnfyic136dth24st2cqw7ke80m

    # 确保目标目录不存在
    if [ -d "/home/$new_user" ]; then
      echo "目录 /home/$new_user 已存在，无法修改用户名"
      exit 1
    fi

    # 修改用户主目录
    mv /home/jnfyic136dth24st2cqw7ke80m /home/$new_user

    # 给新用户添加 sudo 权限
    usermod -aG sudo $new_user

    # 提示修改用户名成功
    echo "修改用户名成功，记得使用新的用户名登录" > /home/$new_user/README.txt

    # 修改 root 密码
    echo "请输入新的 root 密码:"
    read -s root_password_new
    echo "$root_password_new" | passwd root

    # 修改新用户密码
    echo "请输入新用户 ($new_user) 密码:"
    read -s new_user_password
    echo "$new_user:$new_user_password" | chpasswd

    # 设置 firstlogin.done，防止脚本重复执行
    touch /etc/firstlogin.done

    # 清理首次登录脚本
    rm -f /etc/profile.d/first_login.sh
    rm -f /etc/firstlogin.done
    rm -f /etc/root_password.txt

    # 安装自定义包
    apt-get clean && apt-get autoclean && apt-get update -y && apt-get upgrade -y
    apt install vim sudo curl wget ufw htop -y

    echo "首次登录配置完成。"
  '
fi
