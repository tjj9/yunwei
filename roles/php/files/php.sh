#!/bin/bash
set -e

# 关闭SELinux（否则php-fpm写不了PID文件）
if [ "$(getenforce 2>/dev/null)" != "Disabled" ]; then
    setenforce 0 2>/dev/null || true
    sed -i '/SELINUX=enforcing/cSELINUX=disabled' /etc/selinux/config 2>/dev/null || true
fi

# ========== 编译安装PHP（仅首次执行） ==========
if [ ! -f /usr/local/php/bin/php ]; then
    # 安装依赖库
    dnf install epel-release -y
    dnf -y install libxml2-devel libjpeg-devel libpng-devel libwebp-devel freetype-devel curl-devel openssl-devel sqlite sqlite-devel libtool pcre-devel gd-devel libsodium

    id www &> /dev/null
    if [ $? -ne 0 ];then
        useradd -r -s /sbin/nologin www
    fi

    # 安装 oniguruma 库
    cd /usr/local/src
    tar -zxvf onig-6.9.8.tar.gz
    cd onig-6.9.8
    ./configure  && make && make install

    export ONIG_CFLAGS="-I/usr/include"
    export ONIG_LIBS="-L/usr/lib -lonig"

    # 安装libsodium库
    cd /usr/local/src
    tar -xzvf libsodium-1.0.20.tar.gz
    cd libsodium-1.0.20
    ./configure && make && make install
    ldconfig

    export LIBSODIUM_CFLAGS="-I/usr/local/include"
    export LIBSODIUM_LIBS="-L/usr/local/lib -lsodium"
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

    # 安装低版本库openssl-1.1.1
    cd /usr/local/src
    dnf remove openssl-devel -y || true
    dnf install make gcc perl-core zlib-devel -y
    tar -xf openssl-1.1.1w.tar.gz
    cd openssl-1.1.1w
    ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib
    make && make install

    export PKG_CONFIG_PATH=/usr/local/openssl/lib/pkgconfig:$PKG_CONFIG_PATH
    export LD_LIBRARY_PATH=/usr/local/openssl/lib:$LD_LIBRARY_PATH
    export OPENSSL_CFLAGS="-I/usr/local/openssl/include"
    export OPENSSL_LIBS="-L/usr/local/openssl/lib -lssl -lcrypto"

    # 编译安装PHP
    cd
    tar -zxf php-7.4.33.tar.gz
    cd php-7.4.33

    ./configure --prefix=/usr/local/php --with-config-file-path=/usr/local/php/etc --enable-fpm --with-fpm-user=www --with-fpm-group=www --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-iconv --with-freetype --with-jpeg --with-zlib --enable-gd --with-external-gd --with-xpm --with-webp --enable-xml --disable-rpath --enable-bcmath --enable-shmop --enable-sysvsem --with-curl --enable-mbregex --enable-mbstring --enable-ftp --with-openssl=/usr/local/openssl --with-mhash --enable-sockets --enable-soap --without-pear --with-gettext  --enable-pcntl --with-sodium --enable-fileinfo

    make -j$(nproc) && make install

    cp /root/php-7.4.33/php.ini-development /usr/local/php/etc/php.ini
fi

# ========== 配置php-fpm（每次都执行） ==========
cp /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf
cp /usr/local/php/etc/php-fpm.d/www.conf.default /usr/local/php/etc/php-fpm.d/www.conf

sed -i 's#^; *pid = run/php-fpm.pid#pid = run/php-fpm.pid#' /usr/local/php/etc/php-fpm.conf
sed -i 's#^; *daemonize = yes#daemonize = yes#' /usr/local/php/etc/php-fpm.conf

cat > /usr/lib/systemd/system/php-fpm.service <<EOF
[Unit]
Description=PHP FastCGI Process Manager
After=network.target

[Service]
Type=forking
PIDFile=/usr/local/php/var/run/php-fpm.pid
ExecStart=/usr/local/php/sbin/php-fpm --fpm-config /usr/local/php/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
ExecStop=/bin/kill -QUIT \$MAINPID
TimeoutStartSec=180
LimitNOFILE=65535
LimitNPROC=500
PrivateTmp=true
User=www
Group=www

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /usr/local/php/var/run
touch /usr/local/php/var/log/php-fpm.log
chmod 664 /usr/local/php/var/log/php-fpm.log
chown -R www.www /usr/local/php

find /usr/local/openssl -name "libssl.so.1.1" | tee /etc/ld.so.conf.d/openssl-1.1.conf
ldconfig

systemctl daemon-reload
systemctl enable php-fpm
systemctl restart php-fpm

sleep 2
if systemctl is-active php-fpm &>/dev/null; then
    echo "php-fpm 启动成功"
else
    echo "php-fpm 启动失败，查看日志: journalctl -u php-fpm --no-pager | tail -20"
    exit 1
fi

echo 'export PATH=$PATH:/usr/local/php/bin' > /etc/profile.d/php.sh
