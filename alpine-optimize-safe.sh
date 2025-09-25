#!/bin/sh
#
# Alpine Linux 安全优化脚本 (适配 NAT VPS)
# 使用方法：
#   PORT=12345 sh alpine-optimize-safe.sh
#   (不指定 PORT 时默认为 22)
#

set -e
PORT=${PORT:-22}

echo "=== [1/6] 更新镜像源 ==="
MIRROR="https://dl-cdn.alpinelinux.org/alpine"
# 如果需要国内镜像，可改成：
# MIRROR="https://mirrors.aliyun.com/alpine"
cp /etc/apk/repositories /etc/apk/repositories.bak.$(date +%F)
cat > /etc/apk/repositories <<EOF
$MIRROR/latest-stable/main
$MIRROR/latest-stable/community
EOF

echo "=== [2/6] 更新系统 ==="
apk update
apk upgrade --no-cache

echo "=== [3/6] 安装常用工具 ==="
apk add --no-cache \
    bash curl wget vim htop nano tzdata openssh sudo git \
    ca-certificates net-tools iproute2 bind-tools

echo "=== [4/6] 设置时区 ==="
TARGET_TZ="Asia/Shanghai"
cp /usr/share/zoneinfo/$TARGET_TZ /etc/localtime
echo "$TARGET_TZ" > /etc/timezone

echo "=== [5/6] 配置 SSH ==="
# 设置端口
if grep -q "^Port " /etc/ssh/sshd_config; then
    sed -i "s/^Port .*/Port $PORT/" /etc/ssh/sshd_config
else
    echo "Port $PORT" >> /etc/ssh/sshd_config
fi

# 保留密码登录
if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
    sed -i "s/^PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
else
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

# 允许 root 登录
if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i "s/^PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
else
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi

rc-update add sshd default
rc-service sshd restart || true

echo "=== [6/6] 清理缓存 ==="
apk cache clean || true

echo "==============================================="
echo "✅ 优化完成!"
echo "如果你设置了 NAT 端口映射，请用以下命令登录："
echo "ssh root@<你的公网IP> -p $PORT"
echo "未指定 PORT 时默认 22"
echo "==============================================="