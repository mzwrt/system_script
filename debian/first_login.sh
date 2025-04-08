#!/bin/bash

# 检查是否是 root 用户，如果不是则使用 sudo su 进行切换
if [ "$(id -u)" -ne 0 ]; then
  echo "当前用户不是 root，正在切换到 root 用户..."
  
  # 使用预设的 root 密码来自动切换为 root 并执行脚本
  root_password="your_root_password"
  
  # 使用 echo 自动输入 root 密码并执行脚本
  echo $root_password | sudo -S su <<EOF
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

    # 修改用户主目录
    mv /home/jnfyic136dth24st2cqw7ke80m /home/$new_user

    # 给新用户添加 sudo 权限
    usermod -aG sudo $new_user

    # 提示修改用户名成功
    echo "修改用户名成功，记得使用新的用户名登录" > /home/$new_user/README.txt

    # 修改 root 密码
    echo "请输入新的 root 密码:"
    read -s root_password_new
    echo "$root_password_new" | chpasswd

    # 修改新用户密码
    echo "请输入新用户 ($new_user) 密码:"
    read -s new_user_password
    echo "$new_user:$new_user_password" | chpasswd

    # 设置 firstlogin.done，防止脚本重复执行
    touch /etc/firstlogin.done

    # 清理首次登录脚本
    rm -f /etc/profile.d/first_login.sh
    rm -f /etc/firstlogin.done

    # 安装自定义包
    apt-get clean && apt-get autoclean && apt update -y && apt upgrade -y
    apt install vim sudo curl wget ufw htop -y

    echo "首次登录配置完成。"
EOF
fi
