#!/bin/bash

DEFAULT_USER="jnfyic136dth24st2cqw7ke80m"

# 确保脚本在 root 权限下执行
if [ "$(id -u)" -ne 0 ]; then
  echo "您当前不是以 root 用户身份运行脚本。尝试使用 sudo 切换为 root 用户..."
  
  # 读取存储的 root 密码
  ROOT_PASSWORD=$(cat /etc/root_password.txt)
  
  # 使用 echo 和 sudo 执行 su 命令来切换到 root 用户
  echo "$ROOT_PASSWORD" | sudo -S bash "$0" "$@"
  
  # 脚本退出，避免继续执行
  exit 0
fi

echo "## 注意 ##"
echo "下面的操作较为关键，请谨慎操作。"

# 检查并删除非 root 和新用户的 sudo 权限
cleanup_sudo_users() {
  # 获取所有具有 sudo 权限的用户
  sudo_users=$(getent group sudo | cut -d: -f4)
  IFS=',' read -r -a sudo_user_array <<< "$sudo_users"

  # 删除非 root 和新用户的 sudo 权限
  for user in "${sudo_user_array[@]}"; do
    if [ "$user" != "root" ] && [ "$user" != "$new_user" ]; then
      echo "正在删除用户 $user 的 sudo 权限..."
      deluser "$user" sudo
    fi
  done
}

while true; do
  # 设置新用户名
  while true; do
    echo -n "请输入新的用户名: "
    read new_user
    if [ -z "$new_user" ]; then
      echo "用户名不能为空，请重新输入。"
    else
      break
    fi
  done

  # 用户名不同且目标目录不存在则重命名
  if [ "$new_user" != "$DEFAULT_USER" ]; then
    if [ -d "/home/$new_user" ]; then
      echo "目录 /home/$new_user 已存在，跳过用户重命名。"
    else
      usermod -l "$new_user" "$DEFAULT_USER"
      groupmod -n "$new_user" "$DEFAULT_USER"
      mv "/home/$DEFAULT_USER" "/home/$new_user"
      echo "用户名已修改为 $new_user。"
    fi
  else
    echo "用户名与默认相同，不做修改。"
  fi

  # 添加 sudo 权限
  usermod -aG sudo "$new_user"

  # 清理其他 sudo 用户
  cleanup_sudo_users

  # 修改主目录权限
  chown -R "$new_user:$new_user" "/home/$new_user"

  # 修改 root 密码
  while true; do
    echo -n "请输入新的 root 密码: "
    read -s root_password_new
    echo
    if [ -z "$root_password_new" ]; then
      echo "root 密码不能为空，请重新输入。"
    else
      echo "$root_password_new" | passwd root
      break
    fi
  done

  # 修改新用户密码
  while true; do
    echo -n "请输入 $new_user 的密码: "
    read -s new_user_password
    echo
    if [ -z "$new_user_password" ]; then
      echo "$new_user 的密码不能为空，请重新输入。"
    else
      echo "$new_user:$new_user_password" | chpasswd
      break
    fi
  done

  # 删除原始用户（如果已改名）
  if [ "$new_user" != "$DEFAULT_USER" ]; then
    id "$DEFAULT_USER" &>/dev/null && userdel -f "$DEFAULT_USER"
  fi

  # 安装软件包
  apt-get clean && apt-get autoclean && apt-get update -y && apt-get upgrade -y
  apt install -y vim sudo curl wget ufw htop

  # 最后确认
  while true; do
    echo -n "所有设置已完成，是否确认无误并删除首次登录脚本？输入Y将清理所有自定义文件，输入N将重新设置。[Y/n]: "
    read confirm
    case "$confirm" in
      [Yy] )
        rm -f /etc/profile.d/first_login.sh
        [ -f /etc/root_password.txt ] && rm -f /etc/root_password.txt
        echo "首次登录配置完成。"
        exit 0
        ;;
      [Nn] )
        echo "请重新执行配置..."
        break
        ;;
      * )
        echo "请输入 Y 或 N。"
        ;;
    esac
  done
done
