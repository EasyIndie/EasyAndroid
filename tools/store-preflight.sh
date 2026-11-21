#!/usr/bin/env bash
#
# 上架前静态自检 —— 不联网、不上传,只回答「产物和资料够不够交上去」
#
# 为什么需要它
#   商店拒收的理由有一半是**机器能提前查出来的**:targetSdk 太低、包名用了
#   com.example、AAB 里没有 64 位、APK 还是 debuggable、签名不对、版本号对不上。
#   这些等到上传后才被拒,一轮就要等审核;本地先查一遍,几十秒就能定位。
#
# 用法
#   bash tools/store-preflight.sh <version>                  # 所有渠道
#   bash tools/store-preflight.sh <version> --target play    # 只看 Google Play
#   bash tools/store-preflight.sh <version> --target cn      # 只看国内商店
#   bash tools/store-preflight.sh <version> --dist dist      # 指定产物目录
#
# 输入
#   apps/<App>/publish.properties   哪几个渠道(targets=github,play,cn)
#   dist/<App>-<version>.apk        清单/签名/ABI 的事实来源(play 也要它)
#   dist/<App>-<version>.aab        play 必填
#   apps/<App>/store/play.md        人工资料清单(有 TODO: 会提示)
#   apps/<App>/store/cn.md          同上
#
# 退出码
#   0  没有 FAIL(允许有 WARN)
#   1  有 FAIL —— 别提交
#   2  用法/环境错误
#
# ⚠️ 它**不代替**商店后台校验:隐私政策、软著、备案、截图、内容分级这些
#    只能人工确认。机器能查的都在这里,查不了的写在 store/*.md 里。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

REPO="$_REPO_DIR"

# 产物级判据(版本 / 非 debuggable / debug 钩子 / 签名指纹 / AAB 结构)统一走
# EasyRelease;本脚本只保留「商店政策」这类仓库自己的判断(targetSdk 门槛、
# 渠道 ABI、商店资料 TODO)。
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/easyrelease.sh"
DIST="$REPO/dist"
VER=""
TARGET="all"

usage(){
  sed -n '3,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
die(){ echo "!! $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) shift; TARGET="${1:-}"; [ -n "$TARGET" ] || usage ;;
    --dist)   shift; DIST="${1:-}";   [ -n "$DIST" ]   || usage ;;
    -h|--help) usage ;;
    -*) die "未知参数: $1" ;;
    *)  [ -z "$VER" ] && VER="$1" || die "只接受一个 <version>(多余参数: $1)" ;;
  esac
  shift
done
[ -n "$VER" ] || usage
case "$TARGET" in play|cn|all) ;; *) die "--target 只能是 play / cn / all: $TARGET" ;; esac

# ── 门槛(可以在环境里覆盖,方便商店政策变化时不用改脚本)──────────────
# Play:2025-08-31 起新应用/更新要 target API 35;2026-08-31 起要 36。
# 这个仓库的当前时间点按 36 算。政策原文每年更新,提交前再确认一次。
PLAY_MIN_TARGET_SDK="${PLAY_MIN_TARGET_SDK:-36}"
# 国内商店没有统一标准:华为/小米新应用通常 ≥33,TV 商店更宽松。
# 取 30 作为下限,具体以目标商店后台为准。
CN_MIN_TARGET_SDK="${CN_MIN_TARGET_SDK:-30}"
MAX_APK_MB="${MAX_APK_MB:-100}"

AAPT2="$(bt_tool aapt2)"       || true
APKSIGNER="$(bt_tool apksigner)" || true
[ -n "$AAPT2" ]    || die "找不到 aapt2(需要 Android build-tools)"
[ -n "$APKSIGNER" ] || die "找不到 apksigner(需要 Android build-tools)"
# AAB 的 jarsigner 校验已交给 EasyRelease(它按 upload key 的语义判,
# 不会用 -strict 误判自签证书链)。
command -v unzip >/dev/null 2>&1 || die "找不到 unzip(读取 APK/AAB 内容需要它)"

# SemVer -> versionCode,与 build.gradle.kts / release-apk.sh 保持一致
IFS=. read -r MA MI PA <<< "$VER"
case "${MA:-}${MI:-}${PA:-}" in
  ''|*[!0-9]*) die "version 不是严格 SemVer: $VER" ;;
esac
WANT_CODE=$(( MA * 10000 + MI * 100 + PA ))

PASS=0; FAIL=0; WARN=0
ok(){   PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad(){  FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
warn(){ WARN=$((WARN+1)); printf '  ⚠️  %s\n' "$1"; }
info(){ printf '     %s\n' "$1"; }

# ── 小工具 ──────────────────────────────────────────────────────
# publish.properties 里的 targets=...;没有这个文件时按 github 算。
publish_targets(){
  local app="$1"
  local f="$REPO/apps/$app/publish.properties" v
  [ -f "$f" ] || { printf 'github'; return; }
  v="$(sed -n 's/^targets[[:space:]]*=[[:space:]]*//p' "$f" | tr -d '\r' | head -1)"
  [ -n "$v" ] || v=github
  printf '%s' "$v"
}

has_target(){
  case ",$1," in *",$2,"*) return 0 ;; esac
  return 1
}

# 列出 APK 里出现过的 ABI(不是用 sort —— Windows 的 sort.exe 会抢 PATH)
apk_abis(){
  local apk="$1" line abi out=""
  while IFS= read -r line; do
    case "$line" in
      *"lib/"*)
        abi="${line#*lib/}"; abi="${abi%%/*}"
        [ -n "$abi" ] || continue
        case " $out " in *" $abi "*) ;; *) out="$out $abi" ;; esac
        ;;
    esac
  done < <(unzip -l "$apk" 2>/dev/null)
  printf '%s' "${out# }"
}

has_word(){ case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

todo_count(){
  local f="$1" n
  [ -f "$f" ] || { printf 'MISSING'; return; }
  n="$(grep -c 'TODO:' "$f" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

# ── 逐应用检查 ──────────────────────────────────────────────────
APPS=()
for d in "$REPO"/apps/*/; do
  [ -d "$d/app" ] || continue
  APPS+=("$(basename "$d")")
done
[ ${#APPS[@]} -gt 0 ] || die "apps/ 下没有工程"

RAN=0
for APP in "${APPS[@]}"; do
  targets="$(publish_targets "$APP")"
  run_play=0; run_cn=0
  case "$TARGET" in
    play) has_target "$targets" play && run_play=1 ;;
    cn)   has_target "$targets" cn   && run_cn=1 ;;
    all)  has_target "$targets" play && run_play=1
          has_target "$targets" cn   && run_cn=1 ;;
  esac
  [ "$run_play" = 1 ] || [ "$run_cn" = 1 ] || continue
  RAN=$((RAN+1))

  echo
  echo "════════ $APP  (targets=$targets) ════════"

  APK="$DIST/$APP-$VER.apk"
  AAB="$DIST/$APP-$VER.aab"
  if [ ! -f "$APK" ]; then
    bad "缺少 $APK"
    info "先构建: bash tools/release-apk.sh $VER --format both"
    continue
  fi

  # ── 通用:清单事实(只取值,不做判定)──
  badging="$("$AAPT2" dump badging "$(win_of "$APK")" 2>/dev/null)"
  if [ -z "$badging" ]; then
    bad "aapt2 读不出 $APK 的清单(路径或文件损坏?)"
    continue
  fi
  pkg="$(badging_field "$badging" "package:" name)"
  got_ver="$(badging_field "$badging" "package:" versionName)"
  target_sdk="$(badging_field "$badging" "targetSdkVersion:" || true)"
  min_sdk="$(badging_field "$badging" "sdkVersion:" || true)"

  # 包名黑名单是商店政策,留在本地(见 docs/11);「包名是什么」由 EasyRelease 打。
  case "$pkg" in
    "")            bad "取不到包名" ;;
    com.example.*) bad "包名是 $pkg —— Google Play 和国内商店都拒收 com.example.*,必须换" ;;
  esac

  # ── 产物级判据:交给 EasyRelease(与发版、与业务仓库同一套)──
  # 它输出自己的 ✅/❌ 行,这里按行计数,保证汇总数字仍然真实。
  _er_log="$TMP/preflight-$APP.log"
  if easyrelease_verify --apk "$APK" --aab "$AAB" --app "$APP" \
       --version "$VER" --code "$WANT_CODE" > "$_er_log" 2>&1; then
    :
  else
    :
  fi
  while IFS= read -r _line; do
    case "$_line" in
      *✅*)
        case "$_line" in *完成:*) ;; *) PASS=$((PASS+1)) ;; esac
        printf '%s\n' "${_line#"${_line%%✅*}"}" | sed 's/^/  /' ;;
      *❌*) FAIL=$((FAIL+1)); printf '%s\n' "${_line#"${_line%%❌*}"}" | sed 's/^/  /' ;;
    esac
  done < "$_er_log"
  # 只有 ❌ 行不够 —— EasyRelease 整体失败但没解析到 ❌ 时也要计一次失败。
  if grep -q '::error::' "$_er_log" 2>/dev/null; then
    badge=0
    while IFS= read -r _line; do
      case "$_line" in *❌*) badge=$((badge+1)) ;; esac
    done < "$_er_log"
    [ "$badge" -gt 0 ] || { bad "EasyRelease 校验失败(日志 $_er_log)"; }
  fi

  abis="$(apk_abis "$APK")"
  if [ -z "$abis" ]; then
    info "没有 native 库(纯 JVM/Kotlin),跳过 ABI 检查"
  else
    info "ABI: $abis"
    if has_word "$abis" arm64-v8a; then ok "含 64 位(arm64-v8a)"; else bad "缺 arm64-v8a —— Play 要求 64 位"; fi
    if has_word "$abis" armeabi-v7a; then ok "含 32 位(armeabi-v7a)"; else warn "缺 armeabi-v7a —— 32 位 TV 设备装不上"; fi
  fi

  # 危险权限只提示,不判死 —— 是否合理要看应用功能。
  # ⚠️ 不用 `sed "s/...name='//"` 取:表达式里的字面单引号会穿过 MSYS2 的参数还原
  #    (见 AGENTS.md §6)。纯 bash 参数展开不跨进程。
  perms=""
  while IFS= read -r _line; do
    _line="${_line%$'\r'}"
    case "$_line" in
      "uses-permission: name='"*)
        _v="${_line#uses-permission: name=\'}"
        _v="${_v%%\'*}"
        perms="$perms $_v"
        ;;
    esac
  done <<< "$badging"
  case " $perms " in
    *" android.permission."*)
      warn "申请了系统权限:$perms —— 商店会追问用途,数据安全表单也要如实填"
      ;;
    *) info "无系统权限(只有应用自有的 signature 级权限)" ;;
  esac

  # ── Google Play ──
  if [ "$run_play" = 1 ]; then
    echo "  ── Google Play ──"
    tgt="${target_sdk:-0}"
    if _ver_ge "$tgt" "$PLAY_MIN_TARGET_SDK"; then
      ok "targetSdk=$tgt ≥ $PLAY_MIN_TARGET_SDK"
    else
      bad "targetSdk=$tgt < $PLAY_MIN_TARGET_SDK —— Play 会拒收(升级步骤见 docs/11)"
      info "当前 minSdk=$min_sdk;compileSdk/targetSdk 改完记得在真机重验"
    fi

    if [ ! -f "$AAB" ]; then
      bad "缺少 $AAB"
      info "先构建: bash tools/release-apk.sh $VER --format both"
    fi

    n="$(todo_count "$REPO/apps/$APP/store/play.md")"
    case "$n" in
      MISSING) warn "没有 apps/$APP/store/play.md —— 商店资料清单还没建" ;;
      0)       ok "store/play.md 没有 TODO" ;;
      *)       warn "store/play.md 还有 $n 个 TODO(隐私政策/截图/说明等)" ;;
    esac
  fi

  # ── 国内商店 ──
  if [ "$run_cn" = 1 ]; then
    echo "  ── 国内商店 ──"
    tgt="${target_sdk:-0}"
    if _ver_ge "$tgt" "$CN_MIN_TARGET_SDK"; then
      ok "targetSdk=$tgt ≥ $CN_MIN_TARGET_SDK"
    else
      bad "targetSdk=$tgt < $CN_MIN_TARGET_SDK"
    fi

    if [ -n "$abis" ]; then
      if has_word "$abis" armeabi-v7a; then
        ok "含 armeabi-v7a(TCL 等 32 位 TV 可装)"
      else
        bad "缺 armeabi-v7a —— 32 位 TV 商店会拒"
      fi
    fi

    size="$(file_size "$APK")"
    limit=$(( MAX_APK_MB * 1048576 ))
    if [ "$size" -le "$limit" ] 2>/dev/null; then
      ok "APK $((${size:-0} / 1048576)) MB ≤ ${MAX_APK_MB} MB"
    else
      warn "APK $((${size:-0} / 1048576)) MB > ${MAX_APK_MB} MB —— 部分商店会拒"
    fi

    n="$(todo_count "$REPO/apps/$APP/store/cn.md")"
    case "$n" in
      MISSING) warn "没有 apps/$APP/store/cn.md —— 商店资料清单还没建" ;;
      0)       ok "store/cn.md 没有 TODO" ;;
      *)       warn "store/cn.md 还有 $n 个 TODO(软著/备案/隐私政策等)" ;;
    esac
  fi
done

echo
echo "════════════════ 汇总 ════════════════"
printf '  通过 %d  失败 %d  警告 %d\n' "$PASS" "$FAIL" "$WARN"
if [ "$RAN" = 0 ]; then
  echo "  没有应用声明 --target $TARGET(看 apps/*/publish.properties 的 targets=)"
fi
echo
if [ "$FAIL" -gt 0 ]; then
  echo "有硬阻塞,别提交。技术项修完再跑一次;人工项看 apps/*/store/*.md"
  exit 1
fi
echo "技术项通过。人工项(隐私政策/软著/备案/截图)在 apps/*/store/*.md 里逐条确认。"
exit 0
