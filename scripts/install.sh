#!/bin/sh
# onekey-install.sh — kenzok8 五个 OpenWrt 插件的一键安装 / 卸载 / 升级入口
# 插件（字母序）：clashoo、daede、honk、tower、usque
# SPDX-License-Identifier: GPL-3.0-only
#
# 用法：
#   ash install.sh                        # 交互菜单
#   ash install.sh install all            # 一键安装全部五个
#   ash install.sh install clashoo daede  # 安装指定插件（可多选）
#   ash install.sh uninstall all [--purge]# 卸载（默认保留配置，--purge 才清）
#   ash install.sh update all|插件名...   # 升级
#   ash install.sh list                   # 查看安装状态
#
# 环境变量：
#   GH_PROXY：GitHub 镜像前缀，默认 https://ghfast.top/；设为空字符串则只直连。
#   SKIP_BTF=1 跳过 BTF 检查与补装。
#   ONEKEY_PURGE_USQUE_ACCOUNT=1 允许非交互下删除 usque 账号文件（默认需二次确认）。
#
# 兼容：POSIX sh（busybox ash），不用 jq / bash 特性。需要 root。

set -u

# ---------------- 常量 ----------------
FEED_BASE="https://down.dllkids.xyz/openwrt-feed"
KEY_BASE="$FEED_BASE/keys"
DAED_MANIFEST_BASE="$FEED_BASE/daed"
HONK_SUBFEED_BASE="$FEED_BASE/honk"

# 源签名公钥（指纹为内置信任锚点，下载后逐字节比对 SHA-256）
APK_KEY_NAME="dllkids-feed.pub.pem"
APK_KEY_SHA256="ea9dd08b41e6b0fc7ffda166a89b2b4904ad5607bf77d82c9f7f2a54e63a8948"
OPKG_KEY_NAME="dllkids-feed.pub"
OPKG_KEY_SHA256="216565b4d2c50f90da39ee1b19f1c6d2de0392c0043ca9bea311ac831a44779e"
OPKG_KEY_ID="f2a0779946829e7a"

BTF_RELEASE="https://github.com/kenzok8/vmlinux-btf/releases/download/latest"
BTF_API="https://api.github.com/repos/kenzok8/vmlinux-btf/releases/tags/latest"
USQUE_API="https://api.github.com/repos/kenzok8/openwrt-usque/releases/latest"
DAEDE_API="https://api.github.com/repos/kenzok8/openwrt-daede/releases/latest"

PLUGINS="clashoo daede honk tower usque"
GH_PROXY="${GH_PROXY:-https://ghfast.top/}"

# 全局状态（detect_env / setup_feed 填充）
PM=""; SDK=""; ARCH=""; FEED_ARCH=""; FEED_URL=""; FEEDS_FILE=""; EXT=""
KERNEL_VER=""; TMP_DIR=""; FEED_READY=0; BTF_MISSING=0; PURGE=0; SELECTED=""

# ---------------- 输出 ----------------
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
ok()   { printf '[OK] %s\n' "$*"; }
die()  { err "$*"; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# 从 /dev/tty 读一行（管道执行时 stdin 是脚本本身，必须走 tty）；
# 无 tty 时回落 stdin。read_line <变量名>
read_line() {
  if [ -r /dev/tty ]; then
    IFS= read -r "$1" < /dev/tty
  else
    IFS= read -r "$1"
  fi
}

# confirm <提示>：只在显式输入 y/yes 时返回 0；无 tty 时返回 1（默认否）。
# 用 /dev/tty 判断而不是 stdin 是否 tty：管道执行（curl | ash）时 stdin 是脚本本身，
# 但用户仍在终端前，确认提示必须能走到终端。
confirm() {
  [ -r /dev/tty ] || return 1
  printf '%s [y/N] ' "$1"
  _ans=""
  read_line _ans || return 1
  case "$_ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# ---------------- 下载与校验 ----------------
_dl_once() {
  _u="$1"; _o="$2"
  if have_cmd wget; then wget -q -O "$_o" "$_u" 2>/dev/null && return 0; fi
  if have_cmd uclient-fetch; then uclient-fetch -q -O "$_o" "$_u" 2>/dev/null && return 0; fi
  if have_cmd curl; then curl -fsSL -o "$_o" "$_u" 2>/dev/null && return 0; fi
  return 1
}

# download_file <url> <out>：GitHub 域名先走镜像，失败回落直连
download_file() {
  _url="$1"; _out="$2"
  case "$_url" in
    https://github.com/*|https://api.github.com/*|https://raw.githubusercontent.com/*)
      if [ -n "$GH_PROXY" ]; then
        if _dl_once "${GH_PROXY}${_url}" "$_out"; then return 0; fi
        warn "镜像下载失败，回落直连：$_url"
      fi
      ;;
  esac
  if _dl_once "$_url" "$_out"; then return 0; fi
  rm -f "$_out"
  return 1
}

_fetch_once() {
  _u="$1"
  if have_cmd wget; then wget -qO- "$_u" 2>/dev/null && return 0; fi
  if have_cmd uclient-fetch; then uclient-fetch -q -O - "$_u" 2>/dev/null && return 0; fi
  if have_cmd curl; then curl -fsSL "$_u" 2>/dev/null && return 0; fi
  return 1
}

# fetch_text <url>：下载到标准输出（同样走镜像优先逻辑）
fetch_text() {
  _url="$1"
  case "$_url" in
    https://github.com/*|https://api.github.com/*|https://raw.githubusercontent.com/*)
      if [ -n "$GH_PROXY" ]; then
        if _fetch_once "${GH_PROXY}${_url}"; then return 0; fi
      fi
      ;;
  esac
  _fetch_once "$_url"
}

# url_exists <url>：真实 GET 到 /dev/null（有些 CDN 对 HEAD 返回 302，容易误判）
url_exists() {
  _url="$1"
  case "$_url" in
    https://github.com/*|https://api.github.com/*|https://raw.githubusercontent.com/*)
      if [ -n "$GH_PROXY" ]; then
        if _dl_once "${GH_PROXY}${_url}" /dev/null; then return 0; fi
      fi
      ;;
  esac
  _dl_once "$_url" /dev/null
}

sha256_of() {
  if have_cmd sha256sum; then sha256sum "$1" 2>/dev/null | awk '{print $1}'; return 0; fi
  if have_cmd openssl; then openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'; return 0; fi
  return 1
}

# verify_sha256 <文件> <期望值>：0=一致，1=不一致，2=没有校验工具
verify_sha256() {
  _f="$1"; _want="$2"
  _have="$(sha256_of "$_f" || true)"
  if [ -z "$_have" ]; then return 2; fi
  [ "$_have" = "$_want" ]
}

# check_tmp_space <字节数>：/tmp 可用空间不足时直接退出并报数字
check_tmp_space() {
  _need="$1"
  case "$_need" in ''|*[!0-9]*) return 0;; esac
  [ "$_need" -gt 0 ] || return 0
  _avail="$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
  case "$_avail" in ''|*[!0-9]*) return 0;; esac
  if [ $((_avail * 1024)) -lt "$_need" ]; then
    die "/tmp 空间不足：需要约 $((_need / 1024 / 1024)) MiB，可用约 $((_avail / 1024)) MiB，请清理后再试"
  fi
}

# remote_size <url>：用 curl 取 Content-Length；取不到返回空（不报错）
remote_size() {
  have_cmd curl || return 1
  _u="$1"
  case "$_u" in
    https://github.com/*|https://api.github.com/*)
      [ -n "$GH_PROXY" ] && _u="${GH_PROXY}${_u}"
      ;;
  esac
  curl -fsSL -I "$_u" 2>/dev/null | grep -i '^content-length:' | tail -n 1 | awk '{print $2}' | tr -d '\r'
}

# download_checked <url> <out>：有 curl 时先按 Content-Length 核对 /tmp 空间，再下载并确认非空
download_checked() {
  _u="$1"; _o="$2"
  _len="$(remote_size "$_u" || true)"
  case "$_len" in ''|*[!0-9]*) ;; *) check_tmp_space "$_len";; esac
  download_file "$_u" "$_o" || return 1
  [ -s "$_o" ] || { err "下载结果为空：$_u"; return 1; }
  return 0
}

# kernel_ge <主> <次> <补丁>：数值比较内核版本（字符串比较会错，如 6.9 < 6.12）
kernel_ge() {
  _v="$KERNEL_VER"
  _maj="${_v%%.*}"
  case "$_v" in *.*) _r="${_v#*.}";; *) _r="";; esac
  _min="${_r%%.*}"
  case "$_r" in *.*) _p="${_r#*.}";; *) _p="";; esac
  _p="${_p%%[!0-9]*}"
  _maj="${_maj:-0}"; _min="${_min:-0}"; _p="${_p:-0}"
  [ "$_maj" -gt "$1" ] && return 0
  [ "$_maj" -lt "$1" ] && return 1
  [ "$_min" -gt "$2" ] && return 0
  [ "$_min" -lt "$2" ] && return 1
  [ "$_p" -ge "$3" ]
}

# ---------------- 环境检测 ----------------
detect_env() {
  [ "$(id -u)" = "0" ] || die "请用 root 运行（当前用户不是 root）"

  if have_cmd apk; then PM="apk"; EXT="apk"
  elif have_cmd opkg; then PM="opkg"; EXT="ipk"
  else die "未找到包管理器（apk/opkg），无法安装"; fi

  # SDK：优先读 DISTRIB_RELEASE；自定义固件版本号与上游脱钩时按包管理器推断
  SDK=""
  if [ -r /etc/openwrt_release ]; then
    SDK="$(sed -n "s/^DISTRIB_RELEASE=['\"]\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1)"
  fi
  case "$SDK" in
    24.10|25.12) ;;
    *)
      if [ "$PM" = apk ]; then SDK="25.12"; else SDK="24.10"; fi
      warn "DISTRIB_RELEASE 无法识别，按包管理器推断 SDK=$SDK，请核对是否正确"
      ;;
  esac

  # 架构：opkg 取优先级最高的非 all 架构；apk 优先读 DISTRIB_ARCH
  # （apk --print-arch 只回 CPU 家族，会丢 subtarget 后缀）
  if [ "$PM" = opkg ]; then
    ARCH="$(opkg print-architecture 2>/dev/null | awk '$1=="arch" && $2!="all" && $2!="noarch" { if ($3+0>best) { best=$3+0; arch=$2 } } END { print arch }')"
  else
    ARCH="$(sed -n "s/^DISTRIB_ARCH=['\"]\([^'\"]*\)['\"].*/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1)"
    [ -n "$ARCH" ] || ARCH="$(apk --print-arch 2>/dev/null)"
  fi
  [ -n "$ARCH" ] || die "无法确定设备架构"
  FEED_ARCH="$ARCH"

  KERNEL_VER="$(uname -r)"
  KERNEL_VER="${KERNEL_VER%%-*}"
  [ -n "$KERNEL_VER" ] || die "无法读取内核版本（uname -r 为空）"

  # 下载工具：三者都没有时尝试用包管理器装 curl
  if ! have_cmd wget && ! have_cmd uclient-fetch && ! have_cmd curl; then
    warn "没有 wget/uclient-fetch/curl，尝试安装 curl"
    if [ "$PM" = apk ]; then
      apk add curl 2>/dev/null || die "没有可用的下载工具，且 curl 安装失败"
    else
      opkg update >/dev/null 2>&1
      opkg install curl 2>/dev/null || die "没有可用的下载工具，且 curl 安装失败"
    fi
  fi

  # 网络可达性不在这里测：list / uninstall 不需要联网；
  # install / update 由 run_action 调 check_network 测一次（带 guard 不重复测）。

  info "环境：包管理器 $PM / SDK $SDK / 架构 $ARCH / 内核 $KERNEL_VER"
}

# ---------------- 网络检查（install/update 前测一次） ----------------
NET_CHECKED=0
check_network() {
  [ "$NET_CHECKED" = 1 ] && return 0
  NET_CHECKED=1
  # 源与 GitHub 同时不可达时直接失败，不要进入半截安装
  _feed_ok=0; _gh_ok=0
  url_exists "$FEED_BASE/" && _feed_ok=1
  url_exists "https://api.github.com" && _gh_ok=1
  if [ "$_feed_ok" = 0 ] && [ "$_gh_ok" = 0 ]; then
    die "聚合源与 GitHub 均不可达，请检查网络后再试"
  fi
  [ "$_feed_ok" = 0 ] && warn "聚合源不可达，走源安装的插件会失败（usque 不受影响）"
  [ "$_gh_ok" = 0 ] && warn "GitHub 不可达，usque 与 daede 的 GitHub 回退路径不可用"
}

# ---------------- 源与公钥 ----------------
# ensure_feed_key：保证聚合源的签名公钥已安装且指纹与内置信任锚点一致。
# 缺 key 或指纹不符时明确处理（下载校验后安装 / 替换），绝不静默跳过；
# 校验失败或无校验工具时直接退出，拒绝信任来历不明的 key。
ensure_feed_key() {
  if [ "$PM" = apk ]; then
    _kpath="/etc/apk/keys/$APK_KEY_NAME"
    if [ -f "$_kpath" ]; then
      verify_sha256 "$_kpath" "$APK_KEY_SHA256"; _vr=$?
      if [ "$_vr" = 0 ]; then info "聚合源公钥已安装且指纹一致"; return 0; fi
      [ "$_vr" = 2 ] && die "没有 sha256sum/openssl，无法校验已安装的源公钥指纹；请先装 coreutils-sha256sum 或 openssl 再试"
      warn "已安装的源公钥指纹与内置信任锚点不符，将替换为官方公钥"
    else
      info "聚合源公钥未安装，正在下载"
    fi
    _kf="$TMP_DIR/$APK_KEY_NAME"
    download_file "$KEY_BASE/$APK_KEY_NAME" "$_kf" || die "源公钥下载失败：$KEY_BASE/$APK_KEY_NAME"
    verify_sha256 "$_kf" "$APK_KEY_SHA256"; _vr=$?
    [ "$_vr" = 0 ] || die "下载的源公钥指纹与内置信任锚点不符，拒绝安装（可能遭到篡改，或源端已更换密钥）"
    mkdir -p /etc/apk/keys || die "无法创建 /etc/apk/keys"
    cp "$_kf" "$_kpath" || die "无法写入 $_kpath"
    chmod 644 "$_kpath"
    verify_sha256 "$_kpath" "$APK_KEY_SHA256" || die "公钥写入后复验失败：$_kpath"
    ok "聚合源公钥已安装（apk）"
  else
    _kpath="/etc/opkg/keys/$OPKG_KEY_ID"
    if [ -f "$_kpath" ]; then
      verify_sha256 "$_kpath" "$OPKG_KEY_SHA256"; _vr=$?
      if [ "$_vr" = 0 ]; then info "聚合源公钥已安装且指纹一致"; return 0; fi
      [ "$_vr" = 2 ] && die "没有 sha256sum/openssl，无法校验已安装的源公钥指纹；请先装 coreutils-sha256sum 或 openssl 再试"
      warn "已安装的源公钥指纹与内置信任锚点不符，将替换为官方公钥"
      rm -f "$_kpath"
    else
      info "聚合源公钥未安装，正在下载"
    fi
    _kf="$TMP_DIR/$OPKG_KEY_NAME"
    download_file "$KEY_BASE/$OPKG_KEY_NAME" "$_kf" || die "源公钥下载失败：$KEY_BASE/$OPKG_KEY_NAME"
    verify_sha256 "$_kf" "$OPKG_KEY_SHA256"; _vr=$?
    [ "$_vr" = 0 ] || die "下载的源公钥指纹与内置信任锚点不符，拒绝安装（可能遭到篡改，或源端已更换密钥）"
    opkg-key add "$_kf" >/dev/null 2>&1 || die "opkg-key add 失败"
    [ -f "$_kpath" ] || die "opkg-key add 后未找到 $_kpath（keyid 与预期不符？）"
    verify_sha256 "$_kpath" "$OPKG_KEY_SHA256" || die "公钥安装后复验失败：$_kpath"
    ok "聚合源公钥已安装（opkg）"
  fi
}

# refresh_feed：先保证 key 在位，再刷新索引。apk update 失败时警告后
# --allow-untrusted 重试一次（该回退有 daede/clashoo README 为据）；
# 仍失败只警告不退出——可能是其他源的问题，后续安装会给出明确报错。
refresh_feed() {
  ensure_feed_key
  if [ "$PM" = apk ]; then
    if apk update; then return 0; fi
    warn "apk update 失败，重试一次（--allow-untrusted）"
    apk update --allow-untrusted
  else
    opkg update
  fi
}

# setup_feed：配好聚合源（幂等，FEED_READY guard）。流程：装 key → 按索引存在性
# 选 feed 架构（设备架构 → aarch64_generic → all）→ 写源配置 → 刷新索引。
setup_feed() {
  [ "$FEED_READY" = 1 ] && return 0
  ensure_feed_key
  FEED_ARCH=""; FEED_URL=""
  for _cand in "$ARCH" aarch64_generic all; do
    case "$_cand" in
      aarch64_generic) case "$ARCH" in aarch64*) ;; *) continue ;; esac ;;
    esac
    if [ "$PM" = apk ]; then _idx="$FEED_BASE/$SDK/$_cand/packages.adb";
    else _idx="$FEED_BASE/$SDK/$_cand/Packages.gz"; fi
    if url_exists "$_idx"; then FEED_ARCH="$_cand"; FEED_URL="$FEED_BASE/$SDK/$_cand"; break; fi
  done
  [ -n "$FEED_ARCH" ] || die "聚合源里没有可用的架构索引（已试 $ARCH / aarch64_generic / all，SDK $SDK）"
  [ "$FEED_ARCH" != "$ARCH" ] && warn "聚合源无 $ARCH 索引，改用 $FEED_ARCH"
  # apk 回退架构需写入 /etc/apk/arch，否则装包会被拒
  if [ "$PM" = apk ] && [ "$FEED_ARCH" != "$ARCH" ]; then
    printf '%s\n' "$FEED_ARCH" > /etc/apk/arch 2>/dev/null || warn "无法写入 /etc/apk/arch，回退架构的包可能装不上"
  fi
  if [ "$PM" = apk ]; then
    FEEDS_FILE="/etc/apk/repositories.d/customfeeds.list"
    mkdir -p /etc/apk/repositories.d || die "无法创建 /etc/apk/repositories.d"
    # apk 行是 <feed-url>/packages.adb（apk-tools v3 要求直接指向索引文件）。
    # 过滤会连 honk 子源行一起删掉，先把 honk 行捞出来，写完再补回去。
    _honk_line=""
    [ -f "$FEEDS_FILE" ] && _honk_line="$(grep '/honk/' "$FEEDS_FILE" 2>/dev/null || true)"
    _tmpf="$FEEDS_FILE.tmp"
    : > "$_tmpf" || die "无法写入 $FEEDS_FILE"
    [ -f "$FEEDS_FILE" ] && grep -v 'down\.dllkids\.xyz/openwrt-feed/' "$FEEDS_FILE" >> "$_tmpf" 2>/dev/null || true
    printf '%s\n' "$FEED_URL/packages.adb" >> "$_tmpf"
    [ -n "$_honk_line" ] && printf '%s\n' "$_honk_line" >> "$_tmpf"
    mv "$_tmpf" "$FEEDS_FILE" || die "无法写入 $FEEDS_FILE"
  else
    FEEDS_FILE="/etc/opkg/customfeeds.conf"
    # 只删聚合源行（dllkids_feed），honk 子源行（dllkids_honk）原样保留。
    _tmpf="$FEEDS_FILE.tmp"
    : > "$_tmpf" || die "无法写入 $FEEDS_FILE"
    [ -f "$FEEDS_FILE" ] && grep -v 'dllkids_feed' "$FEEDS_FILE" >> "$_tmpf" 2>/dev/null || true
    printf 'src/gz dllkids_feed %s\n' "$FEED_URL" >> "$_tmpf"
    mv "$_tmpf" "$FEEDS_FILE" || die "无法写入 $FEEDS_FILE"
  fi
  refresh_feed || warn "软件源索引刷新失败，后续安装可能失败"
  FEED_READY=1
  ok "聚合源已配置：$FEED_URL"
}

# ensure_honk_subfeed（仅 opkg）：24.10 的 honk linux66 ipk 在 honk 子源里，
# 聚合源不一定有。检查子源索引存在后追加 dllkids_honk 行并刷新。
# 必须在 setup_feed 之后调用。返回 1 时调用方仍可尝试从聚合源安装。
ensure_honk_subfeed() {
  [ "$PM" = opkg ] || return 0
  _hurl="$HONK_SUBFEED_BASE/$SDK/$FEED_ARCH"
  url_exists "$_hurl/Packages.gz" || { warn "honk 子源索引不存在：$_hurl"; return 1; }
  if [ -f "$FEEDS_FILE" ] && grep -q 'dllkids_honk' "$FEEDS_FILE" 2>/dev/null; then
    info "honk 子源已配置"
    return 0
  fi
  printf 'src/gz dllkids_honk %s\n' "$_hurl" >> "$FEEDS_FILE" || { warn "无法写入 honk 子源配置"; return 1; }
  opkg update >/dev/null 2>&1 || warn "opkg update 失败（honk 子源可能未生效）"
  ok "honk 子源已配置：$_hurl"
  return 0
}

# ---------------- 包操作与服务 ----------------
_STAGED=""

# pkg_installed <包名>：不用 apk info -e（版本差异会误判），按名字前缀匹配。
# 注意 dae 与 daed：模式 "^dae-" 不会命中 "daed-..."，因为 daed 在 dae 后是 d 不是 -。
pkg_installed() {
  if [ "$PM" = apk ]; then apk info 2>/dev/null | grep -q "^$1-";
  else opkg list-installed 2>/dev/null | grep -q "^$1 - "; fi
}

pkg_version() {
  if [ "$PM" = apk ]; then apk info 2>/dev/null | sed -n "s/^$1-//p" | head -n 1;
  else opkg list-installed 2>/dev/null | sed -n "s/^$1 - //p" | head -n 1; fi
}

pkg_install() {
  if [ "$PM" = apk ]; then apk add "$@"; else opkg install "$@"; fi
}

# pkg_remove：逐个删，未安装的跳过，单个失败（例如被其他包依赖）不中断其余。
pkg_remove() {
  _rc=0
  for _p in "$@"; do
    pkg_installed "$_p" || continue
    if [ "$PM" = apk ]; then apk del "$_p" || _rc=1;
    else opkg remove "$_p" || _rc=1; fi
  done
  return $_rc
}

pkg_upgrade() {
  if [ "$PM" = apk ]; then apk upgrade "$@"; else opkg upgrade "$@"; fi
}

# install_local_file：装本地包文件。apk 先走 --force-non-repository（仍验签名），
# 失败再警告后 --allow-untrusted 重试一次（包已做 SHA256 校验，签名检查是冗余）。
install_local_file() {
  if [ "$PM" = apk ]; then
    if apk add --force-non-repository "$1"; then return 0; fi
    warn "apk 校验安装失败，重试一次（--allow-untrusted）：$1"
    apk add --allow-untrusted --force-non-repository "$1"
  else
    opkg install "$1"
  fi
}

# _stage_pkg <包名> <URL> <期望SHA256，可空>：下载并校验，把本地路径追加到 _STAGED。
# hash 为空时跳过校验（调用方负责说明原因）；hash 不一致时拒绝安装。
_stage_pkg() {
  _sp_name="${2##*/}"; _sp_local="$TMP_DIR/$_sp_name"
  download_checked "$2" "$_sp_local" || { warn "$1 下载失败：$2"; return 1; }
  if [ -n "$3" ]; then
    verify_sha256 "$_sp_local" "$3"; _vr=$?
    if [ "$_vr" = 1 ]; then err "$1 的 SHA256 校验失败，拒绝安装"; return 1; fi
    [ "$_vr" = 2 ] && warn "没有校验工具，跳过 $1 的 SHA256 校验"
  fi
  _STAGED="$_STAGED $_sp_local"
  return 0
}

_install_staged() {
  for _f in $_STAGED; do
    install_local_file "$_f" || { err "安装失败：$_f"; return 1; }
  done
  return 0
}

stop_service() {
  [ -x "/etc/init.d/$1" ] || return 0
  "/etc/init.d/$1" stop >/dev/null 2>&1 || warn "$1 停止失败（可忽略，继续）"
  "/etc/init.d/$1" disable >/dev/null 2>&1 || true
}

restart_if_exists() {
  [ -x "/etc/init.d/$1" ] || return 0
  "/etc/init.d/$1" restart >/dev/null 2>&1 || warn "$1 重启失败，请手动重启"
}

# ensure_curl_soft：daede/clashoo 的脚本用 curl 但 Makefile 未声明，显式确认并补装。
ensure_curl_soft() {
  have_cmd curl && return 0
  info "正在补装 curl（订阅更新 / 代理检查需要）"
  pkg_install curl || warn "curl 补装失败，相关功能可能不可用"
}

# _arch_candidates：候选架构（设备架构优先；aarch64 追加 generic 回退）。
_arch_candidates() {
  printf '%s\n' "$ARCH"
  case "$ARCH" in
    aarch64*) [ "$ARCH" != aarch64_generic ] && printf '%s\n' aarch64_generic ;;
  esac
}

# ---------------- BTF 与 Geo 数据（包管理器补不了的两类） ----------------
# kernel_btf_ready：/sys/kernel/btf/vmlinux 是 sysfs 文件，stat 大小恒为 0，
# 不能用 -s 判断，只能用 -r（可读即有 BTF）；debug 路径是普通文件，用 -s。
kernel_btf_ready() {
  [ -r /sys/kernel/btf/vmlinux ] && return 0
  [ -s /usr/lib/debug/boot/vmlinux ] && return 0
  return 1
}

# ensure_btf：内核无内置 BTF 时补装 vmlinux-btf。先试源里装，装后仍不 ready
# 说明是错内核的包，删掉再走 GitHub 精确匹配（同系列 sibling 亦可，跨系列不装）。
# 最终仍无 BTF 时警告并继续（BTF_MISSING=1，汇总时再提醒一次），不硬失败；
# SKIP_BTF=1 跳过整个检查。
ensure_btf() {
  [ "${SKIP_BTF:-0}" = 1 ] && { info "SKIP_BTF=1，跳过 BTF 检查"; return 0; }
  kernel_btf_ready && { info "内核自带 BTF"; return 0; }
  info "内核无内置 BTF，尝试补装 vmlinux-btf"
  setup_feed
  if pkg_install vmlinux-btf 2>/dev/null; then
    if kernel_btf_ready; then ok "vmlinux-btf 已装好"; return 0; fi
    warn "源里的 vmlinux-btf 与当前内核不匹配，删掉后改走 GitHub 精确匹配"
    pkg_remove vmlinux-btf 2>/dev/null || true
  else
    warn "源里没有可用的 vmlinux-btf，改走 GitHub 精确匹配"
  fi
  _sums="$TMP_DIR/SHA256SUMS-btf"
  if ! download_file "$BTF_RELEASE/SHA256SUMS" "$_sums" || [ ! -s "$_sums" ]; then
    warn "vmlinux-btf 的 SHA256SUMS 下载失败，无法精确匹配"
    BTF_MISSING=1; return 0
  fi
  _kfull="$(uname -r)"
  _kmaj="${KERNEL_VER%%.*}"; _krest="${KERNEL_VER#*.}"; _kmin="${_krest%%.*}"
  if [ "$EXT" = apk ]; then _suf="-r1-$ARCH.apk"; _pre="vmlinux-btf-";
  else _suf="-r1_${ARCH}.ipk"; _pre="vmlinux-btf_"; fi
  _best=""; _best_patch=-1
  for _f in $(awk '{f=$2; sub(/^\*/,"",f); print f}' "$_sums" | grep -F -- "$_suf"); do
    _k="${_f#$_pre}"; _k="${_k%$_suf}"
    if [ "$_k" = "$_kfull" ]; then _best="$_f"; break; fi
    _maj="${_k%%.*}"; _r="${_k#*.}"; _mn="${_r%%.*}"; _pt="${_r#*.}"; _pt="${_pt%%[!0-9]*}"
    if [ "$_maj" = "$_kmaj" ] && [ "$_mn" = "$_kmin" ]; then
      case "$_pt" in ''|*[!0-9]*) _pt=0;; esac
      if [ "$_pt" -gt "$_best_patch" ]; then _best_patch="$_pt"; _best="$_f"; fi
    fi
  done
  [ -n "$_best" ] || { warn "vmlinux-btf 没有匹配内核 $KERNEL_VER 的包（同系列也没有），请到 kenzok8/vmlinux-btf 反馈"; BTF_MISSING=1; return 0; }
  case "$_best" in
    *"$_kfull"*) info "vmlinux-btf 精确匹配内核 $_kfull" ;;
    *) warn "vmlinux-btf 无精确匹配，改用同系列包 $_best（补丁位不同，BTF 可能不完全匹配）" ;;
  esac
  _hs="$(awk -v f="$_best" '{h=$1; n=$2; sub(/^\*/,"",n); if (n==f) print h}' "$_sums")"
  _STAGED=""
  _stage_pkg vmlinux-btf "$BTF_RELEASE/$_best" "$_hs" || { warn "vmlinux-btf 下载/校验失败"; BTF_MISSING=1; return 0; }
  _install_staged || { warn "vmlinux-btf 安装失败"; BTF_MISSING=1; return 0; }
  if kernel_btf_ready; then ok "vmlinux-btf 已装好（$_best）"; return 0; fi
  warn "vmlinux-btf 已装但 BTF 仍未就绪（可能是内核不匹配）"
  BTF_MISSING=1; return 0
}

geo_ready() {
  [ -s /usr/share/v2ray/geoip.dat ] && [ -s /usr/share/v2ray/geosite.dat ]
}

# ensure_geodata：daede 的 Geo 数据。先走源里装；失败则从聚合目录列表直接取
# noarch 包（按文件名排序取最新，geoip/geosite 是日期版本号，字典序即版本序）；
# 仍失败警告并继续，不硬失败。
ensure_geodata() {
  geo_ready && { info "Geo 数据已存在"; return 0; }
  info "Geo 数据缺失，尝试补装 v2ray-geoip / v2ray-geosite"
  setup_feed
  if pkg_install v2ray-geoip v2ray-geosite 2>/dev/null && geo_ready; then
    ok "Geo 数据已装好"; return 0
  fi
  _list="$TMP_DIR/feed-listing.html"
  if download_file "$FEED_BASE/$SDK/$FEED_ARCH/" "$_list" 2>/dev/null; then
    _STAGED=""
    _geo_ok=1
    for _g in v2ray-geoip v2ray-geosite; do
      if [ "$EXT" = apk ]; then _gf="$(grep -o "${_g}-[^\"'<>]*\.apk" "$_list" 2>/dev/null | sort | tail -n 1)";
      else _gf="$(grep -o "${_g}_[^\"'<>]*_noarch\.ipk" "$_list" 2>/dev/null | sort | tail -n 1)"; fi
      [ -n "$_gf" ] || { _geo_ok=0; break; }
      _stage_pkg "$_g" "$FEED_BASE/$SDK/$FEED_ARCH/$_gf" "" || { _geo_ok=0; break; }
    done
    if [ "$_geo_ok" = 1 ] && _install_staged && geo_ready; then ok "Geo 数据已装好（直接取包）"; return 0; fi
  fi
  warn "Geo 数据补装失败：daede 的地理规则可能无法工作，可在面板里手动更新 Geo 数据"
  return 0
}

# ---------------- 逐插件安装 ----------------
is_installed() {
  case "$1" in
    clashoo) pkg_installed clashoo ;;
    daede) pkg_installed daed || pkg_installed dae ;;
    honk) pkg_installed honk ;;
    tower) pkg_installed tower ;;
    usque) pkg_installed usque ;;
  esac
}

install_clashoo() {
  setup_feed || return 1
  ensure_curl_soft
  # i18n 是 luci 包的硬依赖，必须显式列出，不能指望自动带上
  pkg_install clashoo luci-app-clashoo luci-i18n-clashoo-zh-cn || { err "clashoo 安装失败"; return 1; }
  [ -x /etc/init.d/clashoo ] || { err "clashoo 装完但 /etc/init.d/clashoo 不存在"; return 1; }
  ok "clashoo 安装完成"
}

# ---- daede 取包三级：manifest → Packages.gz 索引（仅 opkg）→ GitHub ----
# 聚合源里有同名异源的 dae/daed 包，裸按包名装可能选错，所以不用 pkg_install，
# 一律精确取包。每级都是"全部下载校验成功后才安装"，避免半截安装。
_DAEDE_PKGS=""

daede_install_manifest() {
  _man_url="$DAED_MANIFEST_BASE/$SDK/$FEED_ARCH/manifest-daede.txt"
  _man="$TMP_DIR/manifest-daede.txt"
  download_file "$_man_url" "$_man" || { warn "daed manifest 下载失败：$_man_url"; return 1; }
  [ -s "$_man" ] || { warn "daed manifest 为空"; return 1; }
  _STAGED=""
  for _p in $_DAEDE_PKGS; do
    _fn="$(sed -n "s/^${_p}=//p" "$_man" | head -n 1 | tr -d '\r')"
    _hs="$(sed -n "s/^${_p}_sha256=//p" "$_man" | head -n 1 | tr -d '\r')"
    [ -n "$_fn" ] || { warn "manifest 里没有 $_p"; return 1; }
    [ -n "$_hs" ] || warn "manifest 里没有 $_p 的 hash，跳过校验"
    _stage_pkg "$_p" "$DAED_MANIFEST_BASE/$SDK/$FEED_ARCH/$_fn" "$_hs" || return 1
  done
  _install_staged
}

# _parse_index_all <索引文件>：一遍扫描 Packages 索引，为 $_DAEDE_PKGS 里的
# 每个包输出 "包名|文件名|SHA256" 行。
_parse_index_all() {
  _cur=""; _fn=""; _sha=""
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      "")
        if [ -n "$_cur" ] && [ -n "$_fn" ]; then
          case " $_DAEDE_PKGS " in *" $_cur "*) printf '%s|%s|%s\n' "$_cur" "$_fn" "$_sha";; esac
        fi
        _cur=""; _fn=""; _sha="";;
      Package:\ *) _cur="${_line#Package: }" ;;
      Filename:\ *) _fn="${_line#Filename: }" ;;
      SHA256sum:\ *) _sha="${_line#SHA256sum: }" ;;
    esac
  done < "$1"
  if [ -n "$_cur" ] && [ -n "$_fn" ]; then
    case " $_DAEDE_PKGS " in *" $_cur "*) printf '%s|%s|%s\n' "$_cur" "$_fn" "$_sha";; esac
  fi
}

daede_install_index() {
  [ "$PM" = opkg ] || return 1
  _idx_gz="$TMP_DIR/Packages.gz"
  download_file "$FEED_BASE/$SDK/$FEED_ARCH/Packages.gz" "$_idx_gz" || { warn "包索引下载失败"; return 1; }
  _idx="$TMP_DIR/Packages"
  if have_cmd gzip; then gzip -dc "$_idx_gz" > "$_idx" 2>/dev/null || { warn "Packages.gz 解压失败"; return 1; }
  elif have_cmd zcat; then zcat "$_idx_gz" > "$_idx" 2>/dev/null || { warn "Packages.gz 解压失败"; return 1; }
  else warn "没有 gzip/zcat，无法解析包索引"; return 1; fi
  warn "manifest 不可用，退到包索引解析（聚合源里有同名异源的 dae 包，装完请核对版本）"
  _recs="$(_parse_index_all "$_idx")"
  _STAGED=""
  for _p in $_DAEDE_PKGS; do
    _rec="$(printf '%s\n' "$_recs" | grep "^${_p}|" | head -n 1)"
    [ -n "$_rec" ] || { warn "索引里没有 $_p"; return 1; }
    _fn="$(printf '%s' "$_rec" | cut -d'|' -f2)"; _hs="$(printf '%s' "$_rec" | cut -d'|' -f3)"
    _stage_pkg "$_p" "$FEED_BASE/$SDK/$FEED_ARCH/$_fn" "$_hs" || return 1
  done
  _install_staged
}

daede_install_github() {
  _json="$TMP_DIR/daede-release.json"
  fetch_text "$DAEDE_API" > "$_json" 2>/dev/null || { warn "GitHub API 不可达"; return 1; }
  [ -s "$_json" ] || { warn "GitHub API 返回为空"; return 1; }
  _urls="$(grep -o '"browser_download_url": *"[^"]*"' "$_json" | sed 's/.*: *"//; s/"$//')"
  [ -n "$_urls" ] || { warn "GitHub Release 里没有可下载的资产"; return 1; }
  warn "manifest 与包索引都不可用，退到 GitHub Release 直取（无法做 SHA256 校验）"
  _STAGED=""
  for _p in $_DAEDE_PKGS; do
    _u=""
    for _a in $(_arch_candidates); do
      if [ "$EXT" = apk ]; then _u="$(printf '%s\n' "$_urls" | grep -E "/${_p}-[0-9][^/]*-${_a}\.apk$" | head -n 1)";
      elif [ "$_p" = luci-app-daede ]; then _u="$(printf '%s\n' "$_urls" | grep -E "/${_p}_[0-9][^/]*_all\.ipk$" | head -n 1)";
      else _u="$(printf '%s\n' "$_urls" | grep -E "/${_p}_[0-9][^/]*_${_a}\.ipk$" | head -n 1)"; fi
      [ -n "$_u" ] && break
    done
    [ -n "$_u" ] || { warn "GitHub Release 里没有 $_p（架构 $ARCH）"; return 1; }
    _stage_pkg "$_p" "$_u" "" || return 1
  done
  _install_staged
}

install_daede() {
  setup_feed || return 1
  ensure_btf
  ensure_geodata
  _core="${DAEDE_CORE:-both}"
  case "$_core" in
    dae) _DAEDE_PKGS="dae luci-app-daede" ;;
    daed) _DAEDE_PKGS="daed luci-app-daede" ;;
    *) _DAEDE_PKGS="dae daed luci-app-daede"
       [ "$_core" != both ] && warn "DAEDE_CORE=$_core 无效，默认装双核（both）" ;;
  esac
  if daede_install_manifest; then _tier=manifest;
  elif daede_install_index; then _tier=index;
  elif daede_install_github; then _tier=github;
  else err "daede 取包三路都失败（manifest / 包索引 / GitHub）"; return 1; fi
  info "daede 取包走 $_tier 通道"
  ensure_curl_soft
  # 安装后核验以核心二进制存在为准，不只看包管理器退出码
  for _p in $_DAEDE_PKGS; do
    case "$_p" in
      dae) [ -x /usr/bin/dae ] || { err "daede 装完但 /usr/bin/dae 不存在"; return 1; } ;;
      daed) [ -x /usr/bin/daed ] || { err "daede 装完但 /usr/bin/daed 不存在"; return 1; } ;;
    esac
  done
  ok "daede 安装完成"
}

install_honk() {
  # 内核门（硬失败）：apk/25.12 要求 6.12+，opkg/24.10 要求 6.6.40+
  if [ "$PM" = apk ]; then
    kernel_ge 6 12 0 || { err "honk 需要内核 6.12+（当前 $KERNEL_VER），请升级固件"; return 1; }
  else
    kernel_ge 6 6 40 || { err "honk 在 24.10 需要内核 6.6.40+（当前 $KERNEL_VER），请升级固件"; return 1; }
  fi
  case "$ARCH" in
    x86_64|aarch64*|arm*) ;;
    *) err "honk 不支持架构 $ARCH（仅 x86_64 / aarch64 / arm）"; return 1 ;;
  esac
  setup_feed || return 1
  if [ "$PM" = opkg ]; then
    warn "24.10 上安装的是 honk linux66 实验包（内核 6.6 分支），属实验通道"
    ensure_honk_subfeed || warn "honk 子源未加上，尝试从聚合源安装"
  fi
  ensure_btf
  pkg_install honk luci-app-honk || { err "honk 安装失败"; return 1; }
  [ -x /usr/bin/honk-core ] || { err "honk 装完但 /usr/bin/honk-core 不存在"; return 1; }
  ok "honk 安装完成"
}

install_tower() {
  setup_feed || return 1
  pkg_install tower luci-app-tower || { err "tower 安装失败"; return 1; }
  pkg_installed tower || { err "tower 装完但包管理器里没有 tower"; return 1; }
  pkg_installed luci-app-tower || { err "tower 装完但包管理器里没有 luci-app-tower"; return 1; }
  ok "tower 安装完成"
}

# _pick_file <包名> <候选文件名列表> <架构>：输出匹配的文件名。
# apk 两包都带架构后缀；ipk 的 luci 包是 _all，核心包带架构。
_pick_file() {
  if [ "$EXT" = apk ]; then grep -E "^$1-[0-9].*-$3\.apk$" "$2" | head -n 1;
  elif [ "$1" = luci-app-usque ]; then grep -E "^$1_[0-9].*_all\.ipk$" "$2" | head -n 1;
  else grep -E "^$1_[0-9].*_$3\.ipk$" "$2" | head -n 1; fi
}

# usque 不在聚合源里，唯一路径是 GitHub 最新正式 Release（releases/latest
# 自动排除 draft/prerelease）。用 Release 自带的 SHA256SUMS-<SDK> 验 hash。
install_usque() {
  case "$ARCH" in
    mips*|mipsel*) warn "MIPS 架构未经真机验收，安装后请自行验证功能" ;;
  esac
  # usque 不走源，源配不上也不影响安装；子 shell 里跑，setup_feed 的 die 只退出子 shell
  ( setup_feed ) || warn "聚合源配置失败，usque 走 GitHub Release 安装，不受影响"
  _tag="$(fetch_text "$USQUE_API" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed 's/.*: *"//; s/"$//')"
  [ -n "$_tag" ] || { err "无法获取 usque 最新版本号（GitHub API 不可达？）"; return 1; }
  info "usque 最新正式版：$_tag"
  _base="https://github.com/kenzok8/openwrt-usque/releases/download/$_tag"
  _sums="$TMP_DIR/SHA256SUMS-usque"
  _have_sums=0
  if download_file "$_base/SHA256SUMS-$SDK" "$_sums" 2>/dev/null && [ -s "$_sums" ]; then
    _have_sums=1
    _cands="$TMP_DIR/usque-cands.txt"
    awk '{f=$2; sub(/^\*/,"",f); print f}' "$_sums" > "$_cands"
  else
    warn "SHA256SUMS-$SDK 下载失败，改从 Release 资产列表取包名（无法做 SHA256 校验）"
    _json="$TMP_DIR/usque-release.json"
    fetch_text "$USQUE_API" > "$_json" 2>/dev/null || { err "GitHub API 不可达"; return 1; }
    _cands="$TMP_DIR/usque-cands.txt"
    grep -o '"browser_download_url": *"[^"]*"' "$_json" | sed 's/.*\///; s/"$//' > "$_cands"
  fi
  [ -s "$_cands" ] || { err "没有可用的 usque 候选包列表"; return 1; }
  _STAGED=""
  for _p in usque luci-app-usque; do
    _file=""
    for _a in $(_arch_candidates); do
      _file="$(_pick_file "$_p" "$_cands" "$_a")"
      [ -n "$_file" ] && break
    done
    [ -n "$_file" ] || { err "Release 里没有 $_p（架构 $ARCH）"; return 1; }
    _hs=""
    if [ "$_have_sums" = 1 ]; then
      _hs="$(awk -v f="$_file" '{h=$1; n=$2; sub(/^\*/,"",n); if (n==f) print h}' "$_sums")"
      [ -n "$_hs" ] || warn "SHA256SUMS 里没有 $_file 的 hash，跳过校验"
    fi
    _stage_pkg "$_p" "$_base/$_file" "$_hs" || return 1
  done
  _install_staged || return 1
  pkg_installed usque || { err "usque 装完但包管理器里没有 usque"; return 1; }
  pkg_installed luci-app-usque || { err "usque 装完但包管理器里没有 luci-app-usque"; return 1; }
  ok "usque 安装完成（$_tag）"
}

# ---------------- 逐插件卸载 ----------------
# 默认只删包、保留配置；PURGE=1（--purge）才清理配置与状态。
uninstall_clashoo() {
  stop_service clashoo
  rm -f /tmp/clashoo*
  pkg_remove luci-i18n-clashoo-zh-cn luci-app-clashoo clashoo
  if pkg_installed clashoo; then
    err "clashoo 核心删不掉（可能被 nikki 等包依赖），卸载未完成"
    return 1
  fi
  if [ "$PURGE" = 1 ]; then
    # nikki 守卫：只有核心包确实被删掉，才清理配置目录；否则会破坏包管理器状态
    rm -rf /etc/clashoo /usr/share/clashoo /usr/share/clashbackup /etc/init.d/clashoo /etc/config/clashoo
    info "已清理 clashoo 配置与状态"
  fi
  for _s in rpcd uhttpd dnsmasq firewall; do restart_if_exists "$_s"; done
  ok "clashoo 卸载完成"
}

uninstall_daede() {
  stop_service dae; stop_service daed
  # 显式删三包：旧卸载脚本在 apk 下只删 luci 包，会把两个核心留成孤儿
  pkg_remove luci-app-daede dae daed
  if pkg_installed dae || pkg_installed daed; then
    err "daede 核心删不掉，卸载未完成"
    return 1
  fi
  if [ "$PURGE" = 1 ]; then
    rm -rf /etc/dae /etc/daed /etc/config/daede /usr/share/daed
    info "已清理 daede 配置与状态"
  fi
  ok "daede 卸载完成"
}

uninstall_honk() {
  stop_service honk
  pkg_remove honk luci-app-honk
  if pkg_installed honk; then
    err "honk 核心删不掉，卸载未完成"
    return 1
  fi
  if [ "$PURGE" = 1 ]; then
    rm -rf /etc/honk /etc/.honk-preupgrade /etc/honk-pre-reset
    info "已清理 honk 配置与状态"
  fi
  ok "honk 卸载完成"
}

uninstall_tower() {
  stop_service tower
  pkg_remove tower luci-app-tower
  if pkg_installed tower; then
    err "tower 删不掉，卸载未完成"
    return 1
  fi
  if [ "$PURGE" = 1 ]; then
    rm -rf /etc/tower
    info "已清理 tower 配置与状态"
  fi
  ok "tower 卸载完成"
}

uninstall_usque() {
  stop_service usque
  pkg_remove usque luci-app-usque
  if pkg_installed usque; then
    err "usque 删不掉，卸载未完成"
    return 1
  fi
  if [ "$PURGE" = 1 ]; then
    # /etc/usque/config.json 含账号私钥与令牌，删前二次确认；
    # 非交互下必须显式设 ONEKEY_PURGE_USQUE_ACCOUNT=1 才删，否则保留。
    _ok=0
    if [ "${ONEKEY_PURGE_USQUE_ACCOUNT:-0}" = 1 ]; then _ok=1;
    elif confirm "确认删除 usque 账号文件 /etc/usque/config.json（内含账号私钥，删除后需重新注册）？"; then _ok=1; fi
    if [ "$_ok" = 1 ]; then
      rm -rf /etc/usque
      info "已清理 usque 配置与状态（含账号文件）"
    else
      warn "已保留 /etc/usque（账号文件未删除）"
    fi
  fi
  ok "usque 卸载完成"
}

# ---------------- 逐插件升级 ----------------
# 源内插件走源升级；daede/usque（精确取包 / 无源）重跑安装。
update_clashoo() {
  setup_feed || return 1
  refresh_feed
  pkg_upgrade clashoo luci-app-clashoo luci-i18n-clashoo-zh-cn || { err "clashoo 升级失败"; return 1; }
  pkg_installed clashoo || { err "升级后 clashoo 不见了"; return 1; }
  ok "clashoo 升级完成"
}

update_daede() {
  install_daede
}

update_honk() {
  setup_feed || return 1
  refresh_feed
  pkg_upgrade honk luci-app-honk || { err "honk 升级失败"; return 1; }
  [ -x /usr/bin/honk-core ] || { err "升级后 /usr/bin/honk-core 不存在"; return 1; }
  ok "honk 升级完成"
}

update_tower() {
  setup_feed || return 1
  refresh_feed
  pkg_upgrade tower luci-app-tower || { err "tower 升级失败"; return 1; }
  pkg_installed tower || { err "升级后 tower 不见了"; return 1; }
  ok "tower 升级完成"
}

update_usque() {
  install_usque
}

# ---------------- 分发 ----------------
do_install() {
  case "$1" in
    clashoo) install_clashoo ;; daede) install_daede ;; honk) install_honk ;;
    tower) install_tower ;; usque) install_usque ;;
  esac
}

do_uninstall() {
  case "$1" in
    clashoo) uninstall_clashoo ;; daede) uninstall_daede ;; honk) uninstall_honk ;;
    tower) uninstall_tower ;; usque) uninstall_usque ;;
  esac
}

do_update() {
  case "$1" in
    clashoo) update_clashoo ;; daede) update_daede ;; honk) update_honk ;;
    tower) update_tower ;; usque) update_usque ;;
  esac
}

# ---------------- 选择解析与运行器 ----------------
# parse_selection <输入>：把"1 3"、"clashoo,daede"、"a" 这类输入规范为 SELECTED
# （字母序、去重）。空选择与无效输入返回 1。
parse_selection() {
  _in="$1"
  _in="$(printf '%s' "$_in" | tr ',' ' ')"
  _raw=""
  for _t in $_in; do
    case "$_t" in
      a|all) _raw="$PLUGINS"; break ;;
      1) _t=clashoo ;; 2) _t=daede ;; 3) _t=honk ;; 4) _t=tower ;; 5) _t=usque ;;
    esac
    case " $PLUGINS " in *" $_t "*) ;; *) err "无效的选择：$_t（可用：1-5、插件名、a=全部）"; return 1;; esac
    _raw="$_raw $_t"
  done
  [ -n "$_raw" ] || { err "未选择任何插件"; return 1; }
  SELECTED=""
  for _p in $PLUGINS; do
    case " $_raw " in *" $_p "*) SELECTED="$SELECTED $_p";; esac
  done
  SELECTED="${SELECTED# }"
  return 0
}

# run_action <install|uninstall|update> <插件...>：逐个执行，单个失败不中断其余；
# 结束汇总成功 / 失败 / 跳过；退出码非 0 当且仅当有失败项。
run_action() {
  _action="$1"; shift
  case "$_action" in install|update) check_network ;; esac
  _ok=0; _fail=0; _skip=0; _failed=""; _n_proxy=0
  for _p in "$@"; do
    case "$_action" in
      install)
        if is_installed "$_p"; then info "$_p 已安装，跳过"; _skip=$((_skip+1)); continue; fi
        info "正在安装 $_p ..."
        if do_install "$_p"; then
          _ok=$((_ok+1))
          case "$_p" in clashoo|daede|honk) _n_proxy=$((_n_proxy+1));; esac
        else _fail=$((_fail+1)); _failed="$_failed $_p"; fi
        ;;
      uninstall)
        if ! is_installed "$_p"; then info "$_p 未安装，跳过"; _skip=$((_skip+1)); continue; fi
        info "正在卸载 $_p ..."
        if do_uninstall "$_p"; then _ok=$((_ok+1));
        else _fail=$((_fail+1)); _failed="$_failed $_p"; fi
        ;;
      update)
        if ! is_installed "$_p"; then info "$_p 未安装，跳过（先安装再升级）"; _skip=$((_skip+1)); continue; fi
        info "正在升级 $_p ..."
        if do_update "$_p"; then _ok=$((_ok+1));
        else _fail=$((_fail+1)); _failed="$_failed $_p"; fi
        ;;
    esac
  done
  info "汇总：成功 $_ok 个，失败 $_fail 个，跳过 $_skip 个"
  [ -n "$_failed" ] && err "失败的插件：$_failed"
  [ "$_action" = install ] && [ "$_n_proxy" -ge 2 ] && warn "同时安装了 $_n_proxy 个透明代理插件（clashoo/daede/honk），同时启用会抢流量入口，请只启用其中一个"
  [ "$BTF_MISSING" = 1 ] && warn "BTF 未就绪：daede/honk 的核心在 BTF 就绪前无法启动，详见 kenzok8/vmlinux-btf"
  [ "$_fail" -gt 0 ] && return 1
  return 0
}

# ---------------- 菜单与状态 ----------------
pause_return() {
  [ -r /dev/tty ] || return 0
  printf '按回车返回菜单...'
  _x=""; read_line _x || true
}

show_plugin_menu() {
  printf '\n%s\n' "$1"
  printf '  1. clashoo\n  2. daede\n  3. honk\n  4. tower\n  5. usque\n'
  printf '  a. 全部\n  q. 返回\n'
}

# submenu <动作> <标题>：自定义安装 / 卸载 / 更新三个子界面共用。
submenu() {
  show_plugin_menu "$2"
  printf '请选择（可多选，空格或逗号分隔，a=全部，q=返回）：'
  _sel=""
  read_line _sel || return 0
  case "$_sel" in q|Q|"") return 0;; esac
  parse_selection "$_sel" || { pause_return; return 0; }
  # shellcheck disable=SC2086
  run_action "$1" $SELECTED
  pause_return
  return 0
}

plugin_version() {
  case "$1" in
    daede)
      _a="$(pkg_version dae)"; _b="$(pkg_version daed)"
      if [ -n "$_a" ] && [ -n "$_b" ]; then printf 'dae %s / daed %s' "$_a" "$_b";
      elif [ -n "$_a" ]; then printf 'dae %s' "$_a";
      elif [ -n "$_b" ]; then printf 'daed %s' "$_b"; fi ;;
    *) pkg_version "$1" ;;
  esac
}

cmd_list() {
  printf '%-10s %-10s %s\n' "插件" "状态" "版本"
  for _p in $PLUGINS; do
    if is_installed "$_p"; then
      _v="$(plugin_version "$_p")"
      printf '%-10s %-10s %s\n' "$_p" "已安装" "${_v:-未知}"
    else
      printf '%-10s %-10s %s\n' "$_p" "未安装" "-"
    fi
  done
}

menu_main() {
  while true; do
    printf '\n===== kenzok8 插件一键安装 =====\n'
    printf '  1. 安装 clashoo\n  2. 安装 daede\n  3. 安装 honk\n  4. 安装 tower\n  5. 安装 usque\n'
    printf '  6. 自定义安装（多选/全选）\n'
    printf '  7. 卸载（单选/多选/全选）\n'
    printf '  8. 更新升级（单选/多选/全选）\n'
    printf '  9. 查看已安装状态\n'
    printf '  0. 退出\n'
    printf '请选择：'
    _c=""
    read_line _c || { echo; return 0; }
    case "$_c" in
      1) run_action install clashoo; pause_return ;;
      2) run_action install daede; pause_return ;;
      3) run_action install honk; pause_return ;;
      4) run_action install tower; pause_return ;;
      5) run_action install usque; pause_return ;;
      6) submenu install "自定义安装" ;;
      7) submenu uninstall "卸载" ;;
      8) submenu update "更新升级" ;;
      9) cmd_list; pause_return ;;
      0|q|Q) return 0 ;;
      *) warn "无效输入：$_c" ;;
    esac
  done
}

# ---------------- 主入口 ----------------
usage() {
  cat <<'EOF'
用法：
  ash install.sh                        交互菜单
  ash install.sh install all            一键安装全部五个插件
  ash install.sh install clashoo daede  安装指定插件（可多选）
  ash install.sh uninstall all [--purge]卸载（默认保留配置）
  ash install.sh update all|插件名...   升级
  ash install.sh list                   查看安装状态
EOF
}

main() {
  case "${1:-}" in -h|--help) usage; exit 0;; esac
  TMP_DIR="$(mktemp -d /tmp/onekey-install.XXXXXX 2>/dev/null)" || die "无法创建临时目录"
  trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
  _action="${1:-}"
  if [ -z "$_action" ]; then
    detect_env
    menu_main
    exit 0
  fi
  case "$_action" in
    list) detect_env; cmd_list; exit 0 ;;
    install|uninstall|update) ;;
    *) err "未知子命令：$_action"; usage; exit 1 ;;
  esac
  shift
  # 解析 --purge（仅 uninstall 可用）与插件选择
  _args=""
  for _a in "$@"; do
    case "$_a" in
      --purge)
        [ "$_action" = uninstall ] || die "--purge 只能用于 uninstall"
        PURGE=1 ;;
      *) _args="$_args $_a" ;;
    esac
  done
  _args="${_args# }"
  case "$_action" in
    install) _act_zh="安装" ;; uninstall) _act_zh="卸载" ;; update) _act_zh="升级" ;;
  esac
  [ -n "$_args" ] || die "请指定要${_act_zh}的插件（all 或插件名）"
  _sel=""
  for _t in $_args; do
    case "$_t" in
      all) _sel="$PLUGINS"; break ;;
      1) _sel="$_sel clashoo";; 2) _sel="$_sel daede";; 3) _sel="$_sel honk";; 4) _sel="$_sel tower";; 5) _sel="$_sel usque";;
      *) case " $PLUGINS " in *" $_t "*) _sel="$_sel $_t";; *) die "未知的插件：$_t（可用：$PLUGINS / all）";; esac;;
    esac
  done
  # 去重并按字母序规范
  SELECTED=""
  for _p in $PLUGINS; do case " $_sel " in *" $_p "*) SELECTED="$SELECTED $_p";; esac; done
  SELECTED="${SELECTED# }"
  detect_env
  # shellcheck disable=SC2086
  run_action "$_action" $SELECTED
  exit $?
}

main "$@"
