#!/bin/bash

ROOT_HINTS="/var/lib/unbound/root.hints"
ROOT_KEY="/var/lib/unbound/root.key"

curl -fsSL https://www.internic.net/domain/named.cache \
-o ${ROOT_HINTS}.new || exit 1

mv ${ROOT_HINTS}.new ${ROOT_HINTS}

unbound-anchor -a ${ROOT_KEY}

chown unbound:unbound ${ROOT_HINTS} ${ROOT_KEY}

unbound-control reload_keep_cache

logger -t unbound "Monthly root hints and DNSSEC anchor updated"
