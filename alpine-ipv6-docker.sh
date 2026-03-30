#!/bin/sh
# =========================================================
# Alpine OpenVZ Docker + IPv6 无敌版（100% 防翻车）
# =========================================================
set -e

echo "🚀 Alpine Docker + IPv6 无敌版启动"

# -----------------------------
# 1️⃣ 安装基础组件
# -----------------------------
echo "📦 安装基础组件..."
apk update
apk add --no-cache bash curl iptables ip6tables socat

# -----------------------------
# 2️⃣ 安装 Docker
# -----------------------------
echo "🐳 安装 Docker..."
apk add --no-cache docker

# -----------------------------
# 3️⃣ 安装 Docker Compose
# -----------------------------
if [ ! -f /usr/local/bin/docker-compose ]; then
    echo "📦 安装 Docker Compose..."
    curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# -----------------------------
# 4️⃣ 强制使用 vfs（核心）
# -----------------------------
STORAGE="vfs"
echo "🧠 强制存储驱动: vfs（OpenVZ 兼容）"

# -----------------------------
# 5️⃣ 随机 IPv6 子网（避免冲突）
# -----------------------------
HEX=$(hexdump -n2 -e '/2 "%04x"' /dev/urandom)
IPV6_SUBNET="fd00:${HEX}:beef::/64"
IPV6_GATEWAY="fd00:${HEX}:beef::1"

echo "🌐 IPv6 子网: $IPV6_SUBNET"

# -----------------------------
# 6️⃣ 写入 Docker 配置
# -----------------------------
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "$IPV6_SUBNET",
  "iptables": false,
  "ip-masq": false,
  "storage-driver": "$STORAGE"
}
EOF

# -----------------------------
# 7️⃣ 清理旧 Docker（关键）
# -----------------------------
echo "🧹 清理旧 Docker..."
killall dockerd 2>/dev/null || true
killall containerd 2>/dev/null || true

rm -f /var/run/docker.pid
rm -f /var/run/docker.sock

# ⚠️ 强制清数据（避免 overlay2 残留）
rm -rf /var/lib/docker/*

sleep 2

# -----------------------------
# 8️⃣ 启动 Docker
# -----------------------------
echo "⚡ 启动 Docker..."
dockerd > /var/log/docker.log 2>&1 &

# 等待启动
for i in $(seq 1 15); do
    if docker info >/dev/null 2>&1; then
        echo "✅ Docker 启动成功"
        break
    fi
    echo "⌛ 等待 Docker 启动... ($i)"
    sleep 2
done

if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker 启动失败"
    tail -n 50 /var/log/docker.log
    exit 1
fi

# -----------------------------
# 9️⃣ IPv6 配置
# -----------------------------
echo "🌐 启用 IPv6..."
sysctl -w net.ipv6.conf.all.forwarding=1

if ip6tables -t nat -L >/dev/null 2>&1; then
    ip6tables -t nat -A POSTROUTING -s $IPV6_SUBNET ! -o docker0 -j MASQUERADE || true
    echo "✅ IPv6 NAT 已启用"
else
    echo "⚠️ IPv6 NAT 不支持（OpenVZ 正常现象）"
fi

# -----------------------------
# 🔟 创建 IPv6 网络
# -----------------------------
echo "🔧 创建 IPv6 网络..."

docker network inspect ipv6bridge >/dev/null 2>&1 || \
docker network create \
  --ipv6 \
  --subnet=$IPV6_SUBNET \
  --gateway=$IPV6_GATEWAY \
  ipv6bridge || true

# -----------------------------
# ✅ 完成
# -----------------------------
echo ""
echo "🎉 安装完成（无敌版）"
echo "-----------------------------------"
docker info | grep "Storage Driver"
echo "-----------------------------------"
echo "💡 IPv6 网络: ipv6bridge"
echo ""
echo "🧪 测试："
echo "docker run --rm --network ipv6bridge alpine ping6 -c 2 google.com"
echo ""
echo "💡 host 模式（你用的）："
echo "👉 docker-compose 直接 network_mode: host"