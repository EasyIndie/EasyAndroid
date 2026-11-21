#!/usr/bin/env bash
#
# 把本仓库的发版校验委托给 EasyRelease(公共发布库)—— 校验逻辑只留一份。
#
# 为什么要有这一层
#   release-apk.sh / store-preflight.sh 以前各自实现了一遍「读 badging、比版本、
#   查 debuggable、扫 debug 钩子、apksigner 指纹、jarsigner 验 AAB」。同一套逻辑
#   在 EasyRelease 也有一份,而且已经出现漂移(那边修了 `grep -q` + pipefail
#   的假阴性,这边还在踩)。现在这里只做**适配**:把本仓库的约定(签名清单格式、
#   要拦的 debug 钩子)翻译成 EasyRelease 的输入。
#
# EasyRelease 在哪儿
#   1) $EASYRELEASE_DIR(指向一份检出,调试/离线时用)
#   2) .tmp/easyrelease/<tag>(不存在就浅克隆一次;.tmp/ 已在 .gitignore)
#
# 用法
#   bash tools/easyrelease.sh verify --apk dist/App-0.1.0.apk --app Demo \
#        --version 0.1.0 --code 100 [--aab dist/App-0.1.0.aab]
#        [--require-abis arm64-v8a,armeabi-v7a] [--min-target-sdk 36]
#
#   # 被其它脚本 source 时可用:
#   easyrelease_verify --apk ... --app ... --version ... || fail=1
#
# 退出码:0 全部通过;非 0 有检查项失败(❌ 会原样打出来)。
#
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

_gitpath_from_common(){ gitpath "$_REPO_DIR"; }

# 基座只导出 _REPO_DIR(posix);这里给本脚本一个短名字。git 是原生程序,
# 传路径前要过 gitpath —— 与 release.sh / release-apk.sh 一致。
REPO="$(_gitpath_from_common)"
EASYRELEASE_TAG="${EASYRELEASE_TAG:-android-v0.3.0}"
EASYRELEASE_REPO_URL="${EASYRELEASE_REPO_URL:-https://github.com/EasyIndie/EasyRelease.git}"
EASYRELEASE_CACHE="$REPO/.tmp/easyrelease"

# EasyRelease 检出目录;必要时空克隆一次。
easyrelease_home(){
  local dir
  if [ -n "${EASYRELEASE_DIR:-}" ]; then
    dir="$EASYRELEASE_DIR"
    [ -f "$dir/android/scripts/main.sh" ] \
      || { echo "!! EASYRELEASE_DIR 不像 EasyRelease 检出:$dir" >&2; return 1; }
    printf '%s' "$dir"
    return 0
  fi

  dir="$EASYRELEASE_CACHE/$EASYRELEASE_TAG"
  if [ -f "$dir/android/scripts/main.sh" ]; then
    printf '%s' "$dir"
    return 0
  fi

  mkdir -p "$EASYRELEASE_CACHE"
  echo "==> 拉取 EasyRelease@$EASYRELEASE_TAG 到 $dir(只需一次)" >&2
  rm -rf "$dir"
  if ! run_timeout 180 git clone --quiet --depth 1 --branch "$EASYRELEASE_TAG" \
       "$EASYRELEASE_REPO_URL" "$dir" >&2; then
    echo "!! 拉取 EasyRelease 失败。离线时请先克隆一份并设 EASYRELEASE_DIR=<路径>" >&2
    return 1
  fi
  printf '%s' "$dir"
}

# 从 signing-manifest.txt 取某个应用期望的证书指纹。
# 格式:app.<AppName>=<alias> 与 alias.<alias>=<sha256>
easyrelease_expected_fp(){
  local app="$1" manifest="$REPO/signing-manifest.txt" alias fp
  [ -f "$manifest" ] || return 1
  alias="$(grep -m1 "^app\.$app=" "$manifest" 2>/dev/null | cut -d= -f2-)"
  [ -n "$alias" ] || return 1
  fp="$(grep -m1 "^alias\.$alias=" "$manifest" 2>/dev/null | cut -d= -f2-)"
  [ -n "$fp" ] || return 1
  printf '%s' "$fp"
}

# Windows(Git Bash)上给 EasyRelease 注入两样东西:
#   · PATH_HELPER —— 原生工具不认 /e/... 这种 POSIX 路径
#   · apksigner shim —— apksigner 在 Windows 上是 .bat,会硬校验 JAVA_HOME;
#     直接走 `java -jar lib/apksigner.jar` 绕开
easyrelease_prepare_platform(){
  local home="$1" shim_dir helper bt jar
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
  esac
  command -v cygpath >/dev/null 2>&1 || return 0

  shim_dir="$home/.caller-shims"
  mkdir -p "$shim_dir"

  helper="$shim_dir/path-helper"
  cat > "$helper" <<HELPER
#!/usr/bin/env bash
# 由 EasyAndroid 生成:把交给原生工具的路径转成 Windows 形式。
. "$REPO/tools/_common.sh" >/dev/null 2>&1
win_of "\$1"
HELPER
  chmod +x "$helper"
  export EASYRELEASE_PATH_HELPER="$helper"

  bt="$(bt_tool apksigner 2>/dev/null)" || return 0
  jar="$(dirname "$bt")/lib/apksigner.jar"
  [ -f "$jar" ] || return 0
  [ -n "${JAVA_HOME:-}" ] || return 0
  shim="$shim_dir/apksigner"
  cat > "$shim" <<SHIM
#!/usr/bin/env bash
# 由 EasyAndroid 生成:用 java 直接跑 apksigner.jar,避开 .bat 的 JAVA_HOME 硬校验。
exec "$(win_of "${JAVA_HOME:-}")/bin/java.exe" -jar "$(win_of "$jar")" "\$@"
SHIM
  chmod +x "$shim"
  export EASYRELEASE_TOOL_APKSIGNER="$shim"
}

# easyrelease_verify [选项] —— 跑一次 EasyRelease 的 android 校验。
# 选项:--apk --aab --app --version --code --package --require-abis
#       --min-target-sdk --forbid --output-dir
easyrelease_verify(){
  local apk="" aab="" app="" ver="" code="" pkg=""
  local abis="" min_sdk="" forbid="UiDumpReceiver" out_dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --apk)             apk="${2:-}"; shift 2 ;;
      --aab)             aab="${2:-}"; shift 2 ;;
      --app)             app="${2:-}"; shift 2 ;;
      --version)         ver="${2:-}"; shift 2 ;;
      --code)            code="${2:-}"; shift 2 ;;
      --package)         pkg="${2:-}"; shift 2 ;;
      --require-abis)    abis="${2:-}"; shift 2 ;;
      --min-target-sdk)  min_sdk="${2:-}"; shift 2 ;;
      --forbid)          forbid="${2:-}"; shift 2 ;;
      --output-dir)      out_dir="${2:-}"; shift 2 ;;
      *) echo "easyrelease_verify: 未知参数 $1" >&2; return 2 ;;
    esac
  done

  [ -n "$apk" ] || [ -n "$aab" ] || { echo "easyrelease_verify: 需要 --apk 或 --aab" >&2; return 2; }

  local home fp
  home="$(easyrelease_home)" || return 1
  easyrelease_prepare_platform "$home"

  fp=""
  if [ -n "$app" ]; then
    fp="$(easyrelease_expected_fp "$app" || true)"
    [ -n "$fp" ] || echo "  ⚠️  signing-manifest.txt 里没有 app.$app / alias.*,跳过指纹核对" >&2
  fi

  out_dir="${out_dir:-$home/.out}"
  mkdir -p "$out_dir"

  EASYRELEASE_APK="$apk" \
  EASYRELEASE_AAB="$aab" \
  EASYRELEASE_EXPECTED_PACKAGE="$pkg" \
  EASYRELEASE_EXPECTED_VERSION_NAME="$ver" \
  EASYRELEASE_EXPECTED_VERSION_CODE="$code" \
  EASYRELEASE_EXPECTED_SHA256="$fp" \
  EASYRELEASE_FORBIDDEN_STRINGS="$forbid" \
  EASYRELEASE_REQUIRE_ABIS="$abis" \
  EASYRELEASE_MIN_TARGET_SDK="$min_sdk" \
  EASYRELEASE_OUTPUT_DIR="$out_dir" \
  ANDROID_HOME="${ANDROID_HOME:-}" \
    "$home/android/scripts/main.sh"
}

# 直接执行时走 CLI
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    verify) shift; easyrelease_verify "$@" ;;
    home)   easyrelease_home ;;
    *)
      sed -n '/^# 用法/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 2 ;;
  esac
fi
