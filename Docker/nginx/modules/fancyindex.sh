#!/bin/bash
wget --tries=5 --waitretry=2 --no-check-certificate https://github.com/aperezdc/ngx-fancyindex/releases/download/v${fancyindex_VERSION}/ngx-fancyindex-${fancyindex_VERSION}.tar.xz
tar -xJvf ngx-fancyindex-${fancyindex_VERSION}.tar.xz
mv ngx-fancyindex-${fancyindex_VERSION} ngx_fancyindex
rm -f ngx-fancyindex-${fancyindex_VERSION}.tar.xz
