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
#   # CI 用(见 .github/workflows/release.yml):
#   bash tools/release-apk.sh <version> --in-place --create-release --upload
#     --in-place       不用 worktree,直接在当前检出上构建。会强制校验 HEAD == tag,
#                      因为它假定「你已经处在那个提交」—— 本地发版别加这个。
#     --create-release Release 不存在就建(说明自动生成,见下)。
#     --notes-file <f> 用手写的说明代替自动生成。
#
#   例
#   bash tools/release-apk.sh 0.1.0 --upload
#
# Release 说明怎么来
#   优先用 docs/releases/<version>.md(想写清楚就写一份);
#   没有就自动拼:附件表 + 签名指纹 + 安装命令 + <上一个 tag>..<version> 的变更列表。
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

# ⚠️ 过 gitpath —— 理由同 release.sh:$REPO 全喂给 `git -C`,
#    而 git 在 Windows 上是原生程序,见 _common.sh 里 gitpath 的说明。
REPO="$(gitpath "$_REPO_DIR")"
DIST="$REPO/dist"

VER=""; UPLOAD=0; WITH_DEBUG=0; IN_PLACE=0; CREATE_RELEASE=0; PRINT_NOTES=0; NOTES_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --upload)         UPLOAD=1 ;;
    --with-debug)     WITH_DEBUG=1 ;;
    --in-place)       IN_PLACE=1 ;;
    --create-release) CREATE_RELEASE=1 ;;
    --print-notes)    PRINT_NOTES=1 ;;
    --notes-file)     shift; NOTES_FILE="${1:-}" ;;
    -h|--help)        sed -n '3,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                [ -z "$VER" ] && VER="$1" ;;
  esac
  shift
done

die(){ echo "!! $*" >&2; exit 1; }
step(){ printf '\n════════ %s ════════\n' "$1"; }

# ── stdout 只留给「数据」,诊断一律走 stderr ──────────────────────────
# `--print-notes` 是给 shell 重定向用的(`> notes.md`),所以**进度信息不能
# 混进 stdout**,否则说明文件的开头会是「════════ 校验 ════════」。
#
# 踩过:没有这道分离时,我拿 `--print-notes > notes.md` 生成的四个文件
# (0.3.0 / 0.4.0 / 0.4.1 / 0.4.2)带着整个构建进度被当成 Release 正文发了出去。
# 约定:stdout = 数据,stderr = 诊断。这个区分在别的脚本里也一样(见 docs/05)。
if [ "$PRINT_NOTES" = 1 ]; then
  exec 3>&1     # 把真正的 stdout 存到 fd 3
  exec 1>&2     # 之后的进度输出全部走 stderr
fi

[ -n "$VER" ] || die "用法: bash tools/release-apk.sh <version> [--upload] [--with-debug] [--in-place] [--create-release] [--notes-file <f>]"

# 仓库 slug(生成说明里的 compare 链接用)
SLUG="$(git -C "$REPO" remote get-url origin 2>/dev/null | sed 's#.*github\.com[:/]##;s#\.git$##')"

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

# ── 2. 准备构建目录 ──────────────────────────────────────────────
# 默认在 tag 处开临时 worktree 构建:工作区可能带着未提交改动 / 领先 tag 的提交,
# 那样签出来的包和 tag 对不上,而 Release 附件恰恰要能复现。
#
# CI 不需要 worktree —— tag push 时 checkout 的就是那个 tag,也没有未提交改动。
# 但那时改成**强制校验 HEAD == tag**,不能白白放松这个保证。
step "准备构建目录"
if [ "$IN_PLACE" = 1 ]; then
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$TAG_SHA" ] \
    || die "--in-place 要求 HEAD 就是 tag $VER 指向的提交
    HEAD  = $(git -C "$REPO" rev-parse --short HEAD)
    $VER = $(git -C "$REPO" rev-parse --short "$TAG_SHA")
  这是给 CI 用的(tag push 时 checkout 的就是该 tag)。本地发版请去掉 --in-place。"
  BUILD_ROOT="$REPO"
  echo "  in-place:HEAD == tag $VER,直接在当前检出上构建"
else
  # ⚠️ $WT 直接就用**混合形式**(E:/...)。它下面同时有三类消费方:
  #      · bash 自己(cd / cp / rm -rf)—— 认
  #      · git(worktree add/remove)—— git 在 Windows 上是原生程序,认
  #      · apksigner / aapt2(后面校验产物时,路径由 BUILD_ROOT 推导)——
  #        它们也是原生程序,认
  #    统一成一种形式就一处都不用再转,而 POSIX 形式只有第一类能用。
  WT="$(gitpath "$TMP")/release-$VER-$$"
  trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"' EXIT
  git -C "$REPO" worktree add --detach "$WT" "$TAG_SHA" >/dev/null 2>&1 \
    || die "创建 worktree 失败: $WT"
  BUILD_ROOT="$WT"
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
fi

# ── 3. 逐个 app 构建 ──────────────────────────────────────────────
mapfile -t APPS < <(cd "$BUILD_ROOT/apps" && ls -d */ 2>/dev/null | tr -d '/')
[ ${#APPS[@]} -gt 0 ] || die "apps/ 下没有工程"

mkdir -p "$DIST"
declare -a BUILT=()

for APP in "${APPS[@]}"; do
  step "构建 $APP (release)"
  APPDIR="$BUILD_ROOT/apps/$APP"
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
  if "$APKSIGNER" verify "$apk" >"$TMP/release-verify.log" 2>&1; then
    # ⚠️ 指纹/DN 走 apk_cert_* —— 它们**取不到就返回非 0**,不会给出空字符串。
    #    以前是就地 sed:取不到时得到 "",而下面的守护检查是
    #    `grep -qF "" manifest` —— **匹配任何非空文件** → 静默通过 + 打 ✅。
    #    一个永远不会失败的检查比没有检查更糟,它会让人以为已经守住了。
    if ! who="$(apk_cert_dn "$apk")" || ! apk_fp="$(apk_cert_fp "$apk")"; then
      echo "  ❌ $n 取不到签名证书信息 —— 无法核对「是不是同一把密钥」" >&2
      echo "     apksigner 原始输出(格式可能随 build-tools 版本变了):" >&2
      apk_cert_dump "$apk" | sed 's/^/       /' >&2
      fail=1; continue
    fi
    echo "  ✅ $n 已签名  ($who)"
  else
    echo "  ❌ $n 签名校验失败" >&2; sed 's/^/     /' "$TMP/release-verify.log" >&2; fail=1; continue
  fi


  # 4.1b 签名必须是仓库认得的那把
  # signing-manifest.txt 记着本仓库发布该用哪些密钥(只有指纹,不是秘密)。
  # 这是防「用错密钥发版」的最后一道 —— 陌生密钥发的包,老用户装不上,
  # 新用户装的是一个“另一个应用”,以后同样升不了。
  if [ -f "$REPO/signing-manifest.txt" ]; then
    # ⚠️ 必须显式要求 apk_fp 非空 —— `grep -qF ""` 会匹配任何非空文件,
    #    空指纹会让这条守护静默通过。上面已保证非空,这里是第二道。
    if [ -n "$apk_fp" ] && grep -qF "$apk_fp" "$REPO/signing-manifest.txt"; then
      echo "  ✅ $n 的签名在 signing-manifest.txt 里记录过"
    else
      echo "  ❌ $n 的签名 **不在** signing-manifest.txt 里 —— 陌生密钥,不能发!" >&2
      echo "       该 APK ${apk_fp:0:32}..." >&2
      echo "       仓库认得:" >&2
      grep -E '^alias\.' "$REPO/signing-manifest.txt" | sed 's/^/         /' >&2
      echo "       先搞清楚哪把才是对的(见 docs/06「签名凭据」)" >&2
      fail=1
    fi
  else
    echo "  ⚠️  没有 signing-manifest.txt —— 跳过「签名是不是仓库认得的」校验"
    echo "     生成一份以后就能挡住陌生密钥: bash tools/gen-keystore.sh --manifest --write"
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
    APPDIR="$BUILD_ROOT/apps/$APP"
    ( cd "$APPDIR" && run_timeout 900 ./gradlew assembleDebug \
        --no-daemon --console=plain --max-workers=2 ) > "$TMP/release-build-$APP-debug.log" 2>&1 \
      || die "$APP debug 构建失败"
    OUT="$DIST/$APP-$VER-debug.apk"
    cp "$APPDIR/app/build/outputs/apk/debug/app-debug.apk" "$OUT"
    BUILT+=("$OUT")
    echo "  $OUT  ($(file_size "$OUT") bytes)"
  done
fi

# ── 6. Release 说明 ──────────────────────────────────────────────
# --print-notes:只生成说明打到 stdout 就退出(本地预览用,不碰 GitHub)
# 优先用 docs/releases/<version>.md(想写清楚就写一份,跟着 tag 一起提交);
# 没有就自动拼。自动那份也要够用 —— 尤其要有**签名指纹**,
# 让下载的人能核对「这和已装的是不是同一个应用」。
human_size(){
  local n="$1"
  if [ "$n" -ge 1048576 ] 2>/dev/null; then
    printf '%s.%s MB' "$(( n / 1048576 ))" "$(( (n % 1048576) * 10 / 1048576 ))"
  elif [ "$n" -ge 1024 ] 2>/dev/null; then printf '%s KB' "$(( n / 1024 ))"
  else printf '%s B' "$n"; fi
}

gen_notes(){
  local ver="$1" prev="" f fp apksigner
  prev="$(git -C "$REPO" describe --tags --abbrev=0 --match='[0-9]*.[0-9]*.[0-9]*' \
          "refs/tags/$ver^" 2>/dev/null || true)"

  if [ -f "$REPO/docs/releases/$ver.md" ]; then
    cat "$REPO/docs/releases/$ver.md"; echo; echo "---"; echo
  fi

  echo "## 📦 附件"; echo
  echo "| 文件 | 大小 |"; echo "|---|---|"
  for f in "${BUILT[@]}"; do
    printf '| `%s` | %s |\n' "$(basename "$f")" "$(human_size "$(file_size "$f")")"
  done
  echo

  apksigner="$(bt_tool apksigner)"
  if [ -n "$apksigner" ]; then
    echo "签名证书 SHA-256(下载后核对,确保与已安装的版本是**同一个应用**):"; echo
    echo '```'
    local okany=0
    for f in "${BUILT[@]}"; do
      case "$f" in *-debug.apk) continue ;; esac
      if fp="$(apk_cert_fp "$f")"; then
        printf '%s  %s\n' "$fp" "$(basename "$f")"; okany=1
      else
        # 宁可写明「拿不到」,也不留一个空代码块 ——
        # 空的围栏看起来像「指纹就是空的」,比缺这一节更误导。
        printf '⚠️ 取不到 %s 的证书指纹 —— 用 tools/release-apk.sh --verify-against 核对\n' "$(basename "$f")"
      fi
    done
    [ "$okany" = 1 ] || printf '⚠️ 本次一个指纹都没取到 —— 别把这个空块当成「核对通过」\n'
    echo '```'; echo
  fi

  echo "## 安装"; echo
  echo '```bash'
  echo "# Pico 4 / 普通 Android 设备"
  echo "adb install -r <上面的 apk>"
  echo
  echo "# TCL 电视 —— 不能用 adb install(固件封了),走仓里的脚本"
  echo "bash tools/tv-install.sh <上面的 apk>"
  echo '```'; echo
  echo "> ⚠️ 如果设备上装过本仓库的 **debug** 版,要先 \`adb uninstall <applicationId>\` ——"
  echo "> release 与 debug 的签名不同,直接覆盖会报 \`INSTALL_FAILED_UPDATE_INCOMPATIBLE\`。"
  echo "> 全新设备没有这个问题。"; echo

  echo "## 本版变更"; echo
  if [ -n "$prev" ]; then
    git -C "$REPO" log --no-merges --format='- %s' "$prev..$ver" | sed '/^- $/d'
  else
    git -C "$REPO" log --no-merges --format='- %s' "$ver" | head -40
  fi
  echo
  if [ -n "$prev" ] && [ -n "$SLUG" ]; then
    echo "**完整变更**:[\`$prev...$ver\`](https://github.com/$SLUG/compare/$prev...$ver)"
    echo
  fi
  echo "---"; echo
  echo "> 本 Release 由 CI 在 tag \`$ver\` 上自动构建 —— 包来自 tag 检出的代码(**不是工作区**),"
  echo "> 并逐个校验过:已签名 / \`versionName\` == $ver / \`versionCode\` == 推导值 / 非 debuggable / 无 debug 钩子。"
}

# ── 7. 汇总 / 建 Release / 上传 ──────────────────────────────────
step "产物"
for apk in "${BUILT[@]}"; do echo "  $apk"; done

if [ "$PRINT_NOTES" = 1 ]; then
  gen_notes "$VER" >&3     # 说明走真正的 stdout(fd 3)
  exec 1>&3 3>&-
  exit 0
fi

if [ "$UPLOAD" = 1 ] || [ "$CREATE_RELEASE" = 1 ]; then
  [ -n "$GH" ] || die "找不到 gh(GitHub CLI)。装一个: https://cli.github.com/"

  step "GitHub Release $VER"
  # gh 是原生程序,不加 </dev/null 会吃掉脚本的 stdin(见 docs/05)。
  # ⚠️ 但下一行的 gh secret set 那种「从 stdin 读值」的命令绝不能加 —— 见 gen-keystore.sh。
  if "$GH" release view "$VER" --repo "$SLUG" </dev/null >/dev/null 2>&1; then
    echo "  Release 已存在"
  elif [ "$CREATE_RELEASE" = 1 ]; then
    NOTES="$(mktmp)" || die "建临时文件失败"
    if [ -n "$NOTES_FILE" ]; then
      [ -f "$NOTES_FILE" ] || die "找不到 --notes-file 指定的 $NOTES_FILE"
      cp "$NOTES_FILE" "$NOTES"
      echo "  用 --notes-file 指定的说明"
    else
      gen_notes "$VER" > "$NOTES"
      if [ -f "$REPO/docs/releases/$VER.md" ]; then
        echo "  说明来源:docs/releases/$VER.md(手写)+ 自动补的附件/安装段"
      else
        echo "  说明来源:自动生成(附件表 + 指纹 + 安装 + 变更列表)"
      fi
    fi
    "$GH" release create "$VER" --repo "$SLUG" \
      --title "$VER" --notes-file "$(winpath "$NOTES")" --verify-tag </dev/null 2>&1 | tail -3 | sed 's/^/  /' \
      || die "创建 Release 失败"
    echo "  ✅ 已建 Release"
  else
    die "GitHub 上没有 $VER 这个 release。加 --create-release 让它自动建,或先手工创建"
  fi

  if [ "$UPLOAD" = 1 ]; then
    # ⚠️ 路径必须过 winpath,不能用 win_of。
    # Windows 版 gh.exe 从 WSL 里调用时不认 /mnt/e/...,而 win_of 在 WSL 上是
    # 恒等函数 —— 直接传会报 “no matches found for /mnt/e/.../x.apk”。
    # winpath 不做平台判断,无条件转成 Windows 路径。
    declare -a WIN_FILES=()
    for apk in "${BUILT[@]}"; do WIN_FILES+=("$(winpath "$apk")"); done
    "$GH" release upload "$VER" "${WIN_FILES[@]}" --clobber </dev/null 2>&1 | tail -5 | sed 's/^/  /' \
      || die "上传失败"
    echo "  ✅ 已上传 ${#BUILT[@]} 个附件"
  fi
fi

echo
echo "完成。装机前注意:release 与 debug 签名不同,"
echo "同一台设备上从 debug 换 release 要先 adb uninstall <applicationId>。"
