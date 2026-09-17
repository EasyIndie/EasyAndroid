#!/usr/bin/env bash
#
# 生成 release 签名密钥(一次性)
#
# 为什么要签名
#   AGP 产出的 `app-release-unsigned.apk` **装不上设备** —— Android 拒绝安装未签名的包。
#   要发「正式版 APK」就必须有一份 release 签名密钥。
#
# ⚠️ 两个后果必须先想清楚
#
#   1. **丢了就再也升不了级。** Android 用签名判定「是不是同一个应用」。
#      密钥一丢,已装机的用户永远无法更新,只能卸载重装(数据全丢)。
#      → 跑完请把 tools/keystore/release.jks 和仓库根的 keystore.properties
#        一起备份到安全的地方(密码在 properties 里)。
#
#   2. **泄露了等于别人能以你的名义发版。** 两个文件都已 gitignore,
#      别 copy 进任何会被提交的目录,也别贴进聊天/issue。
#
# 用法
#   bash tools/gen-keystore.sh                 # 生成(已存在则拒绝)
#   bash tools/gen-keystore.sh --force         # 覆盖重建(⚠️ 等于换签名,老用户升不了级)
#   KS_PASSWORD=xxx bash tools/gen-keystore.sh # 指定密码(默认随机生成)
#
# 生成的东西
#   tools/keystore/release.jks     密钥库(已 gitignore)
#   keystore.properties            密码与别名(已 gitignore),各工程构建时向上查找它
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

KS_DIR="$_REPO_DIR/tools/keystore"
KS="$KS_DIR/release.jks"
PROPS="$_REPO_DIR/keystore.properties"
ALIAS="release"

die(){ echo "!! $*" >&2; exit 1; }

# keytool 跟着 JDK 走
KEYTOOL=""
for c in "$JAVA_HOME/bin/keytool" "$(command -v keytool 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { KEYTOOL="$c"; break; }
done
[ -n "$KEYTOOL" ] || die "找不到 keytool。装 JDK 17(见 docs/01),或设好 JAVA_HOME。"

if [ -e "$KS" ] || [ -e "$PROPS" ]; then
  if [ "$FORCE" != 1 ]; then
    echo "已存在,不覆盖:" >&2
    [ -e "$KS" ]    && echo "  $KS" >&2
    [ -e "$PROPS" ] && echo "  $PROPS" >&2
    echo >&2
    echo "想重建就加 --force —— 但那等于换签名,已装机的应用会升不了级。" >&2
    exit 1
  fi
  echo "⚠️  --force:覆盖现有密钥。已用旧签名装过的设备将无法直接升级。"
  rm -f "$KS" "$PROPS"
fi

# 密码:优先环境变量,否则随机生成(不打印到控制台,只落进 keystore.properties)
PW="${KS_PASSWORD:-}"
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
"$KEYTOOL" -genkeypair \
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
echo "==> 证书信息(有效期 30 年)"
"$KEYTOOL" -list -v -keystore "$KS" -storepass "$PW" -alias "$ALIAS" 2>/dev/null \
  | grep -E '^(别名|Alias|所有者|Owner|有效期|Valid|SHA1|SHA256|签名算法|Signature algorithm)' \
  | sed 's/^/  /'
echo
echo "════════ 接下来 ════════"
echo "  1. **立刻备份这两个文件**(丢 = 以后升不了级):"
echo "       $KS"
echo "       $PROPS"
echo "  2. 构建正式包:"
echo "       bash tools/release-apk.sh <version>"
