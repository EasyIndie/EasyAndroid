#!/usr/bin/env bash
#
# 从 .agents/skills.config.json 里登记的 sources 同步 Android Agent Skills。
#
# 默认行为：克隆每个上游的默认分支，把选中的技能复制到 .agents/skills/<name>/，
# 并把每个技能对应的上游 commit 写进 .agents/skills-sources.lock.json。
# 更新是「可审计」的：diff 里能看到技能内容和锁文件 revision 的变化。
#
# 用法：
#   bash tools/update-agent-skills.sh             # 同步到当前工作树
#   bash tools/update-agent-skills.sh --dry-run   # 只检查，不写盘
#   bash tools/update-agent-skills.sh --check     # 上游有变化时退出码 1（CI/本地巡检）
#
# GitHub Actions 每周跑一次，但只创建待审 PR，不直接改 main
# （见 .github/workflows/update-agent-skills.yml）。
#
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

REPO="$_REPO_DIR"
CFG_PY="$(pyfile "$_TOOLS_DIR/skills_config.py")"
SKILLS_DIR="$REPO/.agents/skills"
LOCK="$REPO/.agents/skills-sources.lock.json"
[ -n "$PY" ] || { echo '!! python3 缺失：技能同步需要 python3' >&2; exit 1; }

CHECK=0
DRY=0

usage(){
  cat <<'EOF'
从 .agents/skills.config.json 里登记的 sources 同步 Android Agent Skills。

默认行为：克隆每个上游的默认分支，把选中的技能复制到 .agents/skills/<name>/，
并把每个技能对应的上游 commit 写进 .agents/skills-sources.lock.json。
更新是「可审计」的：diff 里能看到技能内容和锁文件 revision 的变化。

用法：
  bash tools/update-agent-skills.sh             # 同步到当前工作树
  bash tools/update-agent-skills.sh --dry-run   # 只检查，不写盘
  bash tools/update-agent-skills.sh --check     # 上游有变化时退出码 1（CI/本地巡检）

GitHub Actions 每周跑一次，但只创建待审 PR，不直接改 main
（见 .github/workflows/update-agent-skills.yml）。
EOF
}

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
note(){ printf '   %s\n' "$*"; }
cfg(){ run_py "$CFG_PY" "$@" | tr -d '\r'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   CHECK=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（--help 看用法）" ;;
  esac
done

[ -d "$SKILLS_DIR" ] || die "找不到 $SKILLS_DIR"

STAGE="$(mktmpd "$TMP/skills-update.XXXXXX")" || die "无法创建临时目录"
trap 'rm -rf "$STAGE"' EXIT

SOURCES="$STAGE/sources.tsv"
LOCK_TSV="$STAGE/lock.tsv"
: > "$LOCK_TSV"
cfg sources > "$SOURCES"
[ -s "$SOURCES" ] || die ".agents/skills.config.json 的 sources 是空的"

NEW_NAMES=()
# 不用关联数组：macOS 自带的 Bash 3.2 不支持 declare -A。
# 技能数量只有几十个，线性查重足够。
seen_has(){
  local needle="$1" item
  for item in "${NEW_NAMES[@]:-}"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

while IFS=$'\t' read -r sid repository license include exclude; do
  [ -n "$sid" ] || continue
  echo "==> 上游 $sid：$repository"
  clone="$STAGE/clone-$sid"
  run_timeout 300 git clone --quiet --depth 1 --single-branch "$repository" "$(gitpath "$clone")" \
    || die "克隆失败：$repository"
  rev="$(git -C "$(gitpath "$clone")" rev-parse HEAD | tr -d '\r')"
  [ -n "$rev" ] || die "取不到 $sid 的 commit"
  note "revision $rev"

  scan="$STAGE/scan-$sid.tsv"
  cfg scan --root "$(pyfile "$clone")" > "$scan"
  [ -s "$scan" ] || die "$sid 里没有找到任何 SKILL.md"

  while IFS=$'\t' read -r name rel; do
    [ -n "$name" ] || continue
    if [ "$include" != "*" ]; then
      case ",$include," in
        *",$name,"*) ;;
        *) continue ;;
      esac
    fi
    case ",$exclude," in
      *",$name,"*) continue ;;
    esac
    if seen_has "$name"; then
      die "上游技能重名：$name（来源 $sid）"
    fi
    NEW_NAMES+=("$name")

    src="$clone/$(dirname "$rel")"
    [ -f "$src/SKILL.md" ] || die "技能目录没有 SKILL.md：$src"
    rel_dir="${rel%/SKILL.md}"

    if [ "$CHECK" = 0 ] && [ "$DRY" = 0 ]; then
      target="$STAGE/vendor/$name"
      mkdir -p "$target"
      cp -R "$src/." "$target/"
      rm -rf "$target/.git"
      # Windows 的 core.autocrlf=true 会把 clone 出来的工作树变成 CRLF；
      # 统一成 LF，避免同一份技能在不同平台产生整文件 diff。
      cfg normalize --root "$(pyfile "$target")" >/dev/null
      if ! compgen -G "$target/LICENSE*" >/dev/null; then
        lic=""
        for cand in "$clone/LICENSE.txt" "$clone/LICENSE" "$clone/LICENSE.md"; do
          [ -f "$cand" ] && { lic="$cand"; break; }
        done
        [ -n "$lic" ] || die "$name 在上游没有许可证文件，不能复制"
        cp "$lic" "$target/"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$sid" "$repository" "$rev" "$rel_dir" "$license" >> "$LOCK_TSV"
  done < "$scan"
done < "$SOURCES"

[ "${#NEW_NAMES[@]}" -gt 0 ] || die "没有从上游选中任何技能（检查 include / exclude）"
cfg write-lock --input "$(pyfile "$LOCK_TSV")" --output "$(pyfile "$STAGE/lock.json")"

if [ "$CHECK" = 1 ]; then
  if [ -f "$LOCK" ] && cmp -s "$STAGE/lock.json" "$LOCK"; then
    echo "已是最新：${#NEW_NAMES[@]} 个上游技能与 lock 一致。"
    exit 0
  fi
  echo "上游有变化：lock 与上游默认分支不一致。"
  echo "本地同步：bash tools/update-agent-skills.sh"
  exit 1
fi

if [ "$DRY" = 1 ]; then
  echo "dry-run：将同步 ${#NEW_NAMES[@]} 个上游技能（未写盘）。"
  exit 0
fi

# 落盘前先确认每个技能都完整，避免把半份上游内容换进工作树。
for name in "${NEW_NAMES[@]}"; do
  [ -f "$STAGE/vendor/$name/SKILL.md" ] || die "同步失败：$name 缺少 SKILL.md"
  compgen -G "$STAGE/vendor/$name/LICENSE*" >/dev/null || die "同步失败：$name 缺少 LICENSE"
done

# 本地技能不能被上游同名技能顶掉。
while IFS= read -r local_name; do
  [ -n "$local_name" ] || continue
  if seen_has "$local_name"; then
    die "本地技能与上游重名：$local_name（改上游 include/exclude，或给本地技能改名）"
  fi
done < <(cfg field localSkills | tr ',' '\n')

# 删掉上次 lock 里记录、这次上游已经取消的技能。
old_lock_names="$(cfg lock-names 2>/dev/null || true)"
if [ -n "$old_lock_names" ]; then
  while IFS= read -r old_name; do
    [ -n "$old_name" ] || continue
    keep=0
    for name in "${NEW_NAMES[@]}"; do
      [ "$name" = "$old_name" ] && { keep=1; break; }
    done
    if [ "$keep" = 0 ] && [ -d "$SKILLS_DIR/$old_name" ]; then
      echo "   - 移除上游已取消的技能：$old_name"
      rm -rf "$SKILLS_DIR/$old_name"
    fi
  done <<< "$old_lock_names"
fi

for name in "${NEW_NAMES[@]}"; do
  target="$SKILLS_DIR/$name"
  rm -rf "$target"
  mv "$STAGE/vendor/$name" "$target"
done

mv "$STAGE/lock.json" "$LOCK"
echo
echo "已同步 ${#NEW_NAMES[@]} 个上游技能；lock 已更新。"
echo "复核：bash tools/verify-all.sh --skills-only"
