#!/bin/bash
# ══════════════════════════════════════════════════════════
# 生成 MySQL TLS 自签证书（有效期10年）
# 执行：chmod +x gen-certs.sh && ./gen-certs.sh
# ══════════════════════════════════════════════════════════

set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo ">>> 生成 CA 根证书..."
openssl genrsa 4096 > ca-key.pem
openssl req -new -x509 -nodes -days 3650 \
  -key ca-key.pem \
  -subj "/C=CN/O=MySQL-CA/CN=MySQL-Root-CA" \
  -out ca-cert.pem

echo ">>> 生成服务端证书..."
openssl req -newkey rsa:4096 -nodes \
  -keyout server-key.pem \
  -subj "/C=CN/O=MySQL/CN=mysql-server" \
  -out server-req.pem
openssl x509 -req -days 3650 -set_serial 01 \
  -in server-req.pem \
  -out server-cert.pem \
  -CA ca-cert.pem -CAkey ca-key.pem

echo ">>> 生成客户端证书..."
openssl req -newkey rsa:4096 -nodes \
  -keyout client-key.pem \
  -subj "/C=CN/O=MySQL/CN=mysql-client" \
  -out client-req.pem
openssl x509 -req -days 3650 -set_serial 02 \
  -in client-req.pem \
  -out client-cert.pem \
  -CA ca-cert.pem -CAkey ca-key.pem

# 清理临时请求文件
rm -f server-req.pem client-req.pem

# 设置权限（私钥只有属主可读）
chmod 400 ca-key.pem server-key.pem client-key.pem
chmod 444 ca-cert.pem server-cert.pem client-cert.pem

echo ""
echo "✅ 证书生成完毕，位于 $CERT_DIR"
echo "   ca-cert.pem      - CA根证书（客户端验证服务器用）"
echo "   server-cert.pem  - 服务端证书"
echo "   server-key.pem   - 服务端私钥"
echo "   client-cert.pem  - 客户端证书（应用连接时使用）"
echo "   client-key.pem   - 客户端私钥"

# 验证证书链
echo ""
echo ">>> 验证证书链..."
openssl verify -CAfile ca-cert.pem server-cert.pem client-cert.pem
echo "✅ 证书链验证通过"
