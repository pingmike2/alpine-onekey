#!/bin/sh
# =========================================================
# Alpine 3.14 OpenVZ/LXC 一键 IPv6 Docker 安装脚本（vfs 存储驱动）
# =========================================================
set -e

echo "🚀 Alpine 一键安装 Docker + Docker Compose + IPv6 (OpenVZ vfs 专用版)"

# -----------------------------
# 1️⃣ 安装基础工具
# -----------------------------
echo "📦 更新 APK 源并安装基础工具..."
apk update
apk add --no-cache bash curl socat ip6tables openrc iptables

# -----------------------------
# 2️⃣ 安装 Docker
# -----------------------------
echo "🐳 安装 Docker..."
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
# 4️⃣ 配置 Docker daemon.json（IPv6 + vfs 存储驱动）
# -----------------------------
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
DEFAULT_IPV6_SUBNET="fd00:dead:beef::/48"

echo "🔧 配置 Docker daemon.json..."
mkdir -p /etc/docker
cat > "$DOCKER_DAEMON_JSON" <<EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "$DEFAULT_IPV6_SUBNET",
  "iptables": false,
  "ip-masq": false,
  "storage-driver": "vfs"
}
EOF

# -----------------------------
# 5️⃣ 后台启动 Docker daemon并等待启动完成
# -----------------------------
echo "⚡ 启动 Docker daemon..."
dockerd -H unix:///var/run/docker.sock > /var/log/docker.log 2>&1 &

# 等待 Docker daemon 启动
for i in $(seq 1 10); do
    if docker info >/dev/null 2>&1; then
        echo "✅ Docker daemon 已启动"
        break
    fi
    echo "⌛ 等待 Docker daemon 启动... ($i/10)"
    sleep 2
done

if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon 启动失败，请查看 /var/log/docker.log"
    exit 1
fi

# -----------------------------
# 6️⃣ 配置 IPv6 NAT（有条件执行）
# -----------------------------
echo "🌐 配置 IPv6 NAT..."
sysctl -w net.ipv6.conf.all.forwarding=1

if ip6tables -t nat -L >/dev/null 2>&1; then
    ip6tables -t nat -A POSTROUTING -s $DEFAULT_IPV6_SUBNET ! -o docker0 -j MASQUERADE || true
else
    echo "⚠️ IPv6 NAT 表不存在，跳过 MASQUERADE"
fi

# -----------------------------
# 7️⃣ 创建自定义 IPv6 网络（不触碰默认 bridge）
# -----------------------------
echo "🔧 创建自定义 IPv6 bridge 网络 ipv6bridge..."
docker network inspect ipv6bridge >/dev/null 2>&1 || \
docker network create \
    --ipv6 \
    --subnet=$DEFAULT_IPV6_SUBNET \
    --gateway=fd00:dead:beef::1 \
    -o com.docker.network.bridge.enable_icc=true \
    ipv6bridge

# -----------------------------
# 8️⃣ 输出安装完成信息
# -----------------------------
echo "🎉 安装完成！"
echo "📌 Docker IPv6 默认子网: $DEFAULT_IPV6_SUBNET"
echo "💡 启动容器请使用自定义网络：--network ipv6bridge"
echo "示例：docker run --rm --network ipv6bridge alpine ping6 -c 2 google.com"

docker version
docker-compose version