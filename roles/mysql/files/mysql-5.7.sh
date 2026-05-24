#!/bin/bash
set -e

# 检查是否已安装，幂等性处理
if [ -f /usr/local/mysql/bin/mysql ]; then
    echo "MySQL 已安装，跳过"
    exit 0
fi

ROOT_PASS="$1"

yum install libaio -y
tar -xf mysql-5.7.31-linux-glibc2.12-x86_64.tar.gz
mv mysql-5.7.31-linux-glibc2.12-x86_64 /usr/local/mysql
useradd -r -s /sbin/nologin mysql

if [ -f /etc/my.cnf ]; then
    mv /etc/my.cnf /etc/my.cnf.bak
fi

cd /usr/local/mysql
mkdir mysql-files
chown mysql:mysql mysql-files
chmod 750 mysql-files
bin/mysqld --initialize --user=mysql --basedir=/usr/local/mysql &>/root/password.txt

cat > /etc/my.cnf <<EOF
[mysqld]
basedir=/usr/local/mysql
datadir=/usr/local/mysql/data
socket=/tmp/mysql.sock
port=3306
log-error=/usr/local/mysql/data/mysql.err
log-bin=/usr/local/mysql/data/binlog
server-id=10
character_set_server=utf8mb4
gtid-mode=on
log-slave-updates=1
enforce-gtid-consistency
sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES
EOF

bin/mysql_ssl_rsa_setup --datadir=/usr/local/mysql/data

cat <<EOF | sudo tee /etc/systemd/system/mysqld.service
[Unit]
Description=MySQL Server
After=network.target
After=syslog.target

[Service]
User=mysql
Group=mysql
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf
LimitNOFILE = 5000
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start mysqld

echo "等待MySQL启动..."
for i in $(seq 1 30); do
    if [ -S /tmp/mysql.sock ]; then
        echo "MySQL启动完成"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "MySQL启动失败，请检查日志"
        exit 1
    fi
    sleep 2
done

systemctl enable mysqld
cd /usr/local/mysql
bin/mysqladmin -uroot password "$ROOT_PASS" -p$(cat /root/password.txt |grep password | awk '{print $NF}')

echo 'export PATH=$PATH:/usr/local/mysql/bin' > /etc/profile.d/mysql.sh

ln -s /lib64/libncurses.so.6 /lib64/libncurses.so.5
ln -s /lib64/libtinfo.so.6 /lib64/libtinfo.so.5

/usr/local/mysql/bin/mysql -uroot -p"$ROOT_PASS" << EOF
create database if not exists wordpress default charset=utf8;
EOF
