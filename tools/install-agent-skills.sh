#!/usr/bin/env bash
#
# 把本仓库维护的 Android Agent Skills 安装到「用户级」或「项目级」技能目录。
#
# 目标目录默认是 ~/.agents/skills —— Agent Skills 的标准位置，Codex / pi /
# VS Code Copilot / Cursor 都会发现它。因此装一次，这台机器上的所有 Android
# 项目都能用，不需要每个项目重复拷贝。
#
# 用法：
#   bash tools/install-agent-skills.sh                  # 默认 profile=core -> ~/.agents/skills
#   bash tools/install-agent-skills.sh --profile tv     # 电视相关集合
#   bash tools/install-agent-skills.sh --profile all    # 全部（会占较多上下文）
#   bash tools/install-agent-skills.sh --agent claude   # 额外装到 ~/.claude/skills
#   bash tools/install-agent-skills.sh --agent all      # 配置里的所有 agent
#   bash tools/install-agent-skills.sh --scope project --project /path/to/app
#   bash tools/install-agent-skills.sh --target /custom/skills/dir
#   bash tools/install-agent-skills.sh --check           # 只检查，不写任何东西
#   bash tools/install-agent-skills.sh --uninstall       # 移除本脚本管理的链接/副本
#   bash tools/install-agent-skills.sh --list            # 列出 profile / agent
#
# 配置：.agents/skills.config.json（profile、agent 路径、默认 scope/模式都在里面）
# 校验：bash tools/verify-all.sh --skills-only
#
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

REPO="$_REPO_DIR"
CFG_PY="$(pyfile "$_TOOLS_DIR/skills_config.py")"
[ -n "$PY" ] || { echo '!! python3 缺失：技能配置解析需要 python3' >&2; exit 1; }
PROFILE=""
AGENTS_ARG=""
TARGET=""
SCOPE=""
PROJECT=""
MODE=""
FORCE=0
DRY=0
CHECK=0
LIST=0
UNINSTALL=0

usage(){
  cat <<'EOF'
把本仓库维护的 Android Agent Skills 安装到「用户级」或「项目级」技能目录。

目标目录默认是 ~/.agents/skills —— Agent Skills 的标准位置，Codex / pi /
VS Code Copilot / Cursor 都会发现它。因此装一次，这台机器上的所有 Android
项目都能用，不需要每个项目重复拷贝。

用法：
  bash tools/install-agent-skills.sh                  # 默认 profile=core -> ~/.agents/skills
  bash tools/install-agent-skills.sh --profile tv     # 电视相关集合
  bash tools/install-agent-skills.sh --profile all    # 全部（会占较多上下文）
  bash tools/install-agent-skills.sh --agent claude   # 额外装到 ~/.claude/skills
  bash tools/install-agent-skills.sh --agent all      # 配置里的所有 agent
  bash tools/install-agent-skills.sh --scope project --project /path/to/app
  bash tools/install-agent-skills.sh --target /custom/skills/dir
  bash tools/install-agent-skills.sh --check           # 只检查，不写任何东西
  bash tools/install-agent-skills.sh --uninstall       # 移除本脚本管理的链接/副本
  bash tools/install-agent-skills.sh --list            # 列出 profile / agent

配置：.agents/skills.config.json（profile、agent 路径、默认 scope/模式都在里面）
校验：bash tools/verify-all.sh --skills-only
EOF
}

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
note(){ printf '   %s\n' "$*"; }

# 统一去掉 Windows python 输出里的 CR（Windows 原生 python 的 stdout 是 CRLF）。
cfg(){
  run_py "$CFG_PY" "$@" | tr -d '\r'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   PROFILE="${2:-}"; shift 2 ;;
    --agent|--agents) AGENTS_ARG="${2:-}"; shift 2 ;;
    --target)    TARGET="${2:-}"; shift 2 ;;
    --scope)     SCOPE="${2:-}"; shift 2 ;;
    --project)   PROJECT="${2:-}"; shift 2 ;;
    --copy)      MODE=copy; shift ;;
    --link)      MODE=link; shift ;;
    --force)     FORCE=1; shift ;;
    --dry-run)   DRY=1; shift ;;
    --check)     CHECK=1; shift ;;
    --list)      LIST=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "未知参数：$1（--help 看用法）" ;;
  esac
done

PROFILE="${PROFILE:-$(cfg field defaultProfile)}"
SCOPE="${SCOPE:-$(cfg field scope)}"
MODE="${MODE:-$(cfg field installMode)}"
[ -n "$AGENTS_ARG" ] || AGENTS_ARG="$(cfg field defaultAgents)"

case "$SCOPE" in user|project) ;; *) die "scope 只能是 user 或 project：$SCOPE" ;; esac
case "$MODE" in auto|link|copy) ;; *) die "installMode 只能是 auto / link / copy：$MODE" ;; esac

if [ "$LIST" = 1 ]; then
  echo "profiles:"
  cfg profiles | while IFS=$'\t' read -r name desc; do
    [ -n "$name" ] || continue
    count="$(cfg skills --profile "$name" | wc -l | tr -d '[:space:]')"
    printf '  %-14s %3s  %s\n' "$name" "$count" "$desc"
  done
  echo
  echo "agents:"
  cfg agents | while IFS=$'\t' read -r name path desc; do
    [ -n "$name" ] || continue
    printf '  %-14s %-32s %s\n' "$name" "$path" "$desc"
  done
  exit 0
fi

# ── 选中的技能 ──────────────────────────────────────────────────────
SKILLS=()
while IFS= read -r skill; do
  [ -n "$skill" ] && SKILLS+=("$skill")
done < <(cfg skills --profile "$PROFILE")
[ "${#SKILLS[@]}" -gt 0 ] || die "profile $PROFILE 没有解析出任何技能"

source_of(){
  local name="$1"
  if [ -f "$REPO/.agents/skills/$name/SKILL.md" ]; then
    printf '%s' "$REPO/.agents/skills/$name"
    return 0
  fi
  return 1
}

# ── 目标目录 ────────────────────────────────────────────────────────
TARGETS=()
add_target(){
  local candidate="$1" existing
  [ -n "$candidate" ] || return 0
  for existing in "${TARGETS[@]:-}"; do
    [ "$existing" = "$candidate" ] && return 0
  done
  TARGETS+=("$candidate")
}

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    "~/"*) TARGET="$HOME/${TARGET#\~/}" ;;
  esac
  add_target "$(posix_of "$TARGET")"
else
  if [ "$SCOPE" = project ]; then
    PROJECT="${PROJECT:-$PWD}"
    [ -d "$PROJECT" ] || die "项目目录不存在：$PROJECT"
  fi
  IFS=',' read -r -a _agents <<< "$AGENTS_ARG"
  for agent in "${_agents[@]}"; do
    agent="${agent//[[:space:]]/}"
    [ -n "$agent" ] || continue
    if [ "$agent" = all ]; then
      while IFS=$'\t' read -r name _ _; do
        [ -n "$name" ] || continue
        add_target "$(posix_of "$(cfg agent-path --agent "$name" --scope "$SCOPE" --project "$(pyfile "$PROJECT")")")"
      done < <(cfg agents)
      continue
    fi
    add_target "$(posix_of "$(cfg agent-path --agent "$agent" --scope "$SCOPE" --project "$(pyfile "$PROJECT")")")"
  done
fi
[ "${#TARGETS[@]}" -gt 0 ] || die "没有目标目录（用 --agent / --target 指定）"

# ── 链接 / 副本的识别与操作 ─────────────────────────────────────────
is_link_to(){
  local dest="$1" src="$2" current
  # 不先判断 -L：Windows 的目录 junction 在部分 MSYS 版本里不被当作 symlink，
  # 但 readlink 仍然能读出目标。直接用 readlink 的结果更稳。
  current="$(readlink "$dest" 2>/dev/null || true)"
  [ -n "$current" ] || return 1
  [ "$current" = "$src" ] && return 0
  [ "$(posix_of "$current")" = "$src" ] && return 0
  return 1
}

is_managed_copy(){
  [ -f "$1/.easyandroid-skill" ]
}

remove_managed(){
  local dest="$1"
  if is_managed_copy "$dest"; then
    rm -rf "$dest"
    return 0
  fi
  if [ -L "$dest" ] || [ -n "$(readlink "$dest" 2>/dev/null || true)" ]; then
    # Windows 上的 junction 用 rmdir 摘除，避免 rm -rf 顺着链接把源目录删掉。
    if [ "$IS_WINDOWS" = 1 ] && [ -d "$dest" ]; then
      cmd //c rmdir "$(winpath "$dest")" >/dev/null 2>&1 && return 0
    fi
    rm -f "$dest"
    return 0
  fi
  return 1
}

copy_skill(){
  local src="$1" dest="$2"
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"
  printf 'repo=%s\nsource=%s\n' "$REPO" "$src" > "$dest/.easyandroid-skill"
}

link_skill(){
  local src="$1" dest="$2"
  if [ "$IS_WINDOWS" = 1 ]; then
    # 目录 junction 不需要管理员权限；先试它，避免 MSYS 把 ln -s 悄悄退化成复制。
    if cmd //c mklink /J "$(winpath "$dest")" "$(winpath "$src")" >/dev/null 2>&1; then
      return 0
    fi
  fi
  if ln -s "$src" "$dest" 2>/dev/null; then
    if [ -L "$dest" ] || [ -n "$(readlink "$dest" 2>/dev/null || true)" ]; then
      return 0
    fi
    # ln 在部分 MSYS 配置下会创建副本而不是链接 —— 清掉，交给 copy 分支。
    rm -rf "$dest" 2>/dev/null || true
  fi
  return 1
}

# ── 单个技能：安装 / 检查 / 卸载 ────────────────────────────────────
install_one(){
  local name="$1" src="$2" dest="$3"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if is_link_to "$dest" "$src"; then
      note "= $name（已链接）"
      return 0
    fi
    if is_managed_copy "$dest"; then
      [ "$DRY" = 1 ] && { note "~ $name（将刷新副本）"; return 0; }
      remove_managed "$dest" || die "无法移除旧副本：$dest"
    elif [ "$FORCE" = 1 ] && remove_managed "$dest"; then
      :
    else
      printf '!! %s 已存在，但不是本仓库安装的链接/副本：%s\n' "$name" "$dest" >&2
      printf '   先手工移走，或加 --force（只替换链接/本脚本的副本）\n' >&2
      return 1
    fi
  fi

  if [ "$DRY" = 1 ]; then
    note "+ $name -> $dest"
    return 0
  fi

  if [ "$MODE" = copy ]; then
    copy_skill "$src" "$dest"
    note "+ $name（副本）"
    return 0
  fi

  if link_skill "$src" "$dest"; then
    note "+ $name（链接）"
    return 0
  fi
  if [ "$MODE" = link ]; then
    printf '!! 无法为 %s 创建链接：%s\n' "$name" "$dest" >&2
    return 1
  fi
  copy_skill "$src" "$dest"
  note "+ $name（副本：当前环境不能建链接；更新时重跑本脚本）"
}

check_one(){
  local name="$1" src="$2" dest="$3"
  if is_link_to "$dest" "$src"; then
    note "OK   $name（链接）"
    return 0
  fi
  if is_managed_copy "$dest"; then
    note "OK   $name（副本，重跑 install 才会更新）"
    return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    note "FAIL $name（存在，但不是本仓库的链接/副本）"
  else
    note "MISS $name（未安装）"
  fi
  return 1
}

uninstall_one(){
  local name="$1" dest="$2"
  if is_link_to "$dest" "$(source_of "$name" 2>/dev/null || true)" || is_managed_copy "$dest"; then
    if [ "$DRY" = 1 ]; then
      note "- $name（将移除）"
      return 0
    fi
    if remove_managed "$dest"; then
      note "- $name"
    else
      printf '!! 无法移除：%s\n' "$dest" >&2
      return 1
    fi
  elif [ -e "$dest" ] || [ -L "$dest" ]; then
    note "SKIP $name（不是本脚本管理的，保留）"
  else
    note "SKIP $name（本来就不存在）"
  fi
}

# ── 执行 ────────────────────────────────────────────────────────────
printf '==> profile=%s，技能 %d 个\n' "$PROFILE" "${#SKILLS[@]}"
if [ "$CHECK" = 1 ]; then
  echo "==> 检查模式（不写任何文件）"
elif [ "$UNINSTALL" = 1 ]; then
  echo "==> 卸载模式"
else
  echo "==> 安装模式（$( [ "$MODE" = auto ] && echo 自动 || echo "$MODE" )）"
fi

FAILS=0
for target in "${TARGETS[@]}"; do
  echo
  echo "==> 目标：$target"
  if [ "$CHECK" = 0 ] && [ "$UNINSTALL" = 0 ] && [ "$DRY" = 0 ]; then
    mkdir -p "$target" || die "无法创建目录：$target"
  fi
  for skill in "${SKILLS[@]}"; do
    src="$(source_of "$skill")" || die "技能 $skill 在 .agents/skills/ 下不存在（profile $PROFILE 配置错了？）"
    dest="$target/$skill"
    if [ "$CHECK" = 1 ]; then
      check_one "$skill" "$src" "$dest" || FAILS=$((FAILS + 1))
    elif [ "$UNINSTALL" = 1 ]; then
      uninstall_one "$skill" "$dest" || FAILS=$((FAILS + 1))
    else
      install_one "$skill" "$src" "$dest" || FAILS=$((FAILS + 1))
    fi
  done
done

echo
if [ "$CHECK" = 1 ]; then
  if [ "$FAILS" -gt 0 ]; then
    echo "有 $FAILS 个技能未安装 / 不是本仓库管理的链接。"
    echo "修复：bash tools/install-agent-skills.sh --profile $PROFILE"
    exit 1
  fi
  echo "全部 $((${#SKILLS[@]} * ${#TARGETS[@]})) 个目标状态正常。"
elif [ "$UNINSTALL" = 1 ]; then
  [ "$FAILS" = 0 ] && echo "卸载完成。" || exit 1
else
  if [ "$FAILS" -gt 0 ]; then
    echo "有 $FAILS 个技能安装失败。"
    exit 1
  fi
  if [ "$DRY" = 1 ]; then
    echo "dry-run：以上只是计划，未写盘。"
  else
    echo "完成。重启 agent / 新建会话后会发现新技能。"
    echo "提示：Windows 上如果创建链接失败，脚本会自动退化成副本；更新后重跑本脚本即可。"
  fi
fi
