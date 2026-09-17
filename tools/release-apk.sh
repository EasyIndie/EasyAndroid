#!/usr/bin/env bash
#
# 为某个版本构建「正式版 APK」,可选上传到对应的 GitHub Release
#
# 解决什么问题
#   GitHub Release 默认只有源码 zip。要挂可安装的 APK 得先解决两件事:
#     1. AGP 默认产出的 app-release-unsigned.apk **装不上设备**(Android 拒绝未签名包)
#        → 先跑一次 bash tools/gen-keystore.sh 配好签名
#     2. 产物必须来自 tag 指向的提交,不能是当前工作区
#        → 本脚本在临时 git worktree 里 checkout 该 tag 再构建,保证可复现
#
# 用法
#   bash tools/release-apk.sh <version>                  # 构建,产物落在 dist/
#   bash tools/release-apk.sh <version> --upload         # 顺便上传到 GitHub Release
#   bash tools/release-apk.sh <version> --with-debug     # 额外附上 debug 包
#
#   例
#   bash tools/release-apk.sh 0.1.0 --upload
#
# 产物
#   dist/<AppName>-<version>.apk         每个 apps/* 一个
#   dist/<AppName>-<version>-debug.apk   仅 --with-debug 时
#   (dist/ 已 gitignore —— 二进制属于 Release 附件,不入库)
#
# 与开发流程的关系
#   仓库约定:**开发和验收全程用 debug 包**(它带自截图钩子),
#   只有发版才出正式包 + 加签。本脚本是唯一会 assembleRelease 的地方,
#   而且会逐个校验产物「非 debuggable / 无 debug 钩子」—— 防止把 debug
#   包装成正式包发出去。
#
# ⚠️ 装机注意
#   release 包用你自己的密钥签名,debug 包用的是 debug.keystore,两者签名不同。
#   同一台设备上从 debug 换装 release 会报 INSTALL_FAILED_UPDATE_INCOMPATIBLE,
#   必须先 adb uninstall <applicationId>。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

REPO="$_REPO_DIR"
DIST="$REPO/dist"

VER=""; UPLOAD=0; WITH_DEBUG=0
for a in "$@"; do
  case "$a" in
    --upload)     UPLOAD=1 ;;
    --with-debug) WITH_DEBUG=1 ;;
    -h|--help)    sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            [ -z "$VER" ] && VER="$a" ;;
  esac
done

die(){ echo "!! $*" >&2; exit 1; }
step(){ printf '\n════════ %s ════════\n' "$1"; }

[ -n "$VER" ] || die "用法: bash tools/release-apk.sh <version> [--upload] [--with-debug]"

# ── 1. tag 与版本源必须对得上 ──────────────────────────────────────
step "校验"
TAG="refs/tags/$VER"
git -C "$REPO" rev-parse -q --verify "$TAG^{commit}" >/dev/null \
  || die "tag $VER 不存在。先 bash tools/tag-release.sh"
TAG_SHA="$(git -C "$REPO" rev-parse "$TAG^{commit}")"
echo "  tag $VER -> $(git -C "$REPO" rev-parse --short "$TAG^{commit}")  ($(git -C "$REPO" log -1 --format=%s "$TAG^{commit}"))"

# tag 里那份 version.properties 必须就是这个版本 —— 否则签出来名不副实
TAG_VER="$(git -C "$REPO" show "$TAG:version.properties" 2>/dev/null | sed -n 's/^version[[:space:]]*=[[:space:]]*//p' | tr -d '\r' | head -1)"
[ "$TAG_VER" = "$VER" ] || die "tag $VER 里的 version.properties 写的是 '$TAG_VER',对不上"
echo "  ✅ tag 内的 version.properties = $VER"

[ -f "$REPO/keystore.properties" ] \
  || die "没有签名配置。先跑一次: bash tools/gen-keystore.sh
   (AGP 默认产出的 app-release-unsigned.apk 装不上设备)"
echo "  ✅ 签名配置存在"

# SemVer -> versionCode,与 build.gradle.kts 里的推导保持一致
IFS=. read -r MA MI PA <<< "$VER"
WANT_CODE=$(( MA * 10000 + MI * 100 + PA ))
echo "  期望 versionCode = $WANT_CODE"

# ── 2. 在 tag 处开一个临时 worktree 构建 ──────────────────────────
# 不直接在工作区构建:工作区可能带着未提交改动 / 领先 tag 的提交,
# 那样签出来的包和 tag 对不上,而 Release 附件恰恰要能复现。
step "准备构建目录"
WT="$TMP/release-$VER-$$"
trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"' EXIT
git -C "$REPO" worktree add --detach "$WT" "$TAG_SHA" >/dev/null 2>&1 \
  || die "创建 worktree 失败: $WT"
echo "  $WT  (detached @ $(git -C "$REPO" rev-parse --short "$TAG_SHA"))"

# keystore.properties 是被 gitignore 的,worktree 里没有 —— 拷一份进去。
#
# 保留 **相对路径** 而不是改写成绝对路径:因为构建用的 build.gradle.kts 来自 **tag**,
# 不一定支持绝对 storeFile(早期版本会拼成 <worktree>/mnt/e/... 而找不到密钥)。
# 拷到 worktree 内的同一相对位置就能通用于任何 tag。代价是密钥会在 .tmp/ 下
# 有一份副本 —— 那里已 gitignore,且随 worktree 一起删。
cp "$REPO/keystore.properties" "$WT/keystore.properties" || die "拷贝 keystore.properties 失败"
mkdir -p "$WT/tools/keystore"
KS_REL="$(sed -n 's/^storeFile[[:space:]]*=[[:space:]]*//p' "$REPO/keystore.properties" | tr -d '\r' | head -1)"
[ -n "$KS_REL" ] || die "keystore.properties 里没有 storeFile="
case "$KS_REL" in
  /*|[A-Za-z]:[\\/]*) KS_SRC="$KS_REL" ;;   # 本来就是绝对路径,直接读
  *)                  KS_SRC="$REPO/$KS_REL" ;;
esac
[ -f "$KS_SRC" ] || die "找不到密钥库: $KS_SRC"
cp "$KS_SRC" "$WT/tools/keystore/release.jks" || die "拷贝密钥库失败"
echo "  已拷入 keystore.properties + $(basename "$KS_REL") (worktree 内,随它一起删)"

# ── 3. 逐个 app 构建 ──────────────────────────────────────────────
mapfile -t APPS < <(cd "$WT/apps" && ls -d */ 2>/dev/null | tr -d '/')
[ ${#APPS[@]} -gt 0 ] || die "apps/ 下没有工程"

mkdir -p "$DIST"
declare -a BUILT=()

for APP in "${APPS[@]}"; do
  step "构建 $APP (release)"
  APPDIR="$WT/apps/$APP"
  [ -f "$APPDIR/gradlew" ] || die "$APP 里没有 gradlew"

  # local.properties 是 gitignore 的,worktree 里没有,补一份
  printf 'sdk.dir=%s\n' "$ANDROID_SDK_DIR" > "$APPDIR/local.properties"

  # 有些工程的 launcher activity 与应用包名不同,统一以 applicationId 为准取产物
  ( cd "$APPDIR" && run_timeout 900 ./gradlew assembleRelease \
      --no-daemon --console=plain --max-workers=2 ) > "$TMP/release-build-$APP.log" 2>&1 \
    || { tail -25 "$TMP/release-build-$APP.log" | sed 's/^/    /' >&2
         die "$APP 构建失败(日志 $TMP/release-build-$APP.log)"; }

  # assembleRelease 可能产出 signed 或 unsigned 两种名字
  SRC=""
  for cand in "$APPDIR/app/build/outputs/apk/release/app-release.apk" \
              "$APPDIR/app/build/outputs/apk/release/app-release-signed.apk"; do
    [ -f "$cand" ] && { SRC="$cand"; break; }
  done
  if [ -z "$SRC" ]; then
    # 只有 unsigned 说明签名配置没生效
    if ls "$APPDIR"/app/build/outputs/apk/release/*unsigned*.apk >/dev/null 2>&1; then
      die "$APP 产出的是 unsigned 包 —— 签名配置没生效。检查 keystore.properties 与 app/build.gradle.kts"
    fi
    die "$APP 没找到 release 产物"
  fi

  OUT="$DIST/$APP-$VER.apk"
  cp "$SRC" "$OUT"
  BUILT+=("$OUT")
  echo "  $OUT  ($(file_size "$OUT") bytes)"
done

# ── 4. 校验产物:签名 + 版本号 ────────────────────────────────────
step "校验产物"
APKSIGNER="$(bt_tool apksigner)"
AAPT2="$(bt_tool aapt2)"
[ -n "$APKSIGNER" ] || die "找不到 apksigner(需要 build-tools)"
[ -n "$AAPT2" ]     || die "找不到 aapt2(需要 build-tools)"

fail=0
for apk in "${BUILT[@]}"; do
  n="$(basename "$apk")"
  # 4.1 签名
  if "$APKSIGNER" verify --print-certs "$apk" >"$TMP/release-verify.log" 2>&1; then
    who="$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null | sed -n 's/^Signer #1 certificate DN: //p' | head -1)"
    echo "  ✅ $n 已签名  ($who)"
  else
    echo "  ❌ $n 签名校验失败" >&2; sed 's/^/     /' "$TMP/release-verify.log" >&2; fail=1; continue
  fi
  # 4.2 版本号
  badging="$("$AAPT2" dump badging "$apk" 2>/dev/null)"
  got_ver="$(printf '%s' "$badging" | head -1 | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")"
  got_code="$(printf '%s' "$badging" | head -1 | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")"
  if [ "$got_ver" = "$VER" ] && [ "$got_code" = "$WANT_CODE" ]; then
    echo "  ✅ $n versionName=$got_ver versionCode=$got_code"
  else
    echo "  ❌ $n 版本不符: versionName=$got_ver(期望 $VER) versionCode=$got_code(期望 $WANT_CODE)" >&2
    fail=1
  fi

  # 4.3 release 包里不该有 debug 自截图钩子
  if [ "$(printf '%s' "$badging" | grep -c UiDumpReceiver)" != "0" ] \
     || [ "$("$AAPT2" dump xmltree --file AndroidManifest.xml "$apk" 2>/dev/null | grep -c UiDumpReceiver)" != "0" ]; then
    echo "  ❌ $n 里混进了 debug 钩子(UiDumpReceiver)—— 构建类型不对" >&2; fail=1
  fi

  # 4.4 正式包不能是 debuggable
  # 仓库约定:开发/验收全程用 debug 包,只有发版才出正式包。
  # debug 包在 aapt2 badging 里会多一行 application-debuggable —— 用它当机器判据,
  # 挡住「把 debug 包装成正式包发出去」。
  if printf '%s' "$badging" | grep -q 'application-debuggable'; then
    echo "  ❌ $n 是 debuggable 的 —— 这是 debug 包,不是正式包" >&2; fail=1
  else
    echo "  ✅ $n 非 debuggable(正式包)"
  fi
done
[ "$fail" = 0 ] || die "有产物没通过校验,不继续"

# ── 5. 可选:debug 包 ──────────────────────────────────────────────
if [ "$WITH_DEBUG" = 1 ]; then
  for APP in "${APPS[@]}"; do
    step "构建 $APP (debug,带自截图钩子)"
    APPDIR="$WT/apps/$APP"
    ( cd "$APPDIR" && run_timeout 900 ./gradlew assembleDebug \
        --no-daemon --console=plain --max-workers=2 ) > "$TMP/release-build-$APP-debug.log" 2>&1 \
      || die "$APP debug 构建失败"
    OUT="$DIST/$APP-$VER-debug.apk"
    cp "$APPDIR/app/build/outputs/apk/debug/app-debug.apk" "$OUT"
    BUILT+=("$OUT")
    echo "  $OUT  ($(file_size "$OUT") bytes)"
  done
fi

# ── 6. 汇总 / 上传 ────────────────────────────────────────────────
step "产物"
for apk in "${BUILT[@]}"; do echo "  $apk"; done

if [ "$UPLOAD" = 1 ]; then
  step "上传到 GitHub Release $VER"
  [ -n "$GH" ] || die "找不到 gh(GitHub CLI)。装一个,或手动上传上面的文件"
  REPO_SLUG="$(git -C "$REPO" remote get-url origin | sed 's#.*github.com[:/]##;s#\.git$##')"
  # gh 是原生程序,不加 </dev/null 会吃掉脚本的 stdin(见 docs/05)
  "$GH" release view "$VER" --repo "$REPO_SLUG" </dev/null >/dev/null 2>&1 \
    || die "GitHub 上没有 $VER 这个 release。先建: gh release create $VER --title ... --notes-file ..."

  # ⚠️ 路径必须过 winpath,不能用 win_of。
  # Windows 版 gh.exe 从 WSL 里调用时不认 /mnt/e/...,而 win_of 在 WSL 上是
  # 恒等函数 —— 直接传会报 “no matches found for /mnt/e/.../x.apk”。
  # winpath 不做平台判断,无条件转成 Windows 路径。
  declare -a WIN_FILES=()
  for apk in "${BUILT[@]}"; do WIN_FILES+=("$(winpath "$apk")"); done
  "$GH" release upload "$VER" "${WIN_FILES[@]}" --clobber </dev/null 2>&1 | tail -5 | sed 's/^/  /' \
    || die "上传失败"
  echo "  ✅ 已上传"
fi

echo
echo "完成。装机前注意:release 与 debug 签名不同,"
echo "同一台设备上从 debug 换 release 要先 adb uninstall <applicationId>。"
