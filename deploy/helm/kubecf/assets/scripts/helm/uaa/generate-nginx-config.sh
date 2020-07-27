#!/usr/bin/env bash
set -o errexit -o nounset -o xtrace -o pipefail
cp /run/secrets/uaa-ssl/* /run/nginx-config/
cat > /run/nginx-config/nginx.conf <<"EOF"
events {}
stream {
    server {
    listen 8443 ssl;

    ssl_certificate     /etc/nginx/certificate;
    ssl_certificate_key /etc/nginx/private_key;

    proxy_pass localhost:8080;
    }
}
EOF
