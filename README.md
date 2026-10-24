# alpine-onekey

Alpine / OpenVZ / LXC 小鸡一键脚本。

## 1. 系统安全优化

```sh
# 先看会改什么，不动系统（推荐）
curl -fsSL https://raw.githubusercontent.com/pingmike2/alpine-onekey/main/alpine-optimize-safe.sh | sh -s -- --dry-run

# 正式执行（不改 SSH 端口）
curl -fsSL https://raw.githubusercontent.com/pingmike2/alpine-onekey/main/alpine-optimize-safe.sh | sh

# 需要顺带全量升级时
curl -fsSL https://raw.githubusercontent.com/pingmike2/alpine-onekey/main/alpine-optimize-safe.sh | sh -s -- --upgrade
```

v2 相对 v1 的行为变化（v1 备份在 `alpine-optimize-safe.v1.bak.sh`）：

- **不改 SSH 端口**：脚本先探测 sshd 实际监听端口，`PORT` 与之不一致时直接拒绝。
  NAT 小鸡的外网端口由宿主机映射，把内网端口改成外网端口 = 永久失联。
- 改 sshd 前自动备份、`sshd -t` 校验、重启后回连自检，异常自动回滚。
- APK 源锁定当前版本分支（如 v3.22），不再改写成 `latest-stable`，避免跨大版本漂移顶坏依赖。
- 去掉 `set -e`，单步失败只告警不中断，避免留下半套配置。
- 重复执行不再重复追加 `PasswordAuthentication` / `PermitRootLogin`（自动去重）。
- `apk upgrade` 改为默认关闭，只有 `--upgrade` 才执行；磁盘可用 <200MB 时自动跳过安装。
- sysctl 只写容器实际允许写的键，写入 `/etc/sysctl.d/99-alpine-optimize.conf`，
  并由 `/etc/local.d/99-alpine-optimize.start` 在开机时重放（容器重启后内核参数会丢）。
- 会显示 cgroup 真实内存上限：LXC 里 `free` 看到的是宿主机内存，容易误判。

## 2. 一键 Docker + IPv6

```sh
curl -fsSL https://raw.githubusercontent.com/pingmike2/alpine-onekey/main/alpine-ipv6-docker.sh | sh
```

注意：该脚本会清空 `/var/lib/docker`（`rm -rf /var/lib/docker/*`），已有容器和镜像会丢。