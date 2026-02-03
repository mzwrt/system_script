#!/bin/bash
git clone --recursive https://github.com/google/ngx_brotli.git $NGINX_SRC_DIR/ngx_brotli
cd ngx_brotli
git submodule update --init
