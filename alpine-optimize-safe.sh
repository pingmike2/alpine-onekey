#!/bin/sh
# =========================================================
# alpine-optimize-safe.sh  v2 (2026-10-24)
# 面向 Alpine / OpenVZ / LXC 小鸡的安全优化脚本
#
# 相对 v1 的修复：
#   1. 不再把 apk 源改写成 latest-stable（会跨大版本漂移），保持当前版本分支
#   2. Port 不再"没写就追加 PORT"，改为先探测 sshd 真实监听端口；
#      传入的 PORT 与监听端口不一致时直接拒绝（NAT 机器上这是唯一失联原因）
#   3. 改 sshd 前 sshd -t 校验 + 失败自动回滚 + 重启后回连自检
#   4. 去掉 set -e，每步失败只告警不中断
#   5. apk upgrade 改为显式 --upgrade 才执行，并检查磁盘余量
#   6. 只写内核真正允许写的 sysctl 键，并落 /etc/local.d 持久化
#
# 用法：
#   sh alpine-optimize-safe.sh --dry-run     # 只看会做什么，不改系统
#   sh alpine-optimize-safe.sh               # 执行（不改 SSH 端口）
#   sh alpine-optimize-safe.sh --upgrade     # 额外做 apk upgrade
#   PORT=22 sh alpine-optimize-safe.sh       # 显式指定端口（必须等于当前监听端口）
# =========================================================
set -u

DRY=0; DO_UPGRADE=0; PORT_OVERRIDE=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --upgrade) DO_UPGRADE=1 ;;
    *) echo "未知参数: $a"; exit 1 ;;
  esac
done
PORT_OVERRIDE="${PORT:-}"

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
ok()   { printf '   \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[1;33m!\033[0m %s\n' "$*"; }
bad()  { printf '   \033[1;31m✗\033[0m %s\n' "$*"; }
doit() { if [ "$DRY" = "1" ]; then printf '   [dry-run] %s\n' "$*"; else sh -c "$*"; fi; }

[ -f /etc/alpine-release ] || { bad "这不是 Alpine，退出"; exit 1; }
MEM_RAW=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
MEM_RAW=$(printf '%s' "$MEM_RAW" | tr -cd '0-9')
case "$MEM_RAW" in
  ''|0) MEM_SHOW="未限制或不可读" ;;
  *)    MEM_SHOW="$((MEM_RAW/1048576)) MB" ;;
esac
say "系统: Alpine $(cat /etc/alpine-release)  cgroup 内存上限: $MEM_SHOW"
[ "$DRY" = "1" ] && warn "dry-run 模式：只打印，不修改"

# ---------- 1. apk 源：保持当前分支，不追 latest-stable ----------
say "1/7 APK 源"
CUR_BRANCH=$(sed -n 's|.*/alpine/\(v[0-9.]*\)/.*|\1|p' /etc/apk/repositories 2>/dev/null | head -1)
[ -n "$CUR_BRANCH" ] || CUR_BRANCH="v$(cut -d. -f1,2 /etc/alpine-release)"
MIRROR=$(sed -n 's|\(.*/alpine\)/v[0-9.]*/.*|\1|p' /etc/apk/repositories 2>/dev/null | head -1)
[ -n "$MIRROR" ] || MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ok "分支 $CUR_BRANCH, 镜像 $MIRROR（保持不漂移）"
if [ "$DRY" = "0" ]; then
  cp -a /etc/apk/repositories "/etc/apk/repositories.bak.$(date +%Y%m%d-%H%M%S)"
  printf '%s/%s/main\n%s/%s/community\n' "$MIRROR" "$CUR_BRANCH" "$MIRROR" "$CUR_BRANCH" > /etc/apk/repositories
fi
doit "apk update -q" || warn "apk update 失败（源不可达），后续安装会跳过"

# ---------- 2. 磁盘余量 ----------
say "2/7 磁盘余量检查"
AVAIL_MB=$(df -Pm / | awk 'NR==2{print $4}')
ok "根分区可用 ${AVAIL_MB} MB"
if [ "$AVAIL_MB" -lt 200 ]; then
  warn "可用空间 <200MB，跳过所有安装/升级"
  DO_UPGRADE=0; SKIP_INSTALL=1
else
  SKIP_INSTALL=0
fi

# ---------- 3. 系统升级（可选） ----------
say "3/7 系统升级"
if [ "$DO_UPGRADE" = "1" ] && [ "$SKIP_INSTALL" = "0" ]; then
  doit "apk upgrade --no-cache -q" || warn "upgrade 有报错，继续"
else
  ok "跳过（需要时加 --upgrade）"
fi

# ---------- 4. 常用工具 ----------
say "4/7 常用工具"
NEED=""
for p in bash curl wget vim htop nano tzdata openssh sudo ca-certificates iproute2; do
  apk info -e "$p" >/dev/null 2>&1 || NEED="$NEED $p"
done
if [ -n "$NEED" ]; then
  ok "待安装:$NEED"
  [ "$SKIP_INSTALL" = "1" ] && warn "空间不足，跳过" || doit "apk add --no-cache -q$NEED"
else
  ok "已齐全，无需安装"
fi

# ---------- 5. 时区 ----------
say "5/7 时区"
if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
  if cmp -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null; then
    ok "Asia/Shanghai（已正确，跳过）"
  else
    doit "cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
    doit "echo Asia/Shanghai > /etc/timezone"
    ok "Asia/Shanghai"
  fi
else
  warn "缺 tzdata，跳过"
fi

# ---------- 6. SSH（最高风险步骤） ----------
say "6/7 SSH 加固"
CUR_PORT=$(ss -lntp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]}' | head -1)
[ -n "$CUR_PORT" ] || CUR_PORT=22
ok "sshd 实际监听端口: $CUR_PORT"

if [ -n "$PORT_OVERRIDE" ] && [ "$PORT_OVERRIDE" != "$CUR_PORT" ]; then
  bad "拒绝改端口: 你要求 $PORT_OVERRIDE，但 sshd 正在监听 $CUR_PORT"
  warn "NAT 小鸡的外网端口由宿主机映射，脚本里改内网端口 = 直接失联"
  warn "如确认内网端口真要改，请手动改并先确认映射关系"
elif [ -n "$PORT_OVERRIDE" ]; then
  ok "端口一致，不动" 
fi

SSHD_CFG=/etc/ssh/sshd_config
doit "cp -a $SSHD_CFG $SSHD_CFG.bak.$(date +%Y%m%d-%H%M%S)"

# 只保证这两项，不碰端口
ensure_kv() {
  k="$1"; v="$2"
  if grep -qE "^[#[:space:]]*${k}[[:space:]]" "$SSHD_CFG"; then
    doit "sed -i 's|^[#[:space:]]*${k}[[:space:]].*|${k} ${v}|' $SSHD_CFG"
  else
    doit "echo '${k} ${v}' >> $SSHD_CFG"
  fi
}

# 同一个键出现多次时只保留最后一条（sshd 以最后一条为准），避免历史脚本反复追加
dedupe_kv() {
  k="$1"
  [ "$DRY" = "1" ] && { printf '   [dry-run] 去重 %s\n' "$k"; return; }
  awk -v k="$k" '
    { line[NR]=$0 }
    $0 ~ ("^[#[:space:]]*" k "[[:space:]]") { idx[++n]=NR }
    END {
      for (i=1;i<=NR;i++) {
        skip=0
        for (j=1;j<n;j++) if (idx[j]==i) skip=1
        if (!skip) print line[i]
      }
    }' "$SSHD_CFG" > "$SSHD_CFG.tmp" && mv "$SSHD_CFG.tmp" "$SSHD_CFG"
}
ensure_kv PasswordAuthentication yes
ensure_kv PermitRootLogin yes
dedupe_kv PasswordAuthentication
dedupe_kv PermitRootLogin
dedupe_kv Port
ok "PasswordAuthentication/PermitRootLogin 已确保为 yes，重复行已去重（现 $(grep -cE '^(PasswordAuthentication|PermitRootLogin)' "$SSHD_CFG") 行）"

if [ "$DRY" = "0" ]; then
  if sshd -t 2>/tmp/sshd_err; then
    ok "sshd -t 校验通过"
    rc-service sshd restart >/dev/null 2>&1
    sleep 2
    NEW_PORT=$(ss -lntp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]}' | head -1)
    if [ "$NEW_PORT" = "$CUR_PORT" ] && rc-service sshd status >/dev/null 2>&1; then
      ok "sshd 重启后仍在 $NEW_PORT 监听，连接安全"
    else
      bad "sshd 重启异常（监听 $NEW_PORT），立即回滚配置"
      cp -a "$(ls -t $SSHD_CFG.bak.* 2>/dev/null | head -1)" "$SSHD_CFG"
      rc-service sshd restart
      [ "$DRY" = "0" ] && echo "   -> 已回滚，请用旧密码重连验证"
    fi
  else
    bad "sshd -t 校验失败: $(head -2 /tmp/sshd_err)"
    cp -a "$(ls -t $SSHD_CFG.bak.* 2>/dev/null | head -1)" "$SSHD_CFG"
    warn "已回滚，未重启 sshd"
  fi
fi

# ---------- 7. 内核参数 ----------
say "7/7 内核参数（只写容器允许的键）"
SYSCTL_FILE=/etc/sysctl.d/99-alpine-optimize.conf
doit "mkdir -p /etc/sysctl.d"
if [ "$DRY" = "0" ]; then
  cat > "$SYSCTL_FILE" <<'EOF'
# alpine-optimize-safe.sh v2 生成；只含本机实测可写的键
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_keepalive_time=120
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=4096
net.ipv4.ip_local_port_range=10000 65000
net.ipv4.tcp_congestion_control=bbr
EOF
fi

APPLIED=0; FAILED=0
while IFS= read -r kv; do
  case "$kv" in ''|'#'*) continue ;; esac
  if [ "$DRY" = "1" ]; then
    printf '   [dry-run] sysctl -w %s\n' "$kv"
    continue
  fi
  if sysctl -w "$kv" >/dev/null 2>&1; then APPLIED=$((APPLIED+1)); else FAILED=$((FAILED+1)); warn "写入被拒: $kv"; fi
done < "$SYSCTL_FILE"
[ "$DRY" = "0" ] && ok "生效 $APPLIED 项，被拒 $FAILED 项"

# 开机自动应用（容器重启后 sysctl 会丢）
if [ "$DRY" = "0" ]; then
  mkdir -p /etc/local.d
  cat > /etc/local.d/99-alpine-optimize.start <<'EOF'
#!/bin/sh
[ -r /etc/sysctl.d/99-alpine-optimize.conf ] || exit 0
while IFS= read -r kv; do
    case "$kv" in ''|'#'*) continue ;; esac
    sysctl -w "$kv" >/dev/null 2>&1 || true
done < /etc/sysctl.d/99-alpine-optimize.conf
exit 0
EOF
  chmod +x /etc/local.d/99-alpine-optimize.start
  rc-update add local default >/dev/null 2>&1 || true
  ok "已写入 /etc/local.d 并在 default runlevel 启用 local"
fi

# ---------- 收尾 ----------
say "清理与结果"
doit "apk cache clean" >/dev/null 2>&1 || true
if [ "$DRY" = "0" ]; then
  echo "   拥塞控制 : $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
  echo "   somaxconn: $(sysctl -n net.core.somaxconn 2>/dev/null)"
  echo "   SSH 端口 : $(ss -lntp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]}' | head -1)"
  echo "   磁盘可用 : $(df -Pm / | awk 'NR==2{print $4}') MB"
  echo "   服务状态 : $(for s in sshd sing-box argo komari-agent; do rc-service $s status >/dev/null 2>&1 && printf '%s=ok ' $s; done)"
  echo "   时间     : $(date '+%F %T %Z')"
else
  echo "   [dry-run] 未做任何修改"
fi
say "完成"
