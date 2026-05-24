#!/bin/bash
set -e

# 检查是否已安装，幂等性处理
if [ -f /usr/local/nginx/sbin/nginx ]; then
    echo "Nginx 已安装，跳过"
    exit 0
fi

dnf -y install pcre-devel zlib-devel openssl-devel
useradd -r -s /sbin/nologin www

tar xvf nginx-1.24.0.tar.gz
cd nginx-1.24.0
./configure --prefix=/usr/local/nginx --user=www --group=www --with-http_ssl_module --with-http_stub_status_module --with-http_realip_module
make && make install

if [ -f /usr/local/nginx/logs/nginx.pid ]; then
    /usr/local/nginx/sbin/nginx -s quit 2>/dev/null || true
fi

cat > /usr/lib/systemd/system/nginx.service <<EOF
[Unit]
Description=Nginx Web Server
After=network.target
  
[Service]
Type=forking
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
PrivateTmp=true
  
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start nginx
systemctl enable nginx
