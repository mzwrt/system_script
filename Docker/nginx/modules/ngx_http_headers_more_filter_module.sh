#!/bin/bash
  wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${ngx_http_headers_more_filter_module_version}.tar.gz"
  tar -xzf "v${ngx_http_headers_more_filter_module_version}.tar.gz"
  mv "headers-more-nginx-module-${ngx_http_headers_more_filter_module_version#v}" headers-more-nginx-module
  rm -f "v${ngx_http_headers_more_filter_module_version}.tar.gz"
