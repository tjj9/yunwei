#!/bin/bash
set -e

# 检查是否已部署，幂等性处理
if [ -d /usr/local/nginx/html/wp-admin ]; then
    echo "WordPress 已部署，跳过"
    exit 0
fi

tar -xf wordpress-6.7.1.tar.gz
rm -rf /usr/local/nginx/html
mv wordpress /usr/local/nginx/html
