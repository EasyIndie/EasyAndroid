#!/usr/bin/env bash
# 各脚本共用的载入逻辑。不要直接执行,用 `source`。
#
# 作用:
#   1. 探测运行平台(Windows 原生 / WSL2 / Linux),暴露 $PLATFORM / $IS_WINDOWS
#   2. 读 tools/device.env(本地私有,已 gitignore)拿到真实设备地址
#   3. 解析出可用的 adb(见 §6「adb 解析」)
#   4. 补齐跨平台垫片: 临时目录 / 超时 / 文件大小 / python
#
# ── 平台差异与对策 ─────────────────────────────────────────────────
# 本仓库的脚本要在三种环境跑,差异集中在几处,这里统一抹平:
#
# | 差异点        | WSL2 / Linux       | Windows 原生(Git Bash)                |
# |---------------|--------------------|---------------------------------------|
# | adb           | Linux 版 adb       | platform-tools/adb.exe                |
# | 超时命令       | timeout <秒> cmd   | **Windows 自带 timeout.exe 语法不同** |
# |               |                    | (`timeout /T 5`),直接调会报「无效语法」|
# | 临时目录       | /tmp               | /tmp 可能不可写 → 用 $TMP             |
# | python        | python3            | 可能只有 python                       |
# | Windows 侧 adb | 要单独拉一份       | 就是 $ADB 本身                        |
#
# ⚠️ 两个最容易踩的坑:
#
#   1. **timeout**:Git Bash 的 PATH 里 `/c/Windows/system32` 常排在前面,
#      `timeout` 命中的是 Windows 自带那个 —— 它不接受 `timeout 5 cmd` 这种
#      GNU 语法。所以脚本一律不要直接调 `timeout`,用这里导出的 `run_timeout`。
#
#   2. **adb daemon 不跨进程存活**:某些受限环境(沙箱/CI)里每次脚本调用都是
#      新的进程组,上一次 `adb connect` 的记录会丢 —— 表现为「刚连上,下一条
#      命令就 device not found」。对策是每个脚本开头调一次 `adb_connect_all`,
#      幂等且便宜。

# shellcheck disable=SC2034

_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_DIR="$(cd "$_TOOLS_DIR/.." && pwd)"

# ── 1. 平台探测 ─────────────────────────────────────────────────────
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
  Linux)
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then PLATFORM=wsl
    else PLATFORM=linux; fi ;;
  Darwin) PLATFORM=macos ;;
  *)      PLATFORM=unknown ;;
esac

IS_WINDOWS=0
case "$PLATFORM" in windows) IS_WINDOWS=1 ;; esac

# ── 2. 设备地址 ─────────────────────────────────────────────────────
if [ -f "$_TOOLS_DIR/device.env" ]; then
  # shellcheck disable=SC1091
  . "$_TOOLS_DIR/device.env"
fi

# RFC 5737 TEST-NET-1,仅用于文档/示例,不是真实地址
TV_ADDR="${TV_ADDR:-192.0.2.11:5555}"
PICO_ADDR="${PICO_ADDR:-192.0.2.29:5555}"

# 纯 IP(去掉端口)
TV_IP="${TV_ADDR%%:*}"
PICO_IP="${PICO_ADDR%%:*}"

# ── 3. 临时目录 ─────────────────────────────────────────────────────
# 不写死 /tmp:Windows 上 /tmp 可能不可写,而 mktemp 默认模板正是 /tmp,
# 会直接报「failed to create file via template '/tmp/tmp.XXXXXXXXXX'」。
#
# $TMP 一律保持 **POSIX 形式**(脚本内部用),$TMP_WIN 是它的 Windows 形式
# (传给 adb.exe 等原生程序当参数时用)。两者混用是经典坑:
# Git Bash 会把 `C:\Users\...` 当成一个奇怪的相对路径。
_tmp_ok(){ [ -n "${1:-}" ] && mkdir -p "$1" 2>/dev/null && [ -w "$1" ]; }

# ⚠️ 上面两个函数的语义是「**按需**转换」,不是无条件转 ——
#    要不要转取决于**消费这个路径的程序**是本机原生还是 Windows 原生:
#
#     平台              | $ADB / python 是   | cygpath | 转换行为    | 对不对
#      Windows (Git Bash)| adb.exe / Windows  |  有     | 转成 E:\... | ✅
#      WSL2              | Linux 版 / Linux   |  无     | 原样返回    | ✅
#      Linux             | Linux 版 / Linux   |  无     | 原样返回    | ✅
#
#    重点看 WSL2 那行:**win_of 在 WSL 上是恒等函数,而这是对的** ——
#    WSL 上 $ADB 是 Linux 版 adb,传 `/mnt/e/...` 才对;若在这里用 wslpath
#    转成 `E:\...` 反而会把所有 pull/push 弄坏。
#
#    ⚠️ 但**不是所有消费方都跟着平台走**。有些程序无论如何都是 Windows 原生
#    (典型:Windows 版 gh.exe 从 WSL 里调),那种情况必须**无条件转** —— 用下面的
#    winpath,不要用 win_of。踩过:release-apk.sh 把 /mnt/e/.../x.apk 传给 Windows 版
#    gh,报 “no matches found for /mnt/e/...”(它根本没看见那个文件)。

# posix_of <路径> —— 把 Windows 路径转成 Git Bash 可用的 POSIX 形式
posix_of(){
  local p="$1"
  case "$p" in
    [A-Za-z]:[\\/]*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$p" 2>/dev/null || printf '%s' "$p"
      else
        printf '/%s%s' \
          "$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')" \
          "$(printf '%s' "${p#*:}" | tr '\\' '/')"
      fi ;;
    *) printf '%s' "$p" ;;
  esac
}
win_of(){
  local p="$1"
  case "$p" in
    /*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$p" 2>/dev/null || printf '%s' "$p"
      else printf '%s' "$p"; fi ;;
    *) printf '%s' "$p" ;;
  esac
}

# winpath <路径> —— **无条件**转成 Windows 路径,给「无论如何都是 Windows 原生程序」
# 的消费方用(典型:Windows 版 gh.exe 从 WSL 里调)。
#
# 与 win_of 的区别:win_of 是「按需」,只在 Windows 原生 shell 里转 —— 它服务
# $ADB / $PY,而那两个在 WSL 上就是 Linux 版,POSIX 路径才对。winpath 不做这个判断,
# 因为消费方不随平台变。WSL 靠 wslpath,Git Bash 靠 cygpath,都没有就原样返回。
winpath(){
  local p="$1"
  if command -v wslpath >/dev/null 2>&1 && [ "${PLATFORM:-}" = wsl ]; then
    wslpath -w "$p" 2>/dev/null || printf '%s' "$p"
  elif command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p" 2>/dev/null || printf '%s' "$p"
  else printf '%s' "$p"; fi
}

if _tmp_ok "${EASYANDROID_TMP:-}"; then
  TMP="$EASYANDROID_TMP"
elif _tmp_ok "$_REPO_DIR/.tmp"; then
  TMP="$_REPO_DIR/.tmp"
elif [ "$IS_WINDOWS" = 1 ] && [ -n "${TEMP:-}" ] && _tmp_ok "$(posix_of "$TEMP")"; then
  TMP="$(posix_of "$TEMP")"
elif _tmp_ok "${TMPDIR:-}"; then
  TMP="$TMPDIR"
elif _tmp_ok /tmp; then
  TMP=/tmp
else
  TMP="$_REPO_DIR/.tmp"; mkdir -p "$TMP" 2>/dev/null || true
fi
TMP="${TMP%/}"
TMP_WIN="$(win_of "$TMP")"

# 替代 mktemp —— 它默认模板写死在 /tmp
mktmp(){  mktemp "${1:-$TMP/tmp.XXXXXXXXXX}" 2>/dev/null; }
mktmpd(){ mktemp -d "${1:-$TMP/tmpd.XXXXXXXXXX}" 2>/dev/null; }

# ── 4. 超时垫片 ─────────────────────────────────────────────────────
# 用法: run_timeout <秒> <命令> [参数...]
_gnu_timeout=""
if command -v timeout >/dev/null 2>&1; then
  _p="$(command -v timeout)"
  # 只认 coreutils 那个:它在 /usr/bin 或 /bin 下,且接受 GNU 语法。
  # Windows 自带的是 C:\Windows\system32\timeout.exe,必须排除。
  case "$_p" in
    /usr/bin/timeout|/bin/timeout) _gnu_timeout="$_p" ;;
    *)
      if "$_p" --version 2>/dev/null | grep -qi coreutils; then _gnu_timeout="$_p"; fi ;;
  esac
fi

if [ -n "$_gnu_timeout" ]; then
  run_timeout(){ "$_gnu_timeout" "$@"; }
else
  # 退化路径:忽略超时秒数直接执行。功能可用,只是没有卡死护栏。
  run_timeout(){ local _s="$1"; shift; "$@"; }
fi

# ── 4b. 仓库 slug(owner/repo)───────────────────────────────────────
# 从 origin remote 推。release-apk.sh / release.sh 都要拿它拼 compare 链接,
# 所以抽在这里 —— 不然就是第 N 份拷贝(上次差一点变成两份)。
repo_slug(){
  git -C "${1:-$_REPO_DIR}" remote get-url origin 2>/dev/null \
    | sed 's#.*github\.com[:/]##;s#\.git$##' | tr -d '\r'
}


# ── 5. 跨平台小工具 ─────────────────────────────────────────────────
file_size(){ stat -c%s "$1" 2>/dev/null || wc -c < "$1" 2>/dev/null || echo 0; }
file_mtime(){ stat -c%Y "$1" 2>/dev/null || date +%s; }

# python(Git Bash 上可能只有 python,没有 python3)
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 \
     && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done

# pyfile <路径> —— 把路径转成「本机 python 认得的」形式。
# ⚠️ Windows 上这是必需的:Git Bash 的 /e/foo/bar 对 Windows 原生 python
#    是不存在的路径,会直接 FileNotFoundError。
pyfile(){ win_of "$1"; }

# run_py —— 用探测到的 python 跑脚本,自动处理路径。
#   用法同 python: run_py -c '...'   或   run_py script.py [args]
run_py(){ [ -n "$PY" ] || return 127; "$PY" "$@"; }

# re_escape <字符串> —— 转义成 grep -E 的字面量
#
# ⚠️ 别用 `sed 's/[.[\*^$]/\\&/g'` 这类写法,它有两个坑:
#   1. sed 替换串里的 `&` 代表「整个匹配」,必须写成 `\&`。
#      仓库里曾因此把 com.example.dualdemo 变成 com&example&dualdemo。
#   2. 字符类里同时出现 `]`、`\`、`|` 时,各版本 sed 的解析不一致,
#      很容易报 unterminated `s' command。
# 逐字符处理又长又慢但**没有歧义**,这种一次性小字符串不值得为性能妥协。
re_escape(){
  local s="$1" out="" i=0 c
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"
    case "$c" in
      '.'|'*'|'^'|'$'|'['|']'|'\'|'+'|'?'|'('|')'|'{'|'}'|'|') out="$out\\$c" ;;
      *) out="$out$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# ── 6. adb 解析 ─────────────────────────────────────────────────────
# 顺序:
#   1. 用户显式 $ADB(可用于临时切版本)
#   2. 仓库内 tools/platform-tools/(已 gitignore)—— 优先它,保证版本一致
#   3. 系统 PATH 里的 adb
_adb_ok(){ [ -n "${1:-}" ] && [ -x "$1" ] && "$1" version >/dev/null 2>&1; }

ADB=""
if _adb_ok "${ADB:-}"; then
  :
elif [ "$IS_WINDOWS" = 1 ] && _adb_ok "$_TOOLS_DIR/platform-tools/adb.exe"; then
  ADB="$_TOOLS_DIR/platform-tools/adb.exe"
elif _adb_ok "$_TOOLS_DIR/platform-tools/adb"; then
  ADB="$_TOOLS_DIR/platform-tools/adb"
elif command -v adb >/dev/null 2>&1 && _adb_ok "$(command -v adb)"; then
  ADB="$(command -v adb)"
fi

# ── 7. SDK 与 JDK ───────────────────────────────────────────────────
ANDROID_SDK_DIR="${ANDROID_SDK_DIR:-${ANDROID_HOME:-/opt/android-sdk}}"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_DIR}"

# Windows 上 /opt/android-sdk 基本不存在,补探常见安装位置
if [ "$IS_WINDOWS" = 1 ] && [ ! -d "$ANDROID_HOME" ]; then
  for cand in "$LOCALAPPDATA/Android/Sdk" "$HOME/AppData/Local/Android/Sdk"; do
    if [ -n "$cand" ] && [ -d "$cand" ]; then
      ANDROID_HOME="$(cygpath -u "$cand" 2>/dev/null || printf '%s' "$cand")"
      break
    fi
  done
fi
ANDROID_SDK_ROOT="$ANDROID_HOME"

# PATH 里补 SDK 工具(目录存在才补,不存在不报错)
for _p in "$ANDROID_HOME/platform-tools" "$ANDROID_HOME/cmdline-tools/latest/bin"; do
  [ -d "$_p" ] || continue
  case ":$PATH:" in
    *":$_p:"*) ;;
    *) PATH="$_p:$PATH" ;;
  esac
done

# JDK(tv-install 用 aapt2 读 APK 信息)
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME:-}/bin/java" ]; then
  for _jh in /opt/jdk/jdk-17* /usr/lib/jvm/*17* "$HOME/AppData/Local/Programs/Android Studio/jbr"; do
    if [ -n "$_jh" ] && [ -x "$_jh/bin/java" ]; then JAVA_HOME="$_jh"; break; fi
  done
fi

# bt_tool <工具名> —— 解析 build-tools 里的可执行文件(aapt2 / apksigner / zipalign ...)
# Windows 上是 .bat/.exe,Linux 上无后缀;装了多个版本时取版本号最高的那个。
# 找不到返回非零,调用方自己决定是报错还是跳过。
bt_tool(){
  local name="$1" bt c
  [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/build-tools" ] || return 1
  bt="$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
  [ -n "$bt" ] || return 1
  for c in "$bt$name" "$bt$name.bat" "$bt$name.exe"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ── APK 签名证书信息 ───────────────────────────────────────────────
# 取 APK 的签名证书指纹 / DN。
#
# 为什么要有这两个函数,而不是就地写 sed:
#
#  1. **空值必须变成错误。** 曾经是这样的调用:
#         fp="$(apksigner verify --print-certs "$apk" 2>/dev/null | sed -n '.../p')"
#         grep -qF "$fp" signing-manifest.txt      # ← 守护检查
#     当 fp 取不到(空)时,`grep -qF ""` **匹配任何非空文件** → 守护检查
#     静默通过,还打 ✅。**一个永远不会失败的检查,比没有检查更糟** ——
#     它会让人以为已经守住了。所以这里取不到就返回非 0。
#
#  2. **不要假定输出在 stdout。** 不同 build-tools 版本的 apksigner 把
#     `--print-certs` 的信息写到哪个流并不一致(实测 GitHub runner 上的版本
#     取不到,本机 34.0.0 正常)。所以合并 stderr 再解析。
#
#  3. 匹配放宽:只认 `... DN:` / `... SHA-256 digest:` 这两段后缀,
#     前缀("Signer #1 certificate")变化不影响。
apk_cert_fp(){
  local apk="$1" signer out fp
  signer="$(bt_tool apksigner)" || return 2
  [ -f "$apk" ] || return 3
  out="$("$signer" verify --print-certs "$apk" 2>&1)" || return 4
  fp="$(printf '%s\n' "$out" \
        | sed -n 's/.*SHA-256 digest:[[:space:]]*//p' | head -1 \
        | tr -d ':' | tr -d '[:space:]' | tr 'A-Z' 'a-z')"
  [ -n "$fp" ] || return 5
  printf '%s' "$fp"
}

apk_cert_dn(){
  local apk="$1" signer out dn
  signer="$(bt_tool apksigner)" || return 2
  [ -f "$apk" ] || return 3
  out="$("$signer" verify --print-certs "$apk" 2>&1)" || return 4
  dn="$(printf '%s\n' "$out" | sed -n 's/.*certificate DN:[[:space:]]*//p' | head -1)"
  [ -n "$dn" ] || return 5
  printf '%s' "$dn"
}

# 取不到时的诊断输出,交给调用方打到 stderr
apk_cert_dump(){
  local apk="$1" signer
  signer="$(bt_tool apksigner)" || { echo "(找不到 apksigner)"; return 0; }
  "$signer" verify --print-certs "$apk" 2>&1
}

export PLATFORM IS_WINDOWS TMP TMP_WIN ADB PY
export ANDROID_HOME ANDROID_SDK_ROOT PATH
[ -n "${JAVA_HOME:-}" ] && export JAVA_HOME

# ── 8. Windows 侧 adb(USB 引导用)───────────────────────────────────
# WSL2 没有 USB 总线,插在 Windows 上的设备只能由 Windows 版 adb 操作;
# Windows 原生上 $ADB 本身就是 adb.exe,直接复用。
WINADB="${WINADB:-$_TOOLS_DIR/platform-tools/adb.exe}"
WINADB_PORT="${WINADB_PORT:-15037}"
if [ "$IS_WINDOWS" = 1 ] && [ -n "$ADB" ]; then
  case "$ADB" in *.exe) WINADB="$ADB" ;; esac
fi
export WINADB WINADB_PORT

# ── 8b. GitHub CLI(发版上传 Release 附件用)───────────────────────
# WSL 里通常没装 gh,而 Windows 侧的 gh 是可执行的 —— 直接按路径用它。
GH=""
if command -v gh >/dev/null 2>&1; then
  GH="gh"
elif [ -x "/mnt/c/Program Files/GitHub CLI/gh.exe" ]; then
  GH="/mnt/c/Program Files/GitHub CLI/gh.exe"
fi
export GH

# ── 9. 通用封装 ─────────────────────────────────────────────────────
# adbx <serial> <adb 子命令...>
#   · 自动带 -s
#   · 自动 </dev/null —— 非交互环境下 adb shell 会占用 stdin,
#     把脚本的输入流吃掉,导致后续命令全部无输出(见 docs/05)
adbx(){ local _d="$1"; shift; "$ADB" -s "$_d" "$@" </dev/null 2>&1; }

# adb_connect_all —— 幂等地确保 device.env 里的网络设备已连接。
# 脚本开头调一次即可。已连接时几乎无开销。
# 注意「先 disconnect 再 connect」:设备休眠过之后 adb 里常留一条过期记录,
# 单发 connect 会被当成「已连接」直接返回,状态并不会恢复。
adb_connect_all(){
  [ -n "$ADB" ] || return 1
  "$ADB" start-server >/dev/null 2>&1 || true
  local _d _st
  for _d in "$PICO_ADDR" "$TV_ADDR"; do
    case "$_d" in *:*) ;; *) continue ;; esac      # 只管网络设备
    _st="$("$ADB" devices 2>/dev/null | awk -v x="$_d" '$1==x{print $2}')"
    if [ "$_st" != "device" ]; then
      "$ADB" disconnect "$_d" >/dev/null 2>&1 || true
      "$ADB" connect "$_d" >/dev/null 2>&1 || true
    fi
  done
  return 0
}

# adb_online <serial> —— 是否处于 device 状态
adb_online(){
  [ -n "$ADB" ] || return 1
  "$ADB" devices 2>/dev/null | awk -v d="$1" '$1==d && $2=="device"' | grep -q .
}

export -f mktmp mktmpd run_timeout file_size file_mtime posix_of win_of winpath pyfile run_py \
         apk_cert_fp apk_cert_dn apk_cert_dump \
          re_escape adbx adb_connect_all adb_online bt_tool 2>/dev/null || true

# ── 10. 提示 ────────────────────────────────────────────────────────
if [ ! -f "$_TOOLS_DIR/device.env" ] && [ -z "${EASYANDROID_QUIET:-}" ]; then
  echo "提示: 未找到 tools/device.env,使用示例地址 $TV_ADDR / $PICO_ADDR" >&2
  echo "      复制 tools/device.env.example 并填入真实地址。" >&2
fi

if [ -z "$ADB" ] && [ -z "${EASYANDROID_QUIET:-}" ]; then
  echo "提示: 没找到可用的 adb。装 Android platform-tools 后重试," >&2
  echo "      或跑 bash tools/fetch-platform-tools.sh 拉一份到 tools/platform-tools/。" >&2
fi
