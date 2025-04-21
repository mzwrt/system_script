#!/bin/bash

# 复制证书到 /opt/ssl 目录

rm -rf /mnt/XXXX.com/*

cp /opt/ssl/XXXX.com/privkey.pem /mnt/XXXX.com/
cp /opt/ssl/XXXX.com/fullchain.pem /mnt/XXXX.com/

chown -R xvpn:xvpn  /mnt/XXXX.com
chmod 750  /mnt/XXXX.com
chmod 600  /mnt/XXXX.com/privkey.pem
chmod 600  /mnt/XXXX.com/fullchain.pem
