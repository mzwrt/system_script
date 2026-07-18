#!/bin/bash

SRC="/opt/nginx/ssl/ihccc.com"
DST="/etc/unbound/tls"

CERT="${SRC}/fullchain.pem"
KEY="${SRC}/privkey.pem"

if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    logger -t unbound-dot "Certificate files missing"
    exit 1
fi

mkdir -p "$DST"

cp -f "$CERT" "${DST}/cert.pem"
cp -f "$KEY" "${DST}/key.pem"

chown unbound:unbound "${DST}/cert.pem" "${DST}/key.pem"

chmod 644 "${DST}/cert.pem"
chmod 600 "${DST}/key.pem"

unbound-control reload

logger -t unbound-dot "DoT certificate updated and Unbound reloaded"
