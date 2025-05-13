#!/bin/bash

INSTALL_DIR="/mnt/xray"
USER="xvpn"

# 创建安装、卸载函数
install_xray() {
    echo "开始安装 Xray..."

    # 创建用户 'xvpn'，如果不存在
    if ! id -u $USER &>/dev/null; then
        echo "创建用户 $USER..."
        useradd -m -r -s /bin/false $USER
    fi

    # 确保安装目录存在
    mkdir -p $INSTALL_DIR

    # 获取最新的 Xray 版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | sed -n 's/.*"tag_name": "\(v[0-9]\+\.[0-9]\+\.[0-9]\+\)".*/\1/p')

    if [[ -z "$LATEST_VERSION" ]]; then
        echo "获取最新版本失败!"
        exit 1
    fi

    echo "最新版本是: $LATEST_VERSION"

    # 下载 Xray 最新版本
    ARCH="linux-64"  # 可以根据需要修改架构
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/$LATEST_VERSION/Xray-linux-64.zip"

    # 下载并解压 Xray
    echo "下载 Xray 版本 $LATEST_VERSION..."
    curl -L $DOWNLOAD_URL -o $INSTALL_DIR/Xray-linux-64.zip

    # 解压并清理
    unzip $INSTALL_DIR/Xray-linux-64.zip -d $INSTALL_DIR
    rm -f $INSTALL_DIR/Xray-linux-64.zip

    # 下载配置文件
    if [ ! -f $INSTALL_DIR/config.json ]; then
        wget -q -O $INSTALL_DIR/config.json "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/xray/config.json"
    fi

    # 设置权限
    chown -R $USER:$USER $INSTALL_DIR

    # 创建 systemd 服务文件
    wget -q -O /etc/systemd/system/xray.service "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/xray/xray.service"
    sed -i "s|\$INSTALL_DIR|$INSTALL_DIR|g" /etc/systemd/system/xray.service
    sed -i "s|\$USER|$USER|g" /etc/systemd/system/xray.service
    
    # 重新加载 systemd 配置并启动服务
    systemctl daemon-reload
    systemctl enable xray.service
    systemctl start xray.service

    echo "Xray 安装完成，服务已启动"
}

uninstall_xray() {
    echo "开始卸载 Xray..."

    # 停止并禁用 xray 服务
    systemctl stop xray.service
    systemctl disable xray.service

    # 删除 systemd 服务文件
    rm -f /etc/systemd/system/xray.service

    # 删除安装目录
    rm -rf $INSTALL_DIR

    # 删除用户
    userdel -r $USER

    # 重新加载 systemd 配置
    systemctl daemon-reload

    echo "Xray 已成功卸载"
}

exit_script() {
    echo "退出脚本..."
    exit 0
}

# 菜单选项
while true; do
    echo "请选择操作:"
    echo "1. 安装 Xray"
    echo "2. 卸载 Xray"
    echo "3. 退出"
    read -p "请输入数字 [1-3]: " choice

    case $choice in
        1)
            install_xray
            ;;
        2)
            uninstall_xray
            ;;
        3)
            exit_script
            ;;
        *)
            echo "无效的选择，请输入 1、2 或 3。"
            ;;
    esac
done

