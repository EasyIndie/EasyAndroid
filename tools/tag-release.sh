#!/usr/bin/env bash
#
# 打发布 tag —— 保证「tag 名 == version.properties 里的 version」永远成立
#
# 为什么需要它
#   本仓库历史上出现过 tag=0.0.1 而 APK 里 versionName=0.1.0 的漂移。
#   tag 是外部对「这一版」的引用,名字和包内版本不一致的话,
#   `git checkout <tag>` 构出来的包就不知道该叫什么。
#   脚本把这条约束变成机械检查:tag 名只能来自 version.properties。
#
# 用法
#   bash tools/tag-release.sh                 # 校验 + 构建自检 + 打 tag + 推送
#   bash tools/tag-release.sh --check         # 只校验,不改动任何东西(可放 CI)
#   bash tools/tag-release.sh --no-verify     # 跳过构建自检(已单独跑过 verify-all 时用)
#   bash tools/tag-release.sh --bump patch    # 把 version 涨一格(major|minor|patch),只改文件不打 tag
#   bash tools/tag-release.sh --force         # 覆盖已存在的同名 tag
#
#                                           ⚠️ 只在确认没人拉过那个 tag 时用。
#                                             远端会被强推(本仓库 0.0.1 就是这么修正的)。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# ⚠️ 过 gitpath:下面全是 `git -C "$REPO"`,而 git 在 Windows 上是原生程序
#    (某些环境关掉了 MSYS2 的路径自动转换)。见 _common.sh 里 gitpath 的说明。
REPO="$(gitpath "$(cd "$_TOOLS_DIR/.." && pwd)")"
VF="$REPO/version.properties"

CHECK=0; VERIFY=1; FORCE=0; BUMP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     CHECK=1 ;;
    --no-verify) VERIFY=0 ;;
    --force)     FORCE=1 ;;
    --bump)      shift; BUMP="${1:-}" ;;
    -h|--help)   sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "未知参数: $1(看 --help)" >&2; exit 2 ;;
  esac
  shift
done

die(){ echo "!! $*" >&2; exit 1; }
ok(){  printf '  ✅ %s\n' "$1"; }
bad(){ printf '  ❌ %s\n' "$1"; }

# ── SemVer:严格 MAJOR.MINOR.PATCH,不允许前导零 / 前后缀 ──
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
semver_ok(){ [[ "$1" =~ $SEMVER_RE ]]; }

read_version(){ sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$VF" 2>/dev/null | tr -d '\r' | head -1; }

write_version(){ # $1 = 新版本;只替换 version= 那一行,其余原样保留
  local tmp; tmp="$(mktmp)"
  [ -n "$tmp" ] || die "建不了临时文件($TMP 不可写)"
  sed "s|^version[[:space:]]*=.*|version=$1|" "$VF" > "$tmp" && mv "$tmp" "$VF"
}

# ── --bump:只改文件,不碰 git ──
if [ -n "$BUMP" ]; then
  cur="$(read_version)"
  semver_ok "$cur" || die "version.properties 里的 version='$cur' 不是严格 SemVer,先修好再 bump"
  IFS=. read -r MA MI PA <<< "$cur"
  case "$BUMP" in
    major) new="$((MA+1)).0.0" ;;
    minor) new="$MA.$((MI+1)).0" ;;
    patch) new="$MA.$MI.$((PA+1))" ;;
    *) die "--bump 只接受 major | minor | patch,收到 '$BUMP'" ;;
  esac
  write_version "$new"
  echo "==> version: $cur -> $new"
  echo
  echo "接下来:"
  echo "  1. 到 version.properties 的「版本历史」注释里补一行,写清这一版做了什么、为什么是"
  echo "     这个段位(major/minor/patch)"
  echo "  2. 把改动写进提交信息,然后 git commit && git push"
  echo "  3. bash tools/tag-release.sh"
  echo
  echo "⚠️ 这一串是**手工记账**。日常发版请用一条命令的那个:"
  echo "     bash tools/release.sh"
  echo "   它从提交信息推导段位,并自动写 version.properties 的历史与 CHANGELOG.md。"
  echo "   --bump 只留给「想让版本号脱离推导结果」的场合。"
  exit 0
fi

# ── 校验 ──
echo "════════ 校验 ════════"
[ -f "$VF" ] || die "找不到 $VF —— 它是本仓库版本号的唯一来源(见 docs/06)"

VER="$(read_version)"
semver_ok "$VER" || die "version='$VER' 不是严格 SemVer(MAJOR.MINOR.PATCH,不允许前导零/前后缀)。见 docs/06"
ok "version = $VER(来自 version.properties)"

# 工程里不该再有版本号字面量
if grep -rqE 'version(Name)?[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$REPO/apps" --include='*.kts' 2>/dev/null; then
  grep -rnE 'version(Name)?[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$REPO/apps" --include='*.kts' >&2
  die "apps/ 里还有硬编码的版本号 —— 应该统一从 version.properties 读(见 docs/06)"
fi
ok "apps/ 下没有硬编码版本号"

if [ "$CHECK" = 0 ]; then
  [ -z "$(git -C "$REPO" status --porcelain)" ] \
    || { git -C "$REPO" status --short >&2; die "工作区不干净。tag 必须打在已提交的状态上"; }
  ok "工作区干净"

  BR="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
  git -C "$REPO" rev-parse --verify --quiet "origin/$BR" >/dev/null \
    || die "本地分支 $BR 没有上游 origin/$BR"
  if [ "$(git -C "$REPO" rev-parse HEAD)" != "$(git -C "$REPO" rev-parse "origin/$BR")" ]; then
    die "HEAD 和 origin/$BR 不一致 —— 先 git push,否则 tag 会指向一个远端没有的提交"
  fi
  ok "已与 origin/$BR 同步"

  if git -C "$REPO" rev-parse -q --verify "refs/tags/$VER" >/dev/null; then
    [ "$FORCE" = 1 ] || die "tag $VER 已存在。要覆盖加 --force(⚠️ 确认没人拉过)"
    bad "tag $VER 已存在,将用 --force 覆盖"
  else
    ok "tag $VER 未被占用"
  fi
fi

if [ "$CHECK" = 1 ]; then
  echo
  echo "校验通过(--check 到这儿就结束,没有打 tag)。"
  exit 0
fi

# ── 构建自检:用真实产物确认 versionName 就是 $VER ──
if [ "$VERIFY" = 1 ]; then
  echo
  echo "════════ 构建自检 ════════"
  echo "  (会跑 tools/verify-all.sh --build-only,约 1~2 分钟;用 --no-verify 跳过)"
  VLOG="$TMP/tag-release-verify.log"
  if bash "$_TOOLS_DIR/verify-all.sh" --build-only > "$VLOG" 2>&1; then
    # verify-all 会先把分步骤逐条打一遍、最后在汇总里再列一遍,
    # 所以这里去重,否则屏幕上每条都是双份
    grep -E '✅|❌|⏭️' "$VLOG" | awk '!seen[$0]++' | sed 's/^/  /'
    grep -q '版本号与 version.properties 一致' "$VLOG" \
      || die "verify-all 没跑到版本号校验,看 $VLOG"
  else
    grep -E '✅|❌' "$VLOG" | tail -20 | sed 's/^/  /' >&2
    die "构建自检没过,不打 tag(日志 $VLOG)"
  fi
fi

# ── 打 tag ──
echo
echo "════════ 打 tag ════════"
MSG="$(cat <<EOF
$VER

版本号来源: version.properties(唯一来源)
APK 里的 versionName=$VER / versionCode 由 SemVer 推导
EOF
)"
if [ "$FORCE" = 1 ]; then
  git -C "$REPO" tag -a -f "$VER" -m "$MSG" || die "打 tag 失败"
  ok "已覆盖本地 tag $VER"
  git -C "$REPO" push -f origin "refs/tags/$VER" || die "推送 tag 失败"
  ok "已强推到 origin(远端引用被改写)"
else
  git -C "$REPO" tag -a "$VER" -m "$MSG" || die "打 tag 失败"
  ok "已创建本地 tag $VER"
  git -C "$REPO" push origin "refs/tags/$VER" || die "推送 tag 失败"
  ok "已推送到 origin"
fi

echo
echo "tag $VER -> $(git -C "$REPO" rev-parse --short HEAD)  ($(git -C "$REPO" log -1 --format=%s))"
