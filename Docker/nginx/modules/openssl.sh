#!/bin/bash
wget --tries=5 --waitretry=2 --no-check-certificate https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
tar -zxvf openssl-${OPENSSL_VERSION}.tar.gz
mv openssl-${OPENSSL_VERSION} openssl
rm -f openssl-${OPENSSL_VERSION}.tar.gz
