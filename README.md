# WordPress 一键部署（Ansible 自动化运维项目）

## 项目简介
通过 Ansible 剧本，在四组服务器上分别部署 MySQL、Nginx + WordPress、PHP-FPM、Prometheus + Grafana 监控栈，实现从裸机到可访问 WordPress 网站 + 全链路监控的一键自动化部署。

## 架构图

```
管理机 (master)
    │
    ├── group1 ── MySQL 5.7.31 + mysqld_exporter + node_exporter
    ├── group2 ── Nginx 1.24.0 + WordPress 6.7.1 + nginx_exporter + node_exporter
    ├── group3 ── PHP 7.4.33（php-fpm）+ node_exporter（与 group2 同机部署）
    └── group4 ── Prometheus 2.45.0 + Grafana 10.2.2
```

## 技术栈
- **配置管理**：Ansible（Roles 标准结构）
- **数据库**：MySQL 5.7.31（GTID 主从就绪配置）
- **Web 服务器**：Nginx 1.24.0（编译安装）
- **后端语言**：PHP 7.4.33 + php-fpm
- **应用**：WordPress 6.7.1
- **监控告警**：Prometheus + Grafana + node_exporter / nginx_exporter / mysqld_exporter

## Nginx 增强特性
- **速率限制**：limit_req_zone 限制单 IP 10请求/秒，burst 20
- **带宽限制**：limit_conn_zone 限制并发连接数
- **防盗链**：valid_referers 实现图片/资源防盗链（返回403）
- **动静分离**：静态文件（js/css/ico）缓存7天，图片缓存30天，减少 PHP 处理压力
- **运行状态**：stub_status 端点供 Prometheus nginx_exporter 采集指标

## 监控栈
- **Prometheus**：时序数据库，采集 exporter 指标，默认端口 9090
- **Grafana**：可视化面板，默认端口 3000（初始账号 admin/admin）
- **node_exporter**：采集服务器 CPU、内存、磁盘、网络等系统指标，端口 9100
- **nginx_exporter**：采集 Nginx 连接数、请求速率、状态码分布，端口 9113
- **mysqld_exporter**：采集 MySQL QPS、连接数、慢查询等指标，端口 9104
- **告警规则**：
  - CPU 负载超过 80%（持续 5 分钟）
  - 磁盘空间低于 20%
  - 5xx 错误率超过 1%（持续 2 分钟）

## 前置条件
1. 四台 CentOS Stream 9 服务器，配置好静态 IP 和 yum 源
2. 管理机已安装 Ansible：`dnf install ansible -y`
3. 管理机已实现对各服务器的免密登录：`ssh-copy-id IP`
4. 所有服务器已关闭防火墙和 SELinux、已同步时间
5. 所有节点可正常访问 GitHub Releases 和 Grafana 官方仓库（用于下载 prometheus/grafana/exporters）

## 主机清单配置
编辑 `/etc/ansible/hosts`，添加：
```
[group1]
192.168.8.101

[group2]
192.168.8.102

[group3]
192.168.8.102

[group4]
192.168.8.103
```

## 使用步骤

### 1. 下载所需软件包
将以下压缩包放入对应角色的 `files/` 目录（监控组件运行时自动从 GitHub 下载，无需手动准备）：

| 角色 | 文件 | 下载地址 |
|------|------|---------|
| mysql | `mysql-5.7.31-linux-glibc2.12-x86_64.tar.gz` | MySQL 官网 |
| nginx | `nginx-1.24.0.tar.gz` | nginx.org |
| nginx | `wordpress-6.7.1.tar.gz` | WordPress.org |
| php | `php-7.4.33.tar.gz` | php.net |
| php | `onig-6.9.8.tar.gz` | GitHub Releases |
| php | `libsodium-1.0.20.tar.gz` | libsodium.org |
| php | `openssl-1.1.1w.tar.gz` | openssl.org |

### 2. 修改 Prometheus 目标 IP
编辑 `roles/monitoring/files/prometheus.yml`，将 `targets` 中的 IP 地址替换为你的实际服务器 IP。

### 3. 部署文件到管理机
```bash
cp -r roles/* /etc/ansible/roles/
cp wordpress.yaml /etc/ansible/playbook/
```

### 4. 执行部署
```bash
ansible-playbook /etc/ansible/playbook/wordpress.yaml
```

### 5. 访问网站
浏览器打开 `http://192.168.8.102`（group2 的 IP），按 WordPress 安装向导完成配置。

### 6. 访问监控
- **Prometheus**：`http://192.168.8.103:9090`
- **Grafana**：`http://192.168.8.103:3000`（初始账号 admin/admin）

## 项目结构
```
roles/
├── mysql/
│   ├── tasks/main.yml        # MySQL + mysqld_exporter + node_exporter 部署任务
│   └── files/mysql-5.7.sh    # 编译安装 MySQL 脚本
├── nginx/
│   ├── tasks/main.yml        # Nginx + WordPress + exporters 部署任务
│   ├── files/nginx.sh        # 编译安装 Nginx 脚本
│   ├── files/nginx.conf      # Nginx 配置文件（限流/防盗链/动静分离/status）
│   └── files/wordpress.sh    # 解压部署 WordPress 脚本
├── php/
│   ├── tasks/main.yml        # PHP + node_exporter 部署任务
│   └── files/php.sh          # 编译安装 PHP + php-fpm 脚本
└── monitoring/
    ├── tasks/main.yml        # Prometheus + Grafana 部署任务
    └── files/
        ├── prometheus.yml     # 抓取配置（4组 targets）
        ├── alert_rules.yml    # 告警规则（CPU/磁盘/5xx）
        └── prometheus.service # systemd 服务文件
```

## 端口映射

| 端口 | 服务 | 所在组 |
|------|------|--------|
| 80   | Nginx / WordPress | group2 |
| 9090 | Prometheus | group4 |
| 3000 | Grafana | group4 |
| 9100 | node_exporter | group1/2/3 |
| 9113 | nginx_exporter | group2 |
| 9104 | mysqld_exporter | group1 |
| 9000 | php-fpm | group3 |

## 特性
- **幂等性**：所有脚本带检查逻辑，重复执行不报错
- **密码参数化**：MySQL root 密码通过 Playbook 变量传入
- **标准 Roles 结构**：符合 Ansible 官方规范，易于扩展
- **四组架构**：数据库 / Web / PHP / 监控 分离，贴合生产实践
- **全链路监控**：从系统层（CPU/磁盘）到应用层（Nginx 5xx、MySQL QPS）全覆盖
- **生产级 Nginx 配置**：限流、防盗链、动静分离开箱即用

