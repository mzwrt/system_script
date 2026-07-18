#!/bin/bash
set -e

SRC="/opt/nginx/ssl/ihccc.com"

UNBOUND_DST="/etc/unbound/tls"
DNSDIST_DST="/etc/dnsdist/certs"

CERT="${SRC}/fullchain.pem"
KEY="${SRC}/privkey.pem"


if [ ! -f "$CERT" ]; then
    logger -t dns-cert "Certificate missing: $CERT"
    exit 1
fi

if [ ! -f "$KEY" ]; then
    logger -t dns-cert "Key missing: $KEY"
    exit 1
fi


############################
# Unbound DoT
############################

mkdir -p "$UNBOUND_DST"

cp -f "$CERT" "$UNBOUND_DST/cert.pem"
cp -f "$KEY" "$UNBOUND_DST/key.pem"

chown root:unbound \
"$UNBOUND_DST/cert.pem" \
"$UNBOUND_DST/key.pem"

chmod 644 "$UNBOUND_DST/cert.pem"
chmod 640 "$UNBOUND_DST/key.pem"


############################
# dnsdist DoH
############################

mkdir -p "$DNSDIST_DST"

cp -f "$CERT" "$DNSDIST_DST/cert.pem"
cp -f "$KEY" "$DNSDIST_DST/key.pem"


chown _dnsdist:_dnsdist \
"$DNSDIST_DST/cert.pem" \
"$DNSDIST_DST/key.pem"

chmod 644 "$DNSDIST_DST/cert.pem"
chmod 600 "$DNSDIST_DST/key.pem"



systemctl reload unbound || true
systemctl restart dnsdist


logger -t dns-cert "Certificate updated for Unbound and dnsdist"
