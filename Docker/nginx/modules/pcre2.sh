#!/bin/bash
wget --tries=5 --waitretry=2 --no-check-certificate "https://github.com/PhilipHazel/pcre2/releases/download/$pcre2_version/$pcre2_version.tar.gz"
tar -zxf "$pcre2_version.tar.gz"
mv "$pcre2_version" "pcre2"
rm -f "$pcre2_version.tar.gz"
