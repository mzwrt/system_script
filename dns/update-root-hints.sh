#!/bin/bash

exec 9>/run/lock/unbound-root-update.lock
flock -n 9 || exit 1

ROOT_HINTS="/var/lib/unbound/root.hints"
ROOT_KEY="/var/lib/unbound/root.key"

curl -fsSL https://www.internic.net/domain/named.cache \
-o ${ROOT_HINTS}.new || exit 1

if [ -s ${ROOT_HINTS}.new ]; then
    mv ${ROOT_HINTS}.new ${ROOT_HINTS}
else
    exit 1
fi

unbound-anchor -a ${ROOT_KEY} -v

chown unbound:unbound ${ROOT_HINTS}
chmod 644 ${ROOT_HINTS}

chown unbound:unbound ${ROOT_KEY}
chmod 600 ${ROOT_KEY}

unbound-control reload_keep_cache

logger -t unbound "Monthly root hints and DNSSEC anchor updated"
