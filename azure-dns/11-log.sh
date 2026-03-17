cat > /etc/logrotate.d/modsecurity << 'EOF'
/opt/nginx/logs/owasp/*.log {
    daily
    rotate 365
    compress
    delaycompress
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d
    create 640 www-data adm
}
EOF

cat > /etc/logrotate.d/unbound << 'EOF'
/var/log/unbound/*.log {
    daily
    rotate 365
    compress
    delaycompress
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d
    create 640 unbound unbound
    sharedscripts
    postrotate
        /usr/sbin/unbound-control log_reopen 2>/dev/null || true
    endscript
}
EOF
