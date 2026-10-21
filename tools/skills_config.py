#!/usr/bin/env python3
"""读取 / 校验 EasyAndroid 的 Agent Skills 配置。

这个脚本只做一件事：把 `.agents/skills.config.json` 与
`.agents/skills-sources.lock.json` 解析成 shell 脚本能直接消费的形式。
安装脚本、更新脚本和 verify-all.sh 共用它，避免三处各写一份 JSON 解析。

用法（由 tools/*.sh 调用，不要求用户直接记）：
  skills_config.py field <name>
  skills_config.py profiles
  skills_config.py skills --profile <name>
  skills_config.py sources
  skills_config.py agents
  skills_config.py agent-path --agent <name> [--scope user|project] [--project DIR]
  skills_config.py scan --root <dir>
  skills_config.py lock-names
  skills_config.py write-lock --input <tsv> --output <json>
  skills_config.py validate

约定：
  * 技能目录 = `.agents/skills/<name>/SKILL.md`（只扫一层，和 Agent Skills 的发现方式一致）
  * `localSkills` 是本仓库维护的技能；其余是 sources 同步下来的上游技能，记录在 lock 里
  * 退出码非 0 表示配置或技能集不合法
"""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

REPO = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO / ".agents" / "skills"
CONFIG_PATH = REPO / ".agents" / "skills.config.json"
LOCK_PATH = REPO / ".agents" / "skills-sources.lock.json"


class ConfigError(Exception):
    pass


def read_json(path):
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise ConfigError("找不到 %s" % path)
    except json.JSONDecodeError as exc:
        raise ConfigError("%s 不是合法 JSON：%s" % (path, exc))


def load_config():
    cfg = read_json(CONFIG_PATH)
    if not isinstance(cfg, dict):
        raise ConfigError("%s 的顶层必须是对象" % CONFIG_PATH)
    return cfg


def load_lock():
    if not LOCK_PATH.exists():
        return {"version": 1, "skills": []}
    lock = read_json(LOCK_PATH)
    if not isinstance(lock, dict) or not isinstance(lock.get("skills"), list):
        raise ConfigError("%s 里缺少 skills 数组" % LOCK_PATH)
    return lock


def valid_skill_name(name):
    """技能名同时是目录名的一部分，必须限制字符集，防止上游写入 ../。"""
    return bool(re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", name or ""))


def frontmatter(path):
    """解析 SKILL.md 的 YAML 头。只支持 name / description 这类扁平字段。

    官方技能的 description 常用折行（续行缩进），这里把它们拼成一行；
    我们只需要判断非空，不做完整 YAML 解析。
    """
    text = path.read_text(encoding="utf-8", errors="replace").lstrip("\ufeff")
    match = re.match(r"^---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)", text, re.S)
    if not match:
        return {}
    data = {}
    lines = match.group(1).splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        key_match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not key_match:
            i += 1
            continue
        key, value = key_match.group(1), key_match.group(2).strip()
        if value in ("|", ">", "|-", ">-", "|+", ">+"):
            buf = []
            i += 1
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                if lines[i].strip():
                    buf.append(lines[i].strip())
                i += 1
            value = " ".join(buf)
        elif value == "":
            buf = []
            i += 1
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                if lines[i].strip():
                    buf.append(lines[i].strip())
                i += 1
            value = " ".join(buf)
        else:
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            i += 1
        data[key] = value.strip()
    return data


def skill_dirs():
    """返回 {技能名: 目录}。只看 `.agents/skills/*/SKILL.md` 这一层。"""
    result = {}
    if not SKILLS_DIR.is_dir():
        return result
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        result[skill_md.parent.name] = skill_md.parent
    return result


def all_skill_names():
    return sorted(skill_dirs())


def resolve_profile(cfg, name, stack=None):
    profiles = cfg.get("profiles") or {}
    if name not in profiles:
        raise ConfigError("配置里没有 profile：%s（可用：%s）" % (name, ", ".join(sorted(profiles))))
    stack = list(stack or [])
    if name in stack:
        raise ConfigError("profile 循环 extends：%s" % " -> ".join(stack + [name]))

    profile = profiles[name]
    if isinstance(profile, list):
        skills = list(profile)
    elif isinstance(profile, dict):
        skills = []
        parent = profile.get("extends")
        if parent:
            parents = parent if isinstance(parent, list) else [parent]
            for item in parents:
                skills.extend(resolve_profile(cfg, item, stack + [name]))
        skills.extend(profile.get("skills") or [])
    else:
        raise ConfigError("profile %s 必须是数组或对象" % name)

    available = set(all_skill_names())
    result = []
    for skill in skills:
        if skill == "*":
            candidates = sorted(available)
        else:
            candidates = [skill]
        for candidate in candidates:
            if candidate not in available:
                raise ConfigError("profile %s 引用了不存在的技能：%s" % (name, candidate))
            if candidate not in result:
                result.append(candidate)
    return result


def cmd_field(cfg, name):
    if name not in cfg:
        raise ConfigError("配置里没有字段：%s" % name)
    value = cfg[name]
    if isinstance(value, list):
        print(",".join(str(x) for x in value))
    else:
        print(value)


def cmd_profiles(cfg):
    for name, profile in (cfg.get("profiles") or {}).items():
        desc = profile.get("description", "") if isinstance(profile, dict) else ""
        print("%s\t%s" % (name, desc))


def cmd_skills(cfg, profile):
    for skill in resolve_profile(cfg, profile):
        print(skill)


def cmd_sources(cfg):
    for source in cfg.get("sources") or []:
        include = source.get("include") or ["*"]
        exclude = source.get("exclude") or []
        print("\t".join([
            source.get("id", ""),
            source.get("repository", ""),
            source.get("license", ""),
            ",".join(include),
            ",".join(exclude),
        ]))


def cmd_agents(cfg):
    for name, agent in (cfg.get("agents") or {}).items():
        print("%s\t%s\t%s" % (name, agent.get("path", ""), agent.get("description", "")))


def cmd_agent_path(cfg, agent_name, scope, project):
    agents = cfg.get("agents") or {}
    if agent_name not in agents:
        raise ConfigError("未知 agent：%s（可用：%s）" % (agent_name, ", ".join(sorted(agents))))
    rel = Path(agents[agent_name].get("path", ""))
    if rel.is_absolute():
        target = rel
    elif scope == "project":
        base = Path(project).expanduser() if project else Path.cwd()
        target = base / rel
    elif scope == "user":
        target = Path.home() / rel
    else:
        raise ConfigError("scope 只能是 user 或 project，收到：%s" % scope)
    print(target)


def cmd_scan(root):
    root_path = Path(root)
    if not root_path.is_dir():
        raise ConfigError("目录不存在：%s" % root_path)
    rows = []
    for skill_md in root_path.rglob("SKILL.md"):
        if ".git" in skill_md.parts:
            continue
        data = frontmatter(skill_md)
        name = data.get("name") or skill_md.parent.name
        if not valid_skill_name(name):
            raise ConfigError("非法技能名：%r（只允许小写字母 / 数字 / 连字符）" % name)
        rows.append((skill_md.relative_to(root_path).as_posix(), name))
    for rel, name in sorted(rows):
        print("%s\t%s" % (name, rel))


def cmd_normalize(root):
    """把上游技能里的文本文件统一成 LF。

    为什么需要：Windows 上 core.autocrlf=true 时 git clone 出来的工作树是 CRLF，
    直接复制进仓库会让同一份技能在不同平台产生整文件 diff。这里只改行尾，
    不改内容；二进制文件（含 NUL 或不是 UTF-8）原样跳过。
    """
    root_path = Path(root)
    if not root_path.is_dir():
        raise ConfigError("目录不存在：%s" % root_path)
    changed = 0
    for path in root_path.rglob("*"):
        if not path.is_file() or path.is_symlink() or ".git" in path.parts:
            continue
        data = path.read_bytes()
        if b"\x00" in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        normalized = text.replace("\r\n", "\n").replace("\r", "\n")
        if normalized != text:
            path.write_bytes(normalized.encode("utf-8"))
            changed += 1
    print(changed)


def cmd_lock_names():
    for skill in sorted(load_lock().get("skills") or [], key=lambda x: x.get("name", "")):
        print(skill.get("name", ""))


def cmd_write_lock(input_path, output_path):
    rows = []
    seen = set()
    for line in Path(input_path).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != 6:
            raise ConfigError("lock TSV 行字段数不是 6：%r" % line)
        name, source, repository, revision, path, license_name = fields
        if not valid_skill_name(name):
            raise ConfigError("lock 里有非法技能名：%r" % name)
        if name in seen:
            raise ConfigError("lock 里有重名技能：%s" % name)
        seen.add(name)
        rows.append({
            "name": name,
            "source": source,
            "repository": repository,
            "revision": revision,
            "path": path,
            "license": license_name,
        })
    payload = {"version": 1, "skills": sorted(rows, key=lambda x: x["name"].casefold())}
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if output_path:
        Path(output_path).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


def validate(cfg):
    errors = []
    warnings = []

    def err(message):
        errors.append(message)

    def warn(message):
        warnings.append(message)

    if cfg.get("version") != 1:
        err("config version 必须是 1")
    if cfg.get("scope", "user") not in ("user", "project"):
        err("scope 只能是 user 或 project")
    if cfg.get("installMode", "auto") not in ("auto", "link", "copy"):
        err("installMode 只能是 auto / link / copy")

    agents = cfg.get("agents") or {}
    if not agents:
        err("agents 不能为空")
    for name in cfg.get("defaultAgents") or []:
        if name not in agents:
            err("defaultAgents 里有未登记的 agent：%s" % name)

    local_skills = cfg.get("localSkills") or []
    if not isinstance(local_skills, list):
        err("localSkills 必须是数组")
        local_skills = []
    if len(set(local_skills)) != len(local_skills):
        err("localSkills 里有重复项")

    sources = cfg.get("sources") or []
    source_ids = set()
    if not sources:
        err("sources 不能为空（没有上游就没有自动更新）")
    for source in sources:
        sid = source.get("id", "")
        if not sid:
            err("source 缺少 id")
            continue
        if sid in source_ids:
            err("source id 重复：%s" % sid)
        source_ids.add(sid)
        if not source.get("repository"):
            err("source %s 缺少 repository" % sid)
        if not source.get("license"):
            err("source %s 缺少 license" % sid)
        if not (source.get("include") or []):
            err("source %s 的 include 不能为空（全量用 [\"*\"]）" % sid)

    dirs = skill_dirs()
    lock = load_lock()
    locked = {}
    for item in lock.get("skills") or []:
        name = item.get("name", "")
        if not name:
            err("lock 里有缺少 name 的条目")
            continue
        if name in locked:
            err("lock 里技能重名：%s" % name)
        locked[name] = item
        if not item.get("revision"):
            err("lock 技能 %s 缺少 revision" % name)
        if item.get("source") not in source_ids:
            err("lock 技能 %s 的 source 不在 config 里：%s" % (name, item.get("source")))
        if not item.get("path") or item.get("path", "").startswith("../"):
            err("lock 技能 %s 的 path 不合法：%s" % (name, item.get("path")))
        source = next((s for s in sources if s.get("id") == item.get("source")), None)
        if source:
            if item.get("repository") != source.get("repository"):
                err("lock 技能 %s 的 repository 与 config 不一致" % name)
            if item.get("license") != source.get("license"):
                err("lock 技能 %s 的 license 与 config 不一致" % name)

    for name in local_skills:
        if name in locked:
            err("本地技能 %s 不应出现在 lock 里（lock 只记录上游技能）" % name)
        if name not in dirs:
            err("本地技能 %s 缺少目录 .agents/skills/%s/SKILL.md" % (name, name))

    registered = set(local_skills) | set(locked)
    for name in sorted(registered - set(dirs)):
        err("已登记但目录不存在：.agents/skills/%s/SKILL.md" % name)
    for name in sorted(set(dirs) - registered):
        err("未登记的技能目录：.agents/skills/%s（本地技能请加进 localSkills，上游技能请跑 update-agent-skills.sh）" % name)

    for name, path in sorted(dirs.items()):
        if not valid_skill_name(name):
            err("非法技能目录名：%s（只允许小写字母 / 数字 / 连字符）" % name)
        skill_md = path / "SKILL.md"
        data = frontmatter(skill_md)
        if data.get("name") != name:
            err("%s 的 frontmatter name=%r，必须等于目录名 %r" % (skill_md, data.get("name"), name))
        if not data.get("description"):
            err("%s 缺少非空 description" % skill_md)
        if name in locked:
            licenses = list(path.glob("LICENSE*"))
            if not licenses:
                err("上游技能 %s 缺少 LICENSE 文件（复制上游许可证是合规要求）" % name)

    profiles = cfg.get("profiles") or {}
    if cfg.get("defaultProfile") not in profiles:
        err("defaultProfile 指向不存在的 profile：%s" % cfg.get("defaultProfile"))
    for profile_name in profiles:
        try:
            selected = resolve_profile(cfg, profile_name)
        except ConfigError as exc:
            err(str(exc))
            continue
        if not selected:
            err("profile %s 是空的" % profile_name)
        unknown = [x for x in selected if x not in registered]
        if unknown:
            err("profile %s 引用了未登记技能：%s" % (profile_name, ", ".join(unknown)))

    for message in warnings:
        print("WARN  %s" % message)
    for message in errors:
        print("ERROR %s" % message)
    if errors:
        print("技能集校验失败：%d 个错误（%d 个上游 + %d 个本地技能）" % (len(errors), len(locked), len(local_skills)))
        return 1
    print("OK    技能集有效：%d 个技能（%d 个上游 + %d 个本地），%d 个 profile" % (
        len(dirs), len(locked), len(local_skills), len(profiles)))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("field")
    p.add_argument("name")

    sub.add_parser("profiles")

    p = sub.add_parser("skills")
    p.add_argument("--profile", required=True)

    sub.add_parser("sources")
    sub.add_parser("agents")
    sub.add_parser("lock-names")

    p = sub.add_parser("normalize")
    p.add_argument("--root", required=True)

    p = sub.add_parser("agent-path")
    p.add_argument("--agent", required=True)
    p.add_argument("--scope", default="user", choices=["user", "project"])
    p.add_argument("--project", default="")

    p = sub.add_parser("scan")
    p.add_argument("--root", required=True)

    p = sub.add_parser("write-lock")
    p.add_argument("--input", required=True)
    p.add_argument("--output", default="")

    sub.add_parser("validate")

    args = parser.parse_args()
    try:
        cfg = load_config()
        if args.command == "field":
            cmd_field(cfg, args.name)
        elif args.command == "profiles":
            cmd_profiles(cfg)
        elif args.command == "skills":
            cmd_skills(cfg, args.profile)
        elif args.command == "sources":
            cmd_sources(cfg)
        elif args.command == "agents":
            cmd_agents(cfg)
        elif args.command == "agent-path":
            cmd_agent_path(cfg, args.agent, args.scope, args.project)
        elif args.command == "scan":
            cmd_scan(args.root)
        elif args.command == "lock-names":
            cmd_lock_names()
        elif args.command == "normalize":
            cmd_normalize(args.root)
        elif args.command == "write-lock":
            cmd_write_lock(args.input, args.output)
        elif args.command == "validate":
            return validate(cfg)
    except ConfigError as exc:
        print("ERROR %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
