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

echo "=== [附加检测] 检查是否需要重启 ==="
# 检查当前内核与已安装内核版本是否一致
CURRENT_KERNEL=$(uname -r 2>/dev/null || echo "unknown")
INSTALLED_KERNEL=$(apk info -v | grep '^linux-' | head -n1 | awk '{print $1}')

if [ -n "$INSTALLED_KERNEL" ] && [ "$CURRENT_KERNEL" != "unknown" ]; then
    if ! echo "$CURRENT_KERNEL" | grep -q "$(echo "$INSTALLED_KERNEL" | cut -d'-' -f2-)"; then
        echo "⚠️ 检测到系统已安装新内核 ($INSTALLED_KERNEL)"
        echo "当前运行内核版本: $CURRENT_KERNEL"
        echo "👉 建议执行 reboot 以加载新内核"
        NEED_REBOOT=1
    else
        echo "✅ 当前内核 ($CURRENT_KERNEL) 已是最新，无需重启。"
        NEED_REBOOT=0
    fi
else
    echo "ℹ️ 无法检测内核版本，可能是非标准虚拟机或精简系统。"
    NEED_REBOOT=0
fi

echo "==============================================="
echo "✅ 优化完成!"
echo "SSH 登录方式：ssh root@<你的公网IP> -p $PORT"
echo "未指定 PORT 时默认 22"
if [ "$NEED_REBOOT" -eq 1 ]; then
    echo "⚠️ 建议现在执行：reboot"
else
    echo "✅ 无需重启，可立即使用。"
fi
echo "==============================================="