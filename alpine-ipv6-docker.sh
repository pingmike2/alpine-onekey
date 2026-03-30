#!/bin/sh
# =========================================================
# Alpine 一键 IPv6 Docker 安装 + IPv6 NAT 配置 + Docker IPv6 网络
# =========================================================
set -e

echo "🚀 开始安装 Docker + Docker Compose + IPv6..."

# -----------------------------
# 1️⃣ 更新 APK 源 & 安装基础工具
# -----------------------------
apk update
apk add --no-cache bash curl iptables ip6tables socat openrc

# -----------------------------
# 2️⃣ 安装 Docker
# -----------------------------
apk add --no-cache docker

# -----------------------------
# 3️⃣ 安装 Docker Compose（官方二进制）
# -----------------------------
DOCKER_COMPOSE_BIN="/usr/local/bin/docker-compose"
if [ ! -f "$DOCKER_COMPOSE_BIN" ]; then
    echo "📦 安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o "$DOCKER_COMPOSE_BIN"
    chmod +x "$DOCKER_COMPOSE_BIN"
fi

# -----------------------------
# 4️⃣ 启动 Docker 并开机自启
# -----------------------------
rc-update add docker boot
service docker start

# -----------------------------
# 5️⃣ 配置 Docker IPv6 网络
# -----------------------------
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

# 默认 IPv6 子网，可根据 VPS 分配修改
DEFAULT_IPV6_SUBNET="fd00:dead:beef::/48"

if [ ! -f "$DOCKER_DAEMON_JSON" ]; then
    echo "🔧 创建 Docker daemon.json 配置..."
    cat > "$DOCKER_DAEMON_JSON" <<EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "$DEFAULT_IPV6_SUBNET"
}
EOF
else
    echo "⚠️ daemon.json 已存在，请手动确保 ipv6 配置存在"
fi

# -----------------------------
# 6️⃣ 重启 Docker 生效 IPv6
# -----------------------------
service docker restart

# -----------------------------
# 7️⃣ 配置 IPv6 NAT 转发（让容器能访问公网 IPv6）
# -----------------------------
echo "🌐 配置 IPv6 NAT..."
# 启用内核转发
sysctl -w net.ipv6.conf.all.forwarding=1

# 添加 ip6tables NAT 规则
ip6tables -t nat -A POSTROUTING -s $DEFAULT_IPV6_SUBNET ! -o docker0 -j MASQUERADE || true

# -----------------------------
# 8️⃣ 创建 Docker 默认 IPv6 网络（容器默认使用）
# -----------------------------
docker network rm bridge || true
docker network create \
  --ipv6 \
  --subnet=$DEFAULT_IPV6_SUBNET \
  --gateway=fd00:dead:beef::1 \
  -o com.docker.network.bridge.name=bridge \
  -o com.docker.network.bridge.enable_icc=true \
  bridge

# -----------------------------
# 9️⃣ 验证安装
# -----------------------------
echo "✅ 验证 Docker 与 Docker Compose..."
docker version
docker-compose version

echo "🎉 安装完成！Docker 已开启 IPv6。"
echo "🌐 默认 IPv6 子网：$DEFAULT_IPV6_SUBNET"
echo "💡 容器默认网络已开启 IPv6，自动获取 IPv6 并可访问公网。"
