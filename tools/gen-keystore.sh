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
#   bash tools/gen-keystore.sh --verify-against <apk>  # 确认本机密钥和某个已发布 APK 是同一把
#   bash tools/gen-keystore.sh --export [文件]    # 导出自包含的 base64 凭据包(备份/搬运/喂 CI)
#   bash tools/gen-keystore.sh --push-secret [owner/repo]  # 把凭据包直接写进仓库的 Actions secret
#   bash tools/gen-keystore.sh --import <文件>    # 从凭据包还原(换机器 / 灾后恢复)
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

KS_DIR="$_REPO_DIR/tools/keystore"
KS="$KS_DIR/release.jks"
PROPS="$_REPO_DIR/keystore.properties"
ALIAS="release"

die(){ echo "!! $*" >&2; exit 1; }
have_creds(){ [ -f "$KS" ] && [ -f "$PROPS" ]; }

# 临时目录用**全局变量** + 单一 EXIT trap。
# 踩过:写成函数内的 `local tmpd` + `trap 'rm -rf "$tmpd"'`,函数返回后 local 已销毁,
# 脚本退出时 trap 再引用它就报 “tmpd: unbound variable”(配合 set -u)。
TMPD=""
trap 'rm -rf "${TMPD:-}"' EXIT

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
  echo "  ⚠️ 本机的必须是线上发布用的**同一把**。核对方法:拿任意一个 Release 附件比指纹"
  echo "       bash tools/gen-keystore.sh --verify-against <某个已发布的 apk>"
  echo "     返回 ✅ 才是同一把。见 docs/06「签名凭据」"
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

  TMPD="$(mktmpd)" || die "建临时目录失败"
  cp "$KS" "$TMPD/release.jks"
  cp "$PROPS" "$TMPD/keystore.properties"
  ( cd "$TMPD" && tar czf bundle.tgz release.jks keystore.properties ) || die "打包失败"

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
    base64 < "$TMPD/bundle.tgz" | tr -d '\n'
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
  TMPD="$(mktmpd)" || die "建临时目录失败"
  local tmpf="$TMPD/bundle.b64"
  write_bundle "$tmpf"

  echo "==> 写入 $repo 的 Actions secret: KEYSTORE_B64  ($(file_size "$tmpf") bytes)"
  # 重定向由 bash 做(本地 POSIX 路径),gh 从 stdin 读 —— 不需要 winpath
  local out rc
  out="$("$GH" secret set KEYSTORE_B64 --repo "$repo" < "$tmpf" </dev/null 2>&1)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'
  [ "$rc" = 0 ] || die "gh secret set 失败(exit $rc;需要 repo 权限,仓库必须是你的)"

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

  TMPD="$(mktmpd)" || die "建临时目录失败"
  local tmpd; tmpd="$TMPD"
  # 去掉以 # 开头的头部注释行,其余就是 base64
  sed '/^#/d' "$src" | tr -d '\r\n' | base64 -d > "$tmpd/bundle.tgz" 2>/dev/null \
    || die "base64 解码失败 —— 文件是不是被改坏了?"
  ( cd "$tmpd" && tar xzf bundle.tgz ) || die "解包失败 —— 文件不完整?"
  [ -f "$tmpd/release.jks" ] && [ -f "$tmpd/keystore.properties" ] \
    || die "包里缺文件(release.jks / keystore.properties)"

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
FORCE=0
case "${1:-}" in
  ""|--force)  [ "${1:-}" = "--force" ] && FORCE=1; cmd_init ;;
  --status)    cmd_status ;;
  --add-alias) shift; cmd_add_alias "${1:-}" ;;
  --push-secret) shift; cmd_push_secret "${1:-}" ;;
  --verify-against) shift; cmd_verify "${1:-}" ;;
  --export)    cmd_export "${2:-}" ;;
  --import)    shift; [ "${1:-}" = "--force" ] && { FORCE=1; shift; }; cmd_import "${1:-}" ;;
  -h|--help)   sed -n '3,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *)           die "未知参数: $1(看 --help)" ;;
esac
