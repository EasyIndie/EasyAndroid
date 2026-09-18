#!/usr/bin/env bash
#
# release 签名凭据:生成 / 查看 / 导出 / 导入
#
# ── 凭据从哪来 ──────────────────────────────────────────────────────
# **你是自己生成一份,不存在“下载/申请”这一步。** 自签名应用不需要 CA,
# 任意一把 RSA 密钥都能签。关键是这把密钥必须**一直用同一把** ——
# Android 用签名判定「是不是同一个应用」:
#
#   · 丢了 → 已装机的用户**永远无法升级**,只能卸载重装(数据全丢)
#   · 换了 → 同上,新包装不上,报 INSTALL_FAILED_UPDATE_INCOMPATIBLE
#   · 泄露 → 别人能以你的名义发版
#
# ── 多个应用:共用还是各用一把 ──────────────────────────────────
# **一个密钥库文件,每个应用一个别名** —— 推荐这个做法。
#
# 同一个签名下的应用之间是**可互信**的:能访问对方 `protectionLevel="signature"` 的
# 组件、能共享 sharedUserId 进程。所以共一把密钥 = 共一个信任域:
#   · 任何一把的口令泄露、被替换,整个信任域都受影响
#   · 想轮换密钥就得**所有共用它的应用一起换**,每个都要用户卸载重装
#   · 以后要单独转交 / 上架某个应用时会很难看
#
# 而分开的代价几乎为零 —— 都在**同一个 .jks 文件**里,只多一个别名:
#   · 仍然只需备份一个文件
#   · 每把可以独立轮换
#   · 泄露的影响面只限于那一个应用
#
# ⚠️ **已经发布过的应用不要改别名** —— 那等于换签名,老用户升不了级。
#    新加的应用用 --add-alias 拿自己的;老应用继续用默认的 keyAlias。
#
# 所以它等同私钥:不入库、不贴聊天、不进 issue。
#
# ── 凭据怎么配 ──────────────────────────────────────────────────────
# 两个文件,都已 gitignore:
#
#   tools/keystore/release.jks    密钥库
#   keystore.properties           密码与别名(仓库根)
#
# 各工程的 app/build.gradle.kts 从 rootDir 往上找 keystore.properties,
# **找到才配 signingConfig**;找不到时 assembleRelease 照样能跑,
# 只是产出 app-release-unsigned.apk(装不上设备)。
#
# ── 用法 ────────────────────────────────────────────────────────────
#   bash tools/gen-keystore.sh                    # 首次生成(已存在则拒绝)
#   bash tools/gen-keystore.sh --status           # 看当前配置:路径 / 别名 / 指纹 / 有效期
#   bash tools/gen-keystore.sh --add-alias <应用名>    # 给单个应用加一把专用密钥(推荐)
#   bash tools/gen-keystore.sh --scan [目录]         # 扫出本机所有密钥材料副本(含不该有的)⭐
#   bash tools/gen-keystore.sh --manifest            # 对仓里的 signing-manifest.txt 自检
#   bash tools/gen-keystore.sh --manifest --write    # 更新那个文件(加了别名之后跑)
#   bash tools/gen-keystore.sh --verify-against <apk>  # 确认本机密钥和某个已发布 APK 是同一把
#   bash tools/gen-keystore.sh --export [文件]    # 导出自包含的 base64 凭据包(备份/搬运/喂 CI)
#   bash tools/gen-keystore.sh --push-secret [owner/repo]  # 把凭据包直接写进仓库的 Actions secret
#   bash tools/gen-keystore.sh --import <文件>    # 从凭据包还原(换机器 / 灾后恢复)
#   bash tools/gen-keystore.sh --drill <文件|-> [--record [--label "在哪"]]
#     label 也可以从文件读(命令行只传 ASCII 路径,适合传不了中文的 shell):
#       bash tools/gen-keystore.sh --drill f --record --label @label.txt
#     label 也可以用环境变量给(WSL / Git Bash 里适用):
#       GENKS_DRILL_LABEL="飞书个人聊天(文件消息)" bash tools/gen-keystore.sh --drill f --record
#     `-` 表示从 stdin 读:从聊天窗口直接粘进终端(Ctrl-D 结束),不用先存文件   # ⭐ 恢复演练:在临时目录里真跑一遍导入并核对指纹
#                                                #   --record 把「哪天验的」记进入库的期望值文件
#   bash tools/gen-keystore.sh --force            # ⚠️ 覆盖重建 = 换签名,老用户升不了级
#
#   KS_PASSWORD=xxx bash tools/gen-keystore.sh    # 指定密码(默认随机 28 位,不打印)
#
#   # 三条回答「换机器怎么办」的路:
#   #   1. 本机生成 → --export 出一个文件 → 存进密码管理器
#   #   2. 新机器    → 从密码管理器取回那个文件 → --import
#   #   3. CI        → 把那个文件的**内容**存进 GitHub Secret(见 docs/06「签名凭据」)
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# 允许把「仓库根」指到别处。**只有 --drill(恢复演练)会用** ——
# 它要在临时目录里走一遍**真实的导入路径**,从而不碰本机凭据。
_REPO_DIR="${GENKS_ROOT:-$_REPO_DIR}"

KS_DIR="$_REPO_DIR/tools/keystore"
KS="$KS_DIR/release.jks"
PROPS="$_REPO_DIR/keystore.properties"
ALIAS="release"
# 可以入库的「期望值」文件 —— 只有指纹,没有秘密(见 cmd_manifest 的说明)
MANIFEST="$_REPO_DIR/signing-manifest.txt"

die(){ echo "!! $*" >&2; exit 1; }
have_creds(){ [ -f "$KS" ] && [ -f "$PROPS" ]; }

# ── 临时目录:用**列表**跟踪全部,退出时逐个删 ──────────────────────
#
# 这个文件里的临时目录会装着**明文私钥**。踩过两次,两次都真的把私钥留在了盘上:
#
#   1) `local tmpd` + `trap 'rm -rf "$tmpd"'` —— 函数返回后 local 已销毁,
#      脚本退出时 trap 报 “tmpd: unbound variable”,**什么都没删**。
#      (现场:.tmp/tmpd.3LdnqyLsIH/ 里躺着 release.jks + 明文密码的 properties)
#
#   2) 用单个全局 TMPD —— `write_bundle` 内部又 mktmpd 一次,把调用者的 TMPD
#      覆盖掉,那个目录从此没人删。而它恰恰装着一份完整的凭据包。
#      (现场:.tmp/tmpd.*/bundle.b64,每跑一次 --push-secret 漏一个)
#
# 所以:凡是要建临时目录,**一律走 mktmpd_tracked**;trap 遍历列表全删。
# 保证「创建」和「清理」之间没有任何可能失配的路径。
#
# ⚠️ 路径通过 **$TMPDIR_LAST** 返回,不用 stdout —— 因为 `d="$(mktmpd_tracked)"`
#    这种写法会开**子 shell**,在子 shell 里往 TMPDIRS 追加对父 shell 不可见,
#    结果 trap 遍历的是空列表,一个目录都删不掉。
#    踩过:第一版就是这么写的,改完再测 —— 每次 --push-secret 照样漏一份凭据包。
TMPDIRS=""
TMPDIR_LAST=""
mktmpd_tracked(){
  TMPDIR_LAST="$(mktmpd)" || return 1
  TMPDIRS="$TMPDIRS $TMPDIR_LAST"
}
_reap_tmp(){
  local d
  for d in $TMPDIRS; do rm -rf "$d" 2>/dev/null; done
  TMPDIRS=""
}
# EXIT 之外还接 INT/TERM/HUP —— 被 Ctrl-C 或 timeout 打断时也要清干净
trap '_reap_tmp' EXIT INT TERM HUP

# keytool 跟着 JDK 走
KEYTOOL=""
for c in "$JAVA_HOME/bin/keytool" "$(command -v keytool 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { KEYTOOL="$c"; break; }
done
[ -n "$KEYTOOL" ] || die "找不到 keytool。装 JDK 17(见 docs/01),或设好 JAVA_HOME。"

# 统一用英文输出解析(keytool 的字段名会跟着 locale 变)
kt(){ "$KEYTOOL" -J-Duser.language=en "$@"; }

# 从 keystore.properties 读一个字段
prop_of_file(){ sed -n "s/^$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null | tr -d '\r' | head -1; }
prop_of(){ prop_of_file "$PROPS" "$1"; }

# 任意密钥库的 SHA-256 指纹(归一化:小写无冒号)。
# 两个来源格式不同 —— keytool 大写带冒号、apksigner 小写无冒号 ——
# 凡是拿指纹做比较的地方都必须过这一步。这个坑本文件里踩了两次。
fp_of(){
  local ks="$1" pw="$2" al="${3:-$ALIAS}"
  kt -list -v -keystore "$ks" -storepass "$pw" -alias "$al" 2>/dev/null \
    | sed -n 's/^[[:space:]]*SHA256: //p' | head -1 | tr -d ':' | tr 'A-Z' 'a-z'
}
fingerprint_raw(){ fp_of "$KS" "$(prop_of storePassword)" | tr 'a-z' 'A-Z' | sed 's/../&:/g;s/:$//'; }
fingerprint(){ fp_of "$KS" "$(prop_of storePassword)"; }

show_certs(){
  local pw; pw="$(prop_of storePassword)"
  kt -list -v -keystore "$KS" -storepass "$pw" -alias "$(prop_of keyAlias)" 2>/dev/null \
    | grep -E '^(Alias name|Owner|Valid from|Signature algorithm name)' \
    | sed 's/^/  /'
}

# 密钥库里所有别名
list_aliases(){
  kt -list -keystore "$KS" -storepass "$(prop_of storePassword)" 2>/dev/null \
    | sed -n 's/^\([^,]*\), .*PrivateKeyEntry.*/\1/p'
}

list_app_aliases(){ sed -n 's/^alias\.\([^=]*\)=.*/\1/p' "$PROPS" 2>/dev/null | tr -d '\r'; }
alias_of_app(){ sed -n "s/^alias\.$1[[:space:]]*=[[:space:]]*\(.*\)$/\1/p" "$PROPS" 2>/dev/null | tr -d '\r' | head -1; }

# 大小写不敏感地找别名,返回密钥库里**实际**的名字。
# ⚠️ PKCS12 会把别名转成小写:传 -alias MyPlayer 进去,keytool -list 显示的是 myplayer。
#    Java 查 PKCS12 时大小写不敏感,所以用 MyPlayer 也能签;但一旦换成 JKS 就会找不到,
#    而且配置里写 MyPlayer、列表里显示 myplayer 看起来像对不上。所以回读实际值再写配置。
find_alias_ci(){
  local want; want="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  local a
  for a in $(list_aliases); do
    [ "$(printf '%s' "$a" | tr 'A-Z' 'a-z')" = "$want" ] && { printf '%s' "$a"; return 0; }
  done
  return 1
}

cmd_status(){
  echo "════════ 签名凭据 ════════"
  if ! have_creds; then
    echo "  ❌ 未配置 —— assembleRelease 会产出 unsigned 包(装不上设备)"
    echo "     生成: bash tools/gen-keystore.sh"
    return 1
  fi
  local ks_mode; ks_mode="$(stat -c%a "$KS" 2>/dev/null || echo '?')"
  echo "  密钥库  $KS  ($(file_size "$KS") bytes, 权限 $ks_mode)"
  case "$ks_mode" in
    777|666|555|444)
      # drvfs(Windows 盘挂载)/ 某些网络盘不支持 chmod —— 全目录都是 rwxrwxrwx。
      # 不说明白会让人以为密钥真的对所有人可读(其实受 Windows ACL 管)。
      echo "    ⚠️ 权限显示 $ks_mode —— 这类挂载点(drvfs / Windows 盘)不支持 chmod,"
      echo "       实际权限由 Windows ACL 决定。请确认这个目录**不在共享/云同步盘**里。" ;;
  esac
  echo "  配置    $PROPS  (storeFile=$(prop_of storeFile))"

  # 别名:一个密钥库可放多把密钥。共用一个别名 = 共一个信任域,见文件头说明。
  local default_alias pw a
  default_alias="$(prop_of keyAlias)"; pw="$(prop_of storePassword)"
  echo
  echo "  别名"
  for a in $(list_aliases); do
    local tag=""
    [ "$a" = "$default_alias" ] && tag="  ← keyAlias 默认(未单独配置的应用都用它)"
    printf '    %-18s%s\n' "$a" "$tag"
    printf '    %-18s%s\n' "" "$(fp_of "$KS" "$pw" "$a")"
  done
  local apps; apps="$(list_app_aliases)"
  echo
  if [ -n "$apps" ]; then
    echo "  按应用指定"
    for a in $apps; do printf '    %-18s → %s\n' "$a" "$(alias_of_app "$a")"; done
  else
    echo "  ⚠️ 没有 alias.<应用> 配置 —— apps/ 下所有工程都用默认那一把(共一个密钥)"
    echo "     想给新应用一把专用密钥: bash tools/gen-keystore.sh --add-alias <AppName>"
  fi
  echo
  echo "  证书(默认别名 $default_alias)"
  show_certs
  echo
  echo "  SHA-256 指纹(两者是同一个值的不同写法)"
  echo "    $(fingerprint_raw)"
  echo "    $(fingerprint)"
  echo "        ↑ 小写无冒号,与 apksigner 的输出格式一致"
  echo "    比对用: bash tools/gen-keystore.sh --verify-against <某个已发布的 apk>"
  # 有效期检查(keytool 的日期是英文,用 python 解析比 date -d 跨平台可靠)
  local end; end="$(kt -list -v -keystore "$KS" -storepass "$(prop_of storePassword)" -alias "$ALIAS" 2>/dev/null \
      | sed -n 's/^Valid from: .* until: //p' | head -1)"
  if [ -n "$end" ]; then
    run_py -c "
import sys
from datetime import datetime
try:
    d = datetime.strptime('$end'.strip(), '%a %b %d %H:%M:%S %Z %Y')
    days = (d - datetime.now()).days
    print(f'    {d:%Y-%m-%d} 到期,还剩 {days} 天' + ('  ⚠️ 不足一年,该计划换密钥了(换 = 老用户必须卸载重装)' if days < 365 else ''))
except Exception as e:
    print('    (解析到期时间失败:', e, ')')
" 2>/dev/null
  fi
  echo
  echo
  cmd_manifest
  echo
  echo "  ⚠️ 本机的必须是线上发布用的**同一把**。两种核对方式:"
  echo "       bash tools/gen-keystore.sh --manifest              # 对仓里记录的期望值"
  echo "       bash tools/gen-keystore.sh --verify-against <apk>  # 对某个已发布的 APK"
}

# 机械比对:本机密钥 vs 某个已发布的 APK 的签名。
# 这个功能就是为了防住「凭手感对比指纹」和人眼漏看。
cmd_verify(){
  local apk="${1:-}"
  [ -n "$apk" ] || die "用法: bash tools/gen-keystore.sh --verify-against <apk>"
  [ -f "$apk" ] || die "找不到 $apk"
  have_creds || die "本机还没配置凭据,先跑 bash tools/gen-keystore.sh"

  local apksigner; apksigner="$(bt_tool apksigner)"
  [ -n "$apksigner" ] || die "找不到 apksigner(需要 build-tools)"

  local mine theirs
  mine="$(fingerprint)"
  theirs="$("$apksigner" verify --print-certs "$apk" 2>/dev/null \
            | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | tr -d ':' | tr 'A-Z' 'a-z')"
  [ -n "$mine" ]   || die "本机读不出证书指纹(密钥库/密码不对?)"
  [ -n "$theirs" ] || die "读不出 $apk 的签名 —— 它没签名?"

  echo "  本机密钥  $mine"
  echo "  该 APK    $theirs"
  echo
  if [ "$mine" = "$theirs" ]; then
    echo "  ✅ 同一把 —— 本机可以继续为此应用发新版(老用户能正常升级)"
  else
    echo "  ❌ **不是同一把** —— 用本机这把发新版,老用户会报" >&2
    echo "     INSTALL_FAILED_UPDATE_INCOMPATIBLE,必须卸载重装(数据全丢)" >&2
    echo "     先搞清楚哪把才是对的:从密码管理器取回正确的凭据包," >&2
    echo "     bash tools/gen-keystore.sh --import <文件>" >&2
    return 1
  fi
}

# 把当前凭据打成一个自包含的 base64 凭据包(供 --export / --push-secret 共用)。
# 固定文件名打包,便于还原时定位。
write_bundle(){
  local out="$1" fp; fp="$(fingerprint_raw)"
  [ -n "$fp" ] || die "读不出证书指纹 —— 密钥库或密码可能对不上"

  # ⚠️ 必须用**函数内**的目录变量,不能碰全局 TMPD —— 否则会把调用者的
  #    临时目录孤立掉,而那个目录里可能正装着一份凭据包(见文件上方 2) 的说明)。
  local t
  mktmpd_tracked || die "建临时目录失败"
  t="$TMPDIR_LAST"
  cp "$KS" "$t/release.jks"
  cp "$PROPS" "$t/keystore.properties"
  chmod 600 "$t/release.jks" "$t/keystore.properties" 2>/dev/null || true
  ( cd "$t" && tar czf bundle.tgz release.jks keystore.properties ) || die "打包失败"

  mkdir -p "$(dirname "$out")" 2>/dev/null || true
  {
    echo "# EasyAndroid release 签名凭据包"
    echo "# 生成: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "# 默认别名: $(prop_of keyAlias)"
    local a; for a in $(list_app_aliases); do echo "#   alias.$a=$(alias_of_app "$a")"; done
    echo "# SHA-256 指纹: $fp"
    echo "#"
    echo "# ⚠️ 这个文件等同于私钥 —— 存密码管理器/Secret,别提交、别贴聊天。"
    echo "#     丢了 = 已装机应用永远无法升级,泄露 = 别人能以你的名义发版。"
    echo "#"
    echo "# 还原: bash tools/gen-keystore.sh --import <本文件>"
    echo "#"
    # ⚠️ **必须折行**(76 列是 base64 惯例)。
    #    输出成一整个长行的话,把凭据包**粘进终端**会被截断:
    #    Linux 终端规范模式下单行缓冲上限是 4096(MAX_CANON),
    #    实测 7001 字符的长行只进来了 4096 —— 而凭据包有 6800+ 字符。
    #    折行后每行 76 字符,粘贴、邮件、聊天都不会碰上限。
    base64 < "$t/bundle.tgz" | fold -w76
    echo
  } > "$out"
}

# 把凭据包写进仓库的 Actions secret(本地开发不需要,只有想让 CI 也签包时才用)。
#
# 为什么不能反过来(让 CI 自己创建 secret):secret 是只写的,
# 而且这条路等于允许 CI 自赋权限 —— GitHub 从设计上就不支持。
# 所以必须从**已认证的本机**推。
cmd_push_secret(){
  have_creds || die "本机还没配置凭据,先跑 bash tools/gen-keystore.sh"
  [ -n "$GH" ] || die "找不到 gh(GitHub CLI)。装一个: https://cli.github.com/"

  local repo="${1:-}"
  [ -n "$repo" ] || repo="$(git -C "$_REPO_DIR" remote get-url origin 2>/dev/null \
      | sed 's#.*github\.com[:/]##;s#\.git$##')"
  [ -n "$repo" ] || die "推不出仓库 slug。用 --push-secret <owner/repo> 指定"

  # 先写到临时文件再重定向给 gh —— 不用 --body,避免命令行参数长度限制,
  # 也不用把密钥落在 dist/ 里(那是构建产物目录,容易忘掉)。
  mktmpd_tracked || die "建临时目录失败"; TMPD="$TMPDIR_LAST"
  local tmpf="$TMPD/bundle.b64"
  write_bundle "$tmpf"

  # 推之前也验一次 —— 写进 secret 里的坏包更难发现(要到 CI 跑起来才炸)
  verify_bundle "$tmpf" || die "要推给 CI 的凭据包自检失败 —— 没有写入 secret"

  echo "==> 写入 $repo 的 Actions secret: KEYSTORE_B64  ($(file_size "$tmpf") bytes)"
  # 重定向由 bash 做(本地 POSIX 路径),gh 从 stdin 读 —— 不需要 winpath。
  #
  # ⚠️ **这里绝对不能加 </dev/null**。仓库的规矩是「给吃掉 stdin 的原生程序加 </dev/null」,
  #    但 gh secret set 恰恰要**从 stdin 读值**。`< file` 和 `</dev/null` 都作用于 stdin,
  #    后者会覆盖前者 —— 结果 secret 被设成**空值**,而且不报错。
  #    踩过:CI 里 `KEYSTORE_B64:` 是空的,产出的还是 unsigned 包。
  local out rc
  out="$("$GH" secret set KEYSTORE_B64 --repo "$repo" < "$tmpf" 2>&1)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'
  [ "$rc" = 0 ] || die "gh secret set 失败(exit $rc;需要 repo 权限,仓库必须是你的)"
  # gh 成功时不总输出东西 —— 回查一下名字在不在,别把“静默失败”当成功
  "$GH" secret list --repo "$repo" 2>/dev/null | grep -q "^KEYSTORE_B64" \
    || die "secret 列表里看不到 KEYSTORE_B64 —— 写入可能没生效"

  echo
  echo "==> 现有 secrets(值只能写、读不回来,GitHub 也不显示):"
  "$GH" secret list --repo "$repo" </dev/null 2>&1 | sed 's/^/  /'
  echo
  echo "════════ 怎么确认它真能用 ════════"
  echo "  secret 读不回值,所以只能看 CI 的**产物**:推一次提交,等 CI 跑完,"
  echo "  把 CI 上传的 APK 下载下来对比指纹:"
  echo "    bash tools/gen-keystore.sh --verify-against <CI 产出的 apk>"
  echo "  同一把 → ✅ CI 用的是同一把密钥,老用户能升级。"
  echo
  echo "  注意:如果 CI 日志里出现 '未配置 KEYSTORE_B64' 的 notice,"
  echo "  说明 secret 没生效(名字拼错?仓库不对?)—— 那种情况 CI 产的是 unsigned 包。"
}
# 给单个应用加一把专用密钥(同一个密钥库文件,新别名)。
# 已发布过的应用千万别这么做 —— 换别名 = 换签名 = 老用户升不了级。
cmd_add_alias(){
  local name="${1:-}"
  [ -n "$name" ] || die "用法: bash tools/gen-keystore.sh --add-alias <AppName>"
  case "$name" in *[!A-Za-z0-9_.-]*) die "应用名只能含字母数字 . _ - : $name" ;; esac
  have_creds || die "本机还没配置凭据,先跑 bash tools/gen-keystore.sh"

  local pw ksfile; pw="$(prop_of storePassword)"; ksfile="$(prop_of storeFile)"
  case "$ksfile" in
    /*|[A-Za-z]:[\\/]*) ;;
    *) ksfile="$_REPO_DIR/$ksfile" ;;
  esac
  [ -f "$ksfile" ] || die "找不到密钥库: $ksfile"

  local existing; existing="$(find_alias_ci "$name" || true)"
  if [ -n "$existing" ]; then
    echo "==> 别名已存在($existing),只补映射"   # 幂等
  else
    echo "==> 在 $ksfile 里新增别名 $name(密钥库文件不变)"
    kt -genkeypair -keystore "$ksfile" -alias "$name" \
      -keyalg RSA -keysize 4096 -validity 10950 \
      -storepass "$pw" -keypass "$pw" \
      -dname "CN=$name Release, OU=dev, O=EasyAndroid, L=-, ST=-, C=CN" \
      >/dev/null 2>&1 || die "keytool 新增别名失败"
    existing="$(find_alias_ci "$name" || true)"
    [ -n "$existing" ] || die "新增后回读不到别名,keytool 行为异常"
  fi
  [ "$existing" != "$name" ] && echo "     (密钥库里实际存为 '$existing' —— PKCS12 会把别名转小写)"

  if [ -z "$(alias_of_app "$name")" ]; then
    {
      echo
      echo "# 应用 $name 用自己的一把密钥(同一个 .jks 里的独立别名)。"
      echo "# 没有 alias.<应用> 这一行就回落到上面的 keyAlias。见 docs/06「签名凭据」。"
      echo "# ⚠️ 已经发布过的应用不要改别名 —— 等于换签名,老用户升不了级。"
      echo "alias.$name=$existing"
    } >> "$PROPS"
    echo "==> 已写入 $PROPS: alias.$name=$existing"
  fi
  echo "      SHA-256 $(fp_of "$ksfile" "$pw" "$existing")"
  echo
  echo "  下一次 bash tools/release-apk.sh <version> 就会用它签名。"
}

# 「签名期望值」—— 只有一个用途:回答「我手里这把是不是本仓库发布用的那把」。
#
# 为什么这个文件**可以**入库:
#   里面只有别名和证书 SHA-256 指纹。指纹是公钥的哈希,**不是秘密** ——
#   公开它,别人既反推不出私钥,也签不出能被安装的包。
#   而它的价值恰恰在于公开:任何机器(换机器、装 CI、灾后恢复)拿到一份凭据后,
#   能立刻核对是不是同一把,而不是等发完版才发现老用户装不上。
#
# 与之相对,凭据本体(release.jks + 密码)绝对不能入库 —— 见文件头说明。
#
# 指纹统一写成 **小写无冒号**(与 apksigner 的输出格式一致),
# 免得又踩「keytool 大写带冒号 vs apksigner 小写」那个归一化坑。
# 扫描工作目录,列出**所有**密钥材料的副本。
#
# 为什么需要:
#   1. 「我到底有几份、都在哪」—— 「过段时间找不到」这个问题的一半是**不知道有几份**
#   2. 发现**不该存在**的副本。实测踩过:--push-secret 每次都在 .tmp/ 漏一份
#      完整凭据包(明文),没人知道它们躺在那儿,直到跑了一次扫描。
#
# 判定依据(任一命中就算):
#   · 文件名像密钥文件(release.jks / keystore.properties / *.b64 …)
#   · 内容与本机密钥库**逐字节相同**(改名、换扩展名也躲不掉)
#   · 文件头是本仓库凭据包的标志行
cmd_scan(){
  local root="${1:-$_REPO_DIR}"
  root="$(cd "$root" && pwd)"
  echo "  ════ 扫描密钥材料副本: $root ════"

  local ksha=""
  have_creds && ksha="$(sha256sum "$KS" 2>/dev/null | cut -d' ' -f1)"

  local list; list="$TMPDIR_LAST.scan"
  mktmpd_tracked >/dev/null || die "建临时目录失败"
  list="$TMPDIR_LAST/scan.txt"

  "$PY" - "$(pyfile "$root")" "$ksha" "$(pyfile "$KS")" "$(pyfile "$PROPS")" > "$list" <<'PYEOF'
import os, sys, hashlib
root, ksha, ks, props = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
SKIP_DIR = {'.git', 'build', '.gradle', 'node_modules', '.idea', 'platform-tools'}
# 子串匹配(以前是精确匹配,于是 signing-bundle.b64.bak 漏了)
NAME_HINTS = ('release.jks', 'keystore.properties', 'signing-bundle', 'bundle.b64')
HEADER = '# EasyAndroid release'

def size_of(p):
    try:
        return os.path.getsize(p)
    except OSError:
        return -1

def sha(p):
    h = hashlib.sha256()
    try:
        with open(p, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b''):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None

# ⚠️ 必须在 size_of/sha 定义**之后**才能调用 —— 写在这之前会 NameError,
#    而 NameError 会让整个扫描崩掉。崩掉本身还不算最坏:如果外面没检查退出码,
#    它看起来就是「什么都没找到」—— 一个安全扫描静默失败比不扫更糟。
ks_size = size_of(ks) if ks else -1

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIR]
    for fn in filenames:
        full = os.path.join(dirpath, fn)
        why = None
        # 判定顺序:名字 → 大小+哈希 → **内容标志行**。
        # ⚠️ 最后一条**不能限定扩展名**。踩过:用户把本机导出的那份改名成
        #    `signing-bundle.b64.bak`,它既不在名字清单里(清单当时是精确匹配)、
        #    大小也 ≠ 密钥库(它是 base64 包,7393 ≠ 4394),于是被整个跳过 ——
        #    一份含明文私钥的副本躺在 dist/ 里,而 --scan 报「额外 0 份」。
        #    凭据包的内容有独一无二的标志行,按它认,不看文件名。
        if any(h in fn for h in NAME_HINTS) or fn.endswith(('.jks', '.keystore', '.p12')):
            why = '文件名像密钥材料'
        elif ksha and size_of(full) == ks_size and sha(full) == ksha:
            # 逐字节相同的副本**大小必然相同** —— 先用大小筛掉绝大多数文件,
            # 再算哈希。改名、换扩展名、去掉扩展名都躲不掉。
            why = '内容与本机密钥库完全相同(改了名也没用)'
        elif 0 < size_of(full) < 2_000_000:
            # 按标志行认,不看扩展名、不看文件名。
            # ⚠️ 必须要求它出现在**第一行**:只在前 N 字节里 grep 的话,
            #    连本脚本自己都会被命中(它的报错文案里就有这个字符串)——
            #    实测踩到,于是 tools/gen-keystore.sh 被标成"密钥材料、会被提交"。
            #    凭据包的第一行**就是**这个标志,这就是最精确的判据。
            try:
                with open(full, 'r', errors='ignore') as f:
                    first = f.readline().lstrip('\ufeff').strip()
                if first.startswith(HEADER):
                    why = '是本仓库的凭据包(含私钥+明文密码)'
            except OSError:
                pass
        if why:
            try:
                size = os.path.getsize(full)
            except OSError:
                size = 0
            print(f"{os.path.relpath(full, root)}\t{size}\t{why}")
PYEOF
  local prc=$?
  [ "$prc" = 0 ] || die "扫描器自己崩了(exit $prc)—— **不能当成「没找到」**,请先修它"

  local n_exp=0 n_odd=0 n_tracked=0
  local rel size why ign
  # 预期内的三个位置
  local expected=" tools/keystore/release.jks keystore.properties dist/signing-bundle.b64 "
  while IFS=$'\t' read -r rel size why; do
    [ -n "$rel" ] || continue
    ign=""
    git -C "$root" check-ignore -q "$rel" 2>/dev/null && ign="gitignored" || ign="⚠️ 会被提交"
    [ "$ign" = "gitignored" ] || n_tracked=$((n_tracked+1))
    case "$expected" in
      *" $rel "*) n_exp=$((n_exp+1)); printf '  ✅ 预期内   %-44s %8s B  %s\n' "$rel" "$size" "$ign" ;;
      *)           n_odd=$((n_odd+1)); printf '  ⚠️  额外副本 %-44s %8s B  %s   ← %s\n' "$rel" "$size" "$ign" "$why" ;;
    esac
  done < "$list"

  echo
  if [ "$n_exp" = 0 ] && [ "$n_odd" = 0 ]; then
    echo "  扫描不到任何密钥材料 —— 本机没有凭据(或者它们都不在这个目录下)"
  else
    echo "  预期内 $n_exp 份,额外 $n_odd 份"
  fi
  echo "  ⚠️  这个扫描只看 $root。密码管理器、U 盘、别的机器上的副本它看不到 ——"
  echo "     那些要靠 docs/06「凭据在哪」记下来,不然就是「找不到了」。"
  [ "$n_odd" = 0 ] || echo "  建议:额外副本确认用不到的,删掉(每多一份就多一个泄露面)"
  [ "$n_tracked" = 0 ] || echo "  ❌ 有 $n_tracked 份**没被 gitignore** —— 一旦提交就无法收回!"
  # 干净状态下额外副本应该是 0 份,所以它会让这个命令失败 —— 这样能放进 CI/自检。
  # 不想让仓库的工作区里存第二份密钥副本,那是「忘了的地方」的主要来源。
  if [ "$n_tracked" != 0 ] || [ "$n_odd" != 0 ]; then return 1; fi
  return 0
}

cmd_manifest(){
  have_creds || die "本机还没配置凭据,先跑 bash tools/gen-keystore.sh"
  local pw; pw="$(prop_of storePassword)"

  if [ "${1:-}" = "--write" ]; then
    {
      echo "# 签名期望值 —— 这个文件**可以**入库,和 keystore.properties 不是一回事。"
      echo "#"
      echo "# 里面只有别名和证书 SHA-256 指纹。指纹是公钥的哈希,**不是秘密**:"
      echo "# 公开它,别人既反推不出私钥,也签不出能被安装的包。"
      echo "#"
      echo "# 它的用途是**自检** —— 任何机器拿到一份凭据后,先跑:"
      echo "#     bash tools/gen-keystore.sh --manifest"
      echo "# 就能知道「手里这把是不是本仓库发布用的那把」,"
      echo "# 而不是等发完版才从用户的 INSTALL_FAILED_UPDATE_INCOMPATIBLE 里发现。"
      echo "#"
      echo "# ⚠️ 凭据本体(release.jks + 密码)绝对不能入库,存密码管理器。见 docs/06。"
      echo "#"
      echo "# 更新:bash tools/gen-keystore.sh --manifest --write"
      echo "# 自检:bash tools/gen-keystore.sh --manifest"
      echo "#"
      echo "# 生成时间:$(date '+%Y-%m-%d %H:%M:%S %z')"
      echo "# 指纹格式:小写无冒号(与 apksigner 一致)"
      echo "#"
      echo "# drill.* 是恢复演练的记录,由 --drill <文件> --record 写入:"
      echo "#   drill.last    上次演练日期(超过半年 --status 会提醒重跑)"
      echo "#   drill.where   **那份副本放在哪**(持久位置:飞书/密码管理器/U 盘…)"
      echo "#   drill.file    演练时本地那个文件叫什么(可能只是临时下载,验完就删)"
      echo "#   drill.size    字节数 —— 用来说明「验的到底是哪一份」"
      echo
      echo "default_alias=$(prop_of keyAlias)"
      local a
      for a in $(list_aliases); do echo "alias.$a=$(fp_of "$KS" "$pw" "$a")"; done
      for a in $(list_app_aliases); do echo "app.$a=$(alias_of_app "$a")"; done
      # ⚠️ 保留已有的 drill.* —— 重建「期望指纹」不该抹掉「演练历史」。
      #    踩过:重建一次,验证记录就没了,而没人会注意到(那个字段本来就少人看)。
      echo
      grep -E '^drill\.' "$MANIFEST" 2>/dev/null || true
    } > "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
    echo "==> 已更新 $MANIFEST"
    grep -vE '^#|^$' "$MANIFEST" | sed 's/^/     /'
    return 0
  fi

  if [ ! -f "$MANIFEST" ]; then
    echo "  还没有 $MANIFEST —— 用 --manifest --write 生成"
    return 0
  fi
  echo "  ════ 与 $(basename "$MANIFEST") 核对(本机这把是不是发布用的那把)════"
  local want got al bad=0 n=0
  while IFS='=' read -r key want; do
    case "$key" in
      alias.*)
        al="${key#alias.}"; n=$((n+1))
        got="$(fp_of "$KS" "$pw" "$al" 2>/dev/null)"
        if [ -z "$got" ]; then
          echo "  ❌ 本机没有别名 '$al'"; bad=1
        elif [ "$got" = "$want" ]; then
          echo "  ✅ $al 指纹一致"
        else
          echo "  ❌ $al 指纹**不一致** —— 别用它发版!"; bad=1
          echo "       期望 $want"
          echo "       本机 $got"
          echo "       先把正确的凭据导入: bash tools/gen-keystore.sh --import <凭据包>"
        fi ;;
    esac
  done < <(grep -E '^alias\.' "$MANIFEST" 2>/dev/null)
  [ "$n" -gt 0 ] || { echo "  (文件里没有 alias.* 条目)"; return 0; }
  [ "$bad" = 0 ] && echo "  ✅ 全部一致" || echo "  ❌ 有别名对不上 —— 见上面提示"

  # 「上次恢复演练是什么时候」—— 备份会**悄悄过期**(文件被改坏、口令忘了、
  # 存的那份是旧的),不演练就不知道。所以把日期摆出来,让它自己显得可疑。
  local dl; dl="$(sed -n 's/^drill\.last=//p' "$MANIFEST" 2>/dev/null | head -1)"
  if [ -n "$dl" ]; then
    local days=""
    days="$("$PY" -c "
import datetime,sys
try:
    d=datetime.date.fromisoformat('$dl')
    print((datetime.date.today()-d).days)
except Exception:
    print('')
" 2>/dev/null)"
    if [ -n "$days" ]; then
      # 位置字段叫 drill.where(旧版本叫 drill.bundle,为兼容两种都读)
      local dw; dw="$(sed -n 's/^drill\.where=//p' "$MANIFEST" | head -1)"
      [ -n "$dw" ] || dw="$(sed -n 's/^drill\.bundle=//p' "$MANIFEST" | head -1)"
      echo "  上次恢复演练 $dl (${days} 天前,位置:$dw)"
      [ "$days" -gt 180 ] && echo "  ⚠️  超过半年没验过备份了 —— 跑一次:bash tools/gen-keystore.sh --drill <凭据包> --record"
    else
      echo "  上次恢复演练 $dl"
    fi
  else
    echo "  ⚠️  从没跑过恢复演练。备份「存了」不等于「能恢复」——"
    echo "     bash tools/gen-keystore.sh --drill <凭据包> --record"
  fi
  return "$bad"
}

# 从一段「可能是聊天粘贴文本」的内容里抽出凭据包的 base64 负载。
#
# 为什么需要:凭据包的实际流转方式常常是**粘贴** —— 飞书/微信/Slack 的个人消息、
# 邮件正文、笔记。那些地方会带上发送者、时间戳、引用标记,还会把长行折行,
# 有时甚至**不换行就往负载末尾追加东西**(「已读」、时间戳)。
#
# 原来的实现是「去掉 # 注释行,其余全当 base64」:多出来的任何东西都会让解码
# 失败,还报「文件是不是被改坏了?」—— 把人引向错误的怀疑方向(包没坏)。
#
# 难点:没法靠格式规则分辨负载和噪音。
#   · 折行宽度不确定(76 列是惯例,窄窗口可能折到 30)
#   · 人名、`OK`、`20260917` 恰好也由 base64 字符组成
#   · 尾部杂质会和负载粘在同一行上
# 所以改成**多策略试 + 真验证**:每个策略拼出来的串都实际走一遍
#     base64 解码 → gzip 解压 → 当作 tar 打开 → 确认里面有 release.jks
#    和 keystore.properties
# 全部通过才算数。**验内容,不验退出码** —— 只看 gzip 魔数是不够的,
# 尾部杂质照样能让魔数匹配上(魔数在开头)。
#
# 一个有用的事实:合法 base64 里 `=` 只出现在**末尾**,
# 所以第一个 `=` 之后的东西一定是杂质,可以截掉。
#
# 返回:0 成功(stdout = 一整行 base64);非 0 失败(stderr 说明原因)
bundle_extract(){
  local f="$1"
  "$PY" - "$(pyfile "$f")" <<'PYINNER'
import base64, gzip, io, re, sys, tarfile

try:
    text = open(sys.argv[1], encoding='utf-8-sig', errors='replace').read()
except OSError as e:
    print(f'READFAIL {e}', file=sys.stderr); sys.exit(2)

MARK = '# EasyAndroid release'
idx = text.find(MARK)
if idx < 0:
    print('NOMARK', file=sys.stderr); sys.exit(3)
text = text[idx:]
lines_all = [l.strip() for l in text.splitlines()]
B64 = re.compile(r'[A-Za-z0-9+/=]+')
FULL = re.compile(r'^[A-Za-z0-9+/=]+$')

def cut(s):
    """截掉尾部 padding 之后的杂质(合法 base64 的 `=` 只在末尾)。

    ⚠️ 必须保留**整段** `=`,不能只留一个:padding 可能是 `==`(载荷长度
       模 3 余 1 时)。先前写成 `s[:k+1]`,于是把 `...AAA==` 削成了 `...AAA=`,
       长度从 6836 变 6835 不再是 4 的倍数 —— python 的 b64decode 会自动补
       padding 所以看不出来,而 GNU `base64 -d` 直接报 invalid input。
       **真凭据包反而解不开,而所有造的测试样例都通过。**
    """
    k = s.find('=')
    if k < 0:
        return s
    m = k
    while m < len(s) and s[m] == '=':
        m += 1
    return s[:m]

def ok(s):
    """真验证:解码 → 解压 → 当 tar 打开 → 里面必须有那两个文件。"""
    if len(s) < 100:
        return False
    try:
        raw = base64.b64decode(s + '=' * ((-len(s)) % 4))
        tar_bytes = gzip.decompress(raw)
        with tarfile.open(fileobj=io.BytesIO(tar_bytes)) as tf:
            names = set(tf.getnames())
    except Exception:
        return False
    return {'release.jks', 'keystore.properties'} <= names

body = [l for l in lines_all if l and not l.startswith('#')]
whole = [l for l in body if FULL.match(l)]

runs, run = [], []
for l in body:
    if FULL.match(l):
        run.append(l)
    elif run:
        runs.append(run); run = []
if run:
    runs.append(run)
longest = max(runs, key=lambda r: sum(len(x) for x in r)) if runs else []

# 由宽到窄。第一个是主力:按行取「base64 前缀」,能救回尾部粘了杂质的行。
strategies = [
    ('逐行取 base64 前缀', cut(''.join(m.group(0) for m in (B64.match(l) for l in body) if m))),
    ('整行都是 base64',    cut(''.join(whole))),
    ('整行且长度>=32',     cut(''.join(l for l in whole if len(l) >= 32))),
    ('最长的连续段',        cut(''.join(longest))),
]
for name, payload in strategies:
    if ok(payload):
        print(f'（识别方式:{name},负载 {len(payload)} 字符）', file=sys.stderr)
        sys.stdout.write(payload)
        sys.exit(0)

if not body:
    print('NOPAYLOAD', file=sys.stderr); sys.exit(4)
# 有一行长得离谱(>4000)—— 多半是「粘进终端被 MAX_CANON 截断」,
# 而不是包本身坏了。给针对性的提示,别让人去怀疑备份。
if any(len(l) > 4000 for l in body):
    print('LONGLINE', file=sys.stderr); sys.exit(6)
print('NOGZIP', file=sys.stderr); sys.exit(5)
PYINNER
}

# 解一份凭据包到目录 $2。失败时给出**可执行**的提示,而不是笼统的「文件坏了」
unpack_bundle(){
  local src="$1" dest="$2" payload rc=0
  payload="$(bundle_extract "$src" 2>/dev/null)" || rc=$?
  if [ "$rc" != 0 ]; then
    case "$rc" in
      3) die "$src 里找不到凭据包的标志行 '# EasyAndroid release 签名凭据包'。
       最常见的成因:从聊天/邮件里复制时**漏了开头那几行**。整段重贴一次。
       或者它根本不是本仓库的凭据包。" ;;
      4) die "$src 里找到了标志行,但后面没有 base64 字符 —— 复制**被截断**了。" ;;
      5) die "$src 里的内容拼起来解不出 gzip —— **不完整或被改动了**。
       最可能是复制时截断(聊天客户端常只展开前面一段)。
       重新整段复制,再用 --drill 验一次。" ;;
      6) die "$src 里有超长行(>4000 字符),几乎肯定是**粘进终端时被截断了**。
       Linux 终端规范模式下单行缓冲上限是 4096(MAX_CANON),长行会被静默切掉。
       三个办法(任选):
         · 存成文件再验:用记事本粘进去,另存为 UTF-8,再 --drill <那个文件>
         · 重新导出一份**折行**的格式(0.4.5 起默认折行 76 列)
         · 不要把凭据包用「终端粘贴」来传" ;;
      *) die "读不了 $src" ;;
    esac
  fi
  # GNU base64 要求长度是 4 的倍数(python 的 b64decode 会自动补,它不会)。
  # 取出来的负载长度理论上是 4 的倍数,但粘贴过程可能吃掉尾部的 `=`,补上更稳。
  case $(( ${#payload} % 4 )) in
    2) payload="$payload==" ;;
    3) payload="$payload=" ;;
  esac
  printf '%s' "$payload" | base64 -d > "$dest/b.tgz" 2>/dev/null \
    || die "base64 解码失败"
  ( cd "$dest" && tar xzf b.tgz ) || die "解包失败 —— 内容不完整(像是被截断)"
  [ -f "$dest/release.jks" ] && [ -f "$dest/keystore.properties" ] \
    || die "包里缺文件(release.jks / keystore.properties)"
}


# ══════════════════════════════════════════════════════════════════════
# 恢复演练 —— 回答「我存下/存走的那份备份,以后真的还能用吗?」
#
# 为什么需要它:**「存了」和「能恢复」是两件事。** 半年后再打开备份,可能发现
#   · 文件被邮件客户端或云盘改坏(自动换行、截断、加 BOM)
#   · 密码管理器里存的是更早那一次导出的旧版本
#   · 导出的口令自己忘了、或者当时就是随手设的
#   · 存的时候没注意,存进了另一个项目的凭据
# 这些**只有真跑一遍才知道**。而真跑一遍的风险是:万一那份是旧的,就把本机
# 凭据覆盖成错的了 —— 于是这里在**临时目录**里跑完整的 --import 路径。
#
# 它验的是:解码 → 解包 → 读密码 → 算指纹 → 对仓里记录的期望值。
# 全程不碰 $KS / $PROPS。
cmd_drill(){
  # 参数由主解析器收集后传进来(--drill / --record / --label 顺序任意)。
  # 踩过两次都是「参数被静默丢掉,命令照常成功」,所以这里不再自己解析。
  local src="$DRILL_SRC"
  [ -n "$src" ] || die "用法: bash tools/gen-keystore.sh --drill <凭据包文件|-> [--record [--label \"在哪\"]]"

  # `--drill -` 从 stdin 读 —— 直接从聊天窗口粘进终端,不用先存文件。
  # (粘贴完按 Ctrl-D 结束输入。)
  if [ "$src" = "-" ]; then
    mktmpd_tracked || die "建临时目录失败"
    src="$TMPDIR_LAST/从聊天粘进来的.txt"
    cat > "$src" || die "读 stdin 失败"
    [ -s "$src" ] || die "stdin 是空的 —— 没粘上?粘完要按 Ctrl-D"
    echo "  已从 stdin 读入 $(wc -c <"$src" | tr -d ' ') 字节"
  fi
  [ -f "$src" ] || die "找不到 $src"
  # 子进程可能在别的 cwd 下跑,先取绝对路径
  src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

  mktmpd_tracked || die "建临时目录失败"; TMPD="$TMPDIR_LAST"
  local root; root="$TMPD"

  echo "████ 恢复演练(全程不碰本机凭据)████"
  echo "  备份文件  $src"
  echo "            $(wc -c <"$src" | tr -d ' ') 字节,含 $(grep -c '^#' "$src" 2>/dev/null | tr -d ' ') 行头部注释"
  echo "  演练目录  $root"
  echo "  本机凭据  $KS"
  echo "            ↑ 演练结束后它应该**一个字节都没变**"
  echo

  echo "  [1/3] 按真实路径导入到临时目录 …"
  if ! GENKS_ROOT="$root" bash "${BASH_SOURCE[0]}" --import "$src" >"$root/import.log" 2>&1; then
    echo "  ❌ 导入失败 —— 这份备份**现在就用不了**:" >&2
    sed 's/^/       /' "$root/import.log" >&2
    echo >&2
    echo "  结论:赶紧换一份能用的。别把这份当备份。" >&2
    return 1
  fi
  echo "        ✅ 解码 / 解包 / 密码 / 密钥库读取 全部通过"

  echo "  [2/3] 核对指纹 …"
  if [ -f "$MANIFEST" ]; then
    cp "$MANIFEST" "$root/signing-manifest.txt"
    GENKS_ROOT="$root" bash "${BASH_SOURCE[0]}" --manifest >"$root/mf.log" 2>&1
    local mrc=$?
    sed 's/^/       /' "$root/mf.log"
    if [ "$mrc" != 0 ]; then
      echo >&2
      echo "  ❌ 能导入,但**指纹和本仓库记录的不是同一把** —— 这份不是发布用的那份。" >&2
      echo "     用它发布 = 老用户升不了级。先搞清楚哪一份才是对的。" >&2
      return 1
    fi
  else
    echo "        ⚠️  仓库里没有 signing-manifest.txt,跳过核对"
    echo "           (生成了才能挡住「导入了别的项目的凭据」:bash tools/gen-keystore.sh --manifest --write)"
  fi

  echo "  [3/3] 清理临时目录 …"
  echo "        ✅ 已删除 $root"

  if [ "${DRILL_RECORD:-0}" = 1 ] && [ -f "$MANIFEST" ]; then
    # 把「哪一份、什么时候验过」记进入库的期望值文件。
    # 目的是**让过期可见**:半年后 git log 上看到 drill.last 还是很久以前,
    # 就知道该重跑一次了 —— 而不是等到真要恢复时才发现那份早就坏了。
    local today; today="$(date '+%Y-%m-%d')"
    grep -v '^drill\.' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
    # ⚠️ 默认记的是**本地文件名**,但副本常常不在本地(飞书消息、密码管理器、U 盘)。
    #    所以支持 --label 说明「验的其实是放在哪的那一份」——
    #    否则记录会指向一个临时文件,半年后照着找只会找到空气。
      # 位置描述:优先命令行 --label,其次 GENKS_DRILL_LABEL,最后退化成文件名。
    #
    # 环境变量这条通路是给**在 WSL / Git Bash 里**用的(躲开引号麻烦):
    #     GENKS_DRILL_LABEL="飞书个人聊天(文件消息)" bash tools/gen-keystore.sh --drill f --record
    #
    # ⚠️ 它**不能**绕过 PowerShell 的问题,别搞混:
    #    PowerShell 里的 `bash` 是 WSL 启动器(C:\Windows\System32\bash.exe),
    #    它把参数拼成一条 `bash -c` 字符串重新解析 —— 引号被剥掉,括号/空格/`;`/`$()`
    #    重新获得 shell 语义(既是语法错误来源,也是注入面)。
    #    而 PowerShell 设的 `$env:X` **不会**传进 WSL(实测为空)。
    #    非 ASCII 参数还会被这层写成乱码且不报错(实测 `飞书文件消息` → `椋炰功鏂囦欢娑堟伅`)。
    #    结论:跨 Windows shell 边界时 label 用 ASCII;要中文就换 WSL/Git Bash 终端。
    local where; where="${DRILL_LABEL:-${GENKS_DRILL_LABEL:-$(basename "$src")}}"
    {
      echo "drill.last=$today"
      echo "drill.where=$where"
      echo "drill.file=$(basename "$src")"
      echo "drill.size=$(wc -c <"$src" | tr -d ' ')"
    } >> "$MANIFEST"
    echo
    echo "  已记进 $(basename "$MANIFEST"):drill.last=$today  位置=$where"
    # 非 ASCII 的 label 值得多看一眼:Windows 的 PowerShell → WSL 启动器这一层
    # **不是 UTF-8**,中文参数会被写成乱码,而且**不报错** —— 只是安静地记错。
    # 实测 `--label 飞书文件消息` 记进去的是「椋炰功鏂囦欢娑堟伅」。
    # 没法可靠地自动判别乱码,所以把值单独摆出来并点名这个陷阱。
    case "$where" in
      *[!\ -~]*)
        echo "  ⚠️  上面「位置」含非 ASCII 字符 —— 请**确认它显示正确**。"
        echo "      PowerShell 传中文参数会被写成乱码且不报错(实测过);"
        echo "      跨 Windows shell 边界时 label 建议用 ASCII,或在 WSL/Git Bash 里跑。"
        ;;
    esac
    echo "  git diff 能看到 —— 提交它,以后看这个日期就知道备份多久没验过了。"
  fi

  echo
  echo "  ════ 演练通过 ════"
  echo "  这份备份能还原出**发布用的那一把**,可以在新机器上 --import。"
  echo
  echo "  但它只证明了「文件是对的」,**没证明「你以后找得到它」**。后者是流程问题:"
  echo "    · 存在一个**固定**的地方,并在 docs/06「凭据在哪」里记下位置"
  echo "    · 条目名带上仓库名和指纹前缀,以后能搜到:"
  echo "        EasyAndroid 签名凭据 (alias=release, SHA eb3bfaf6)"
  echo "    · 换个时间再跑一次这个演练 —— 通过了才算数"
  return 0
}

# 自检一份凭据包:能不能解开、里面是不是**本机这一把**。
#
# 存在理由(实测踩过):有一版 --export 因为变量名漏改,导出了一个只有头部注释、
# 正文为空的 **467 字节**文件,而命令一路报成功。存进密码管理器的就是一张废纸,
# 而且要到半年后真要恢复时才发现 —— 那时本机可能已经没有别的副本了。
# 所以导出后必须**当场解回来验一遍**:解不开或不是这一把,就删掉并报错。
verify_bundle(){
  local f="$1"
  [ -f "$f" ] || return 1
  local t
  mktmpd_tracked || return 1
  t="$TMPDIR_LAST"
  unpack_bundle "$f" "$t" >/dev/null 2>&1 || return 1
  [ -f "$t/release.jks" ] && [ -f "$t/keystore.properties" ] || return 1
  local pw al fp
  pw="$(prop_of_file "$t/keystore.properties" storePassword)"
  al="$(prop_of_file "$t/keystore.properties" keyAlias)"
  fp="$(fp_of "$t/release.jks" "$pw" "$al")"
  [ -n "$fp" ] || return 1
  [ "$fp" = "$(fingerprint)" ] || return 1
  return 0
}

cmd_export(){
  have_creds || die "还没生成凭据,先跑 bash tools/gen-keystore.sh"
  local out="${1:-$_REPO_DIR/dist/signing-bundle.b64}"
  write_bundle "$out"
  chmod 600 "$out" 2>/dev/null || true
  local fp; fp="$(fingerprint_raw)"
  echo "==> 已导出到 $out  ($(file_size "$out") bytes,权限 600)"
  echo "    指纹 $fp"
  echo
  echo "════════ 接下来(这一步不做,前面白做)════════"
  echo "  1. 把**整个文件内容**存进密码管理器,或者直接推给 GitHub:"
  echo "       bash tools/gen-keystore.sh --push-secret"
  echo "  2. 换机器/灾后恢复: bash tools/gen-keystore.sh --import <文件>"
  echo "  3. 副本目录($(dirname "$out"))是 gitignored 的构建产物目录,别当长期备份"
}

cmd_import(){
  local src="${1:-}"
  [ -n "$src" ] || die "用法: bash tools/gen-keystore.sh --import <凭据包文件>"
  [ -f "$src" ] || die "找不到 $src"

  if have_creds; then
    if [ "${FORCE:-0}" != 1 ]; then
      echo "本机已有凭据,不覆盖:" >&2
      echo "  $KS" >&2; echo "  $PROPS" >&2
      echo >&2
      echo "确认要换成导入的这一份(⚠️ 换签名 = 已装机应用升不了级)就加 --force。" >&2
      exit 1
    fi
    echo "⚠️  --force:替换本机现有凭据"
  fi

  # 头部注释里记的指纹(可能没有,那就跳过核对)
  # ⚠️ 必须归一化后再比:包头部存的是 keytool 的形式(大写带冒号),
  #    而 fingerprint() 返回的是 apksigner 的形式(小写无冒号)。
  #    直接比会得出「不一致」的假警报 —— 这个坑在本文件里踩了两次,
  #    凡是拿指纹做比较的地方都必须先过这一步。
  local want_fp; want_fp="$(sed -n 's/^# SHA-256 指纹: //p' "$src" | head -1 | tr -d ':' | tr 'A-Z' 'a-z')"

  mktmpd_tracked || die "建临时目录失败"; TMPD="$TMPDIR_LAST"
  local tmpd; tmpd="$TMPD"
  # 允许「从聊天/邮件粘回来」的文本 —— 详见 bundle_extract 的说明
  unpack_bundle "$src" "$tmpd"

  mkdir -p "$KS_DIR"

  # ⚠️ **先验后写**:先拿临时目录里那份算出指纹并与包记录比对,
  # 全部通过才落盘。之前的版本是先 cp 再核对 —— 核对失败时本机凭据已经被
  # 覆盖了,而「拿错包」恰恰是这个核对要防的场景。
  local tmp_pw tmp_alias tmp_fp
  tmp_pw="$(prop_of_file "$tmpd/keystore.properties" storePassword)"
  tmp_alias="$(prop_of_file "$tmpd/keystore.properties" keyAlias)"
  tmp_fp="$(fp_of "$tmpd/release.jks" "$tmp_pw" "$tmp_alias")"
  [ -n "$tmp_fp" ] || die "包里的密钥库读不出来 —— 密码与密钥库对不上,包可能坏了。本机未做任何改动"
  if [ -n "$want_fp" ] && [ "$tmp_fp" != "$want_fp" ]; then
    die "指纹不一致!包里记的是 $want_fp,实际是 $tmp_fp。本机未做任何改动 —— 别用这份发布"
  fi

  chmod 700 "$KS_DIR" 2>/dev/null || true
  cp "$tmpd/release.jks" "$KS"
  cp "$tmpd/keystore.properties" "$PROPS"
  chmod 600 "$KS" "$PROPS" 2>/dev/null || true
  echo "==> 已还原:"
  echo "      $KS"
  echo "      $PROPS"
  [ -n "$want_fp" ] && echo "==> ✅ 指纹与包里记录的一致(已先验后写)"
  echo "      $tmp_fp"
  echo
  echo "  核对一下这就是线上发布用的那一把:"
  echo "    bash tools/gen-keystore.sh --verify-against <某个已发布的 apk>"
}

cmd_init(){
  if [ -e "$KS" ] || [ -e "$PROPS" ]; then
    if [ "${FORCE:-0}" != 1 ]; then
      echo "已存在,不覆盖:" >&2
      [ -e "$KS" ]    && echo "  $KS" >&2
      [ -e "$PROPS" ] && echo "  $PROPS" >&2
      echo >&2
      echo "想重建就加 --force —— 但那等于换签名,已装机的应用会升不了级。" >&2
      echo "只想看看现状用 --status;想备份/搬运用 --export。" >&2
      exit 1
    fi
    echo "⚠️  --force:覆盖现有密钥。已用旧签名装过的设备将无法直接升级。"
    rm -f "$KS" "$PROPS"
  fi

  # 密码:优先环境变量,否则随机生成(不打印到控制台,只落进 keystore.properties)
  local PW="${KS_PASSWORD:-}"
  if [ -z "$PW" ]; then
    PW="$(run_py -c "
import secrets, string
a = string.ascii_letters + string.digits
print(''.join(secrets.choice(a) for _ in range(28)))
" 2>/dev/null)"
  fi
  [ -n "$PW" ] || die "生成密码失败(需要 python3)。也可以 KS_PASSWORD=xxx 手动指定。"

  mkdir -p "$KS_DIR"
  chmod 700 "$KS_DIR" 2>/dev/null || true

  echo "==> 生成密钥库 $KS"
  # -dname:先不问交互,用占位信息;CN 只是给人看的,不影响签名校验
  kt -genkeypair \
    -keystore "$KS" \
    -alias "$ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10950 \
    -storepass "$PW" -keypass "$PW" \
    -dname "CN=EasyAndroid Release, OU=dev, O=EasyAndroid, L=-, ST=-, C=CN" \
    >/dev/null 2>&1 || die "keytool 生成失败。手动试一次看报错:
  $KEYTOOL -genkeypair -keystore $KS -alias $ALIAS -keyalg RSA -keysize 4096 -validity 10950"

  chmod 600 "$KS" 2>/dev/null || true

  cat > "$PROPS" <<PROPS_EOF
# release 签名配置 —— 已 gitignore,**不要提交**
# 由 tools/gen-keystore.sh 生成。各工程的 app/build.gradle.kts 会从 rootDir
# 往上找到本文件,存在才配 signingConfig(找不到时 release 产出 unsigned 包)。
#
# ⚠️ 请和 tools/keystore/release.jks 一起备份。丢了这个组合,
#    已装机的应用就永远无法升级了。
#    备份/搬运用: bash tools/gen-keystore.sh --export
#
# storeFile 相对仓库根
storeFile=tools/keystore/release.jks
storePassword=$PW
keyAlias=$ALIAS
keyPassword=$PW
PROPS_EOF
  chmod 600 "$PROPS" 2>/dev/null || true

  echo "==> 写入 $PROPS"
  echo
  cmd_status
  echo
  echo "════════ 接下来(第 1 步不做,前面白做)════════"
  echo "  1. **导出并保管凭据**(丢了 = 已装机应用永远无法升级):"
  echo "       bash tools/gen-keystore.sh --export"
  echo "     然后把这个文件存进密码管理器"
  echo "  2. 构建正式包:"
  echo "       bash tools/release-apk.sh <version>"
}

# ── 参数解析 ────────────────────────────────────────────────────────
FORCE=0; DRILL_MODE=0; DRILL_SRC=""; DRILL_RECORD=0; DRILL_LABEL=""
case "${1:-}" in
  ""|--force)  [ "${1:-}" = "--force" ] && FORCE=1; cmd_init ;;
  --status)    cmd_status ;;
  --add-alias) shift; cmd_add_alias "${1:-}" ;;
  --scan)      shift; cmd_scan "${1:-}" ;;
  --manifest)  shift
               MWANT=""
               [ "${1:-}" = "--write" ] && { MWANT="--write"; shift; }
               cmd_manifest "$MWANT" ;;
  --push-secret) shift; cmd_push_secret "${1:-}" ;;
  --verify-against) shift; cmd_verify "${1:-}" ;;
  --export)    cmd_export "${2:-}" ;;
  --import)    shift; [ "${1:-}" = "--force" ] && { FORCE=1; shift; }; cmd_import "${1:-}" ;;
  # ⚠️ --drill 的参数**先收集、循环结束后再执行**,不要在 case 里直接调。
  #    踩过:写成 `cmd_drill "$1" "$2"` 时,--label 和它的值(第 3、4 个参数)
  #    在 case 里就被丢掉了,`--label` 静默失效 —— 命令成功、记录却是错的。
  # ⚠️ 这个 case 只看 $1(不是 while 循环),所以 --drill 后面的参数必须
  #    在这里**自己消费完**,否则 `--record` / `--label` 会被静默忽略 ——
  #    命令成功、记录却没写(这个"静默什么都没做"的坑在参数解析上踩了第三次)。
  --drill)     shift; DRILL_MODE=1
               while [ $# -gt 0 ]; do
                 case "$1" in
                   --record) DRILL_RECORD=1 ;;
                   --label)  shift; DRILL_LABEL="${1:-}"
            # `--label @文件` 从文件读(内容按 UTF-8 解)。
            # 用途:某些 shell 边界传不了中文(实测 Windows PowerShell → WSL
            # 启动器会把中文参数写成乱码且不报错),而路径是 ASCII 的,
            # 于是把中文放进文件、命令行只传路径 —— 绕开那层编码转换。
            case "$DRILL_LABEL" in
              @?*) DRILL_LABEL="$(cat "${DRILL_LABEL#@}" 2>/dev/null | head -1 | tr -d '\r')" ;;
            esac ;;
                   *)        [ -z "$DRILL_SRC" ] && DRILL_SRC="$1" ;;
                 esac
                 shift
               done ;;
  -h|--help)   sed -n '3,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *)           die "未知参数: $1(看 --help)" ;;
esac
  # ⚠️ 退出码必须**显式接住再原样退出**。踩过两次:
  #   1) 写成 `[ ... ] && cmd_drill` —— 条件为假时整个脚本以 1 退出,
  #      于是 --import / --export / --status 全都"失败"。
  #   2) 改成 if 之后,条件为假时 if 返回 0 —— **把上面 case 的失败悄悄吞掉**:
  #      --scan 发现额外密钥副本时返回 1,脚本却 exit 0,于是 verify-all 报 ✅。
  # 教训:在脚本末尾加任何命令之前,先想清楚它会不会改写 $?。
  RC=$?
  if [ "${DRILL_MODE:-0}" = 1 ]; then
    cmd_drill
    RC=$?
  fi
  exit "$RC"
