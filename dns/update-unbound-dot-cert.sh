#!/bin/bash

SRC="/opt/nginx/ssl/mzwrt.com"

UNBOUND_DST="/etc/unbound/tls"
DNSDIST_DST="/etc/dnsdist/certs"

CERT="${SRC}/fullchain.pem"
KEY="${SRC}/privkey.pem"


if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    logger -t dns-cert "Certificate files missing"
    exit 1
fi


########################
# Unbound DoT
########################

mkdir -p "$UNBOUND_DST"


cp "$CERT" "${UNBOUND_DST}/cert.pem.new"
cp "$KEY" "${UNBOUND_DST}/key.pem.new"


mv "${UNBOUND_DST}/cert.pem.new" \
   "${UNBOUND_DST}/cert.pem"

mv "${UNBOUND_DST}/key.pem.new" \
   "${UNBOUND_DST}/key.pem"


chown root:unbound \
"${UNBOUND_DST}/cert.pem" \
"${UNBOUND_DST}/key.pem"


chmod 644 "${UNBOUND_DST}/cert.pem"
chmod 640 "${UNBOUND_DST}/key.pem"


systemctl restart unbound



########################
# dnsdist DoH
########################

mkdir -p "$DNSDIST_DST"


cp "$CERT" "${DNSDIST_DST}/cert.pem.new"
cp "$KEY" "${DNSDIST_DST}/key.pem.new"


mv "${DNSDIST_DST}/cert.pem.new" \
   "${DNSDIST_DST}/cert.pem"

mv "${DNSDIST_DST}/key.pem.new" \
   "${DNSDIST_DST}/key.pem"


chown _dnsdist:_dnsdist \
"${DNSDIST_DST}/cert.pem" \
"${DNSDIST_DST}/key.pem"


chmod 644 "${DNSDIST_DST}/cert.pem"
chmod 600 "${DNSDIST_DST}/key.pem"


systemctl restart dnsdist


logger -t dns-cert "DoT and DoH certificates updated"
