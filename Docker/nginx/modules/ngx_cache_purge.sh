#!/bin/bash
wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/FRiCKLE/ngx_cache_purge/archive/refs/tags/$ngx_cache_purge_version.zip" 
unzip "$ngx_cache_purge_version.zip"
mv "ngx_cache_purge-$ngx_cache_purge_version" "ngx_cache_purge"
rm -f "$ngx_cache_purge_version.zip"
