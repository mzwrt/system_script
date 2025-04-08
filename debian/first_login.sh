#!/bin/bash
if [ ! -f /etc/firstlogin.done ]; then
  echo "请输入新的用户名:"
  read new_user
  usermod -l $new_user jnfyic136dth24st2cqw7ke80m
  groupmod -n $new_user jnfyic136dth24st2cqw7ke80m
  mv /home/jnfyic136dth24st2cqw7ke80m /home/$new_user

  # 给新用户添加 sudo 权限
  usermod -aG sudo $new_user
  
  echo "修改用户名成功，记得使用新的用户名登录" > /home/$new_user/README.txt
  touch /etc/firstlogin.done

  # 清理首次登录脚本
  rm -f /etc/profile.d/first_login.sh
  rm -f /etc/firstlogin.done
fi
