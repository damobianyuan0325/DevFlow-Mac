#!/usr/bin/env python3
"""Package reviewed, tracked DevFlow skills and public guides; never run examples."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import stat
import subprocess
import sys
from urllib.parse import unquote, urlsplit
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SKILL_FILES = (
    "skills/devflow-record/SKILL.md",
    "skills/devflow-record/agents/openai.yaml",
    "skills/devflow-record/assets/example/checks.py",
    "skills/devflow-record/assets/example/devflow-supervision.json",
    "skills/devflow-record/assets/example/feature.py",
    "skills/devflow-record/assets/example/requirements.md",
    "skills/devflow-record/assets/project-template.json",
    "skills/devflow-record/references/protocol.md",
    "skills/devflow-record/references/workflow.md",
    "skills/devflow-record/scripts/run_example.py",
    "skills/devflow-resolve/SKILL.md",
    "skills/devflow-resolve/agents/openai.yaml",
    "skills/devflow-resolve/assets/devflow-integration.example.json",
    "skills/devflow-resolve/assets/resolution.md",
    "skills/devflow-resolve/references/gated-delivery.md",
    "skills/devflow-resolve/references/integration.md",
    "skills/devflow-resolve/references/triage.md",
    "skills/devflow-resolve/references/writeback.md",
    "skills/devflow-resolve/scripts/prepare_review.py",
)
PUBLIC_FILES = (
    "LICENSE", "README.md", "AGENT_INSTALL.md", "CONTRIBUTING.md", "SECURITY.md", "VERSION", "REL_VERSION",
    "docs/USER_GUIDE.md", "docs/PRIVACY.md", "docs/CHANGELOG.md", "docs/RELEASE.md",
    "docs/releases/v0.2.0-preview.1.md", "docs/releases/v0.2.0-preview.2.md",
    "docs/releases/v0.2.0-preview.3.md", "docs/releases/v0.2.0-preview.4.md",
    "docs/VERSIONING.md", "docs/agent-quickstart.md", "docs/agent-resolution.md",
    "docs/supervision-protocol.md", "docs/PRODUCT.md", "docs/ROADMAP.md", "docs/BRAND.md",
)
MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024


def no_symlinks(path):
    path = Path(os.path.abspath(path))
    for component in (path, *path.parents):
        if component.is_symlink():
            raise ValueError(f"Symbolic links are not package inputs or outputs: {component}")
    return path


def read_regular(path):
    path = no_symlinks(path)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_FILE_BYTES:
        raise ValueError(f"Expected a regular file of at most {MAX_FILE_BYTES} bytes: {path}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    with os.fdopen(os.open(path, flags), "rb") as handle:
        opened = os.fstat(handle.fileno())
        if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise ValueError(f"Input changed while opening: {path}")
        data = handle.read(MAX_FILE_BYTES + 1)
    if len(data) > MAX_FILE_BYTES:
        raise ValueError(f"Input exceeds size limit: {path}")
    return data


def versions(root, requested=None):
    app_version = read_regular(root / "VERSION").decode("utf-8").strip()
    release = read_regular(root / "REL_VERSION").decode("utf-8").strip()
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", app_version):
        raise ValueError("VERSION must contain an X.Y.Z application version")
    match = re.fullmatch(r"((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))-preview\.([1-9]\d*)", release)
    if not match or match[1] != app_version:
        raise ValueError("REL_VERSION must be X.Y.Z-preview.N with the same X.Y.Z as VERSION")
    if requested is not None and requested != release:
        raise ValueError("--version must exactly match REL_VERSION")
    return release, app_version


def check_skill_tree(root):
    allowed = set(SKILL_FILES)
    allowed_dirs = {str(parent) for file in allowed for parent in Path(file).parents}
    for skill in ("skills/devflow-record", "skills/devflow-resolve"):
        no_symlinks(root / skill)
        if not (root / skill).is_dir():
            raise ValueError(f"Missing skill directory: {skill}")
        for directory, dirs, files in os.walk(root / skill, followlinks=False):
            for name in dirs + files:
                path = Path(directory) / name
                no_symlinks(path)
                relative = path.relative_to(root).as_posix()
                if "__pycache__" in path.parts or path.suffix in (".pyc", ".pyo"):
                    continue
                if path.is_dir() and relative not in allowed_dirs:
                    raise ValueError(f"Unexpected directory in skill: {relative}")
                if not path.is_dir() and relative not in allowed:
                    raise ValueError(f"Unexpected file in skill: {relative}")


def headings(text):
    found, counts = set(), {}
    for line in text.splitlines():
        if not re.match(r"^#{1,6}\s+", line):
            continue
        title = re.sub(r"^#{1,6}\s+|\s+#+\s*$", "", line).strip().lower()
        slug = re.sub(r"[^\w\s-]", "", title).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        found.add(slug + (f"-{count}" if count else ""))
    return found


def check_links(payload):
    """Check inline Markdown file/directory links and local heading fragments."""
    for name, data in payload.items():
        if not name.endswith(".md"):
            continue
        text = re.sub(r"(?ms)^\s*(`{3,}|~{3,}).*?^\s*\1\s*$", "", data.decode("utf-8"))
        for raw in re.findall(r"\[[^\]\n]*\]\(([^)\n]+)\)", text):
            target = raw.strip().split(' "', 1)[0].strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme in ("https", "http", "mailto"):
                continue
            if parsed.scheme or parsed.netloc or "\\" in target:
                raise ValueError(f"Unsupported link in {name}: {target}")
            path = unquote(parsed.path)
            relative = posixpath.normpath(posixpath.join(posixpath.dirname(name), path)) if path else name
            if relative.startswith("/") or relative == ".." or relative.startswith("../"):
                raise ValueError(f"Link leaves the package in {name}: {target}")
            is_directory = any(file.startswith(relative.rstrip("/") + "/") for file in payload)
            if relative not in payload and not is_directory:
                raise ValueError(f"Broken offline link in {name}: {target}")
            if parsed.fragment and relative.endswith(".md"):
                if unquote(parsed.fragment) not in headings(payload[relative].decode("utf-8")):
                    raise ValueError(f"Unknown offline heading in {name}: {target}")


def public_payload(root, release, source_revision=None):
    actual_release, app_version = versions(root, release)
    selected = (*PUBLIC_FILES, f"docs/releases/v{release}.md", *SKILL_FILES)
    if source_revision is None:
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "--verify", "HEAD"], text=True).strip()
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit):
            raise ValueError("Cannot identify the source commit")
        clean = subprocess.run(["git", "-C", str(root), "diff", "--quiet", "HEAD", "--"])
        if clean.returncode != 0:
            raise ValueError("Tracked source files differ from HEAD; freeze a clean commit before packaging")
        actual_release, app_version = versions(root, release)
        selected = (*PUBLIC_FILES, f"docs/releases/v{release}.md", *SKILL_FILES)
        query = subprocess.run(["git", "-C", str(root), "ls-files", "--stage", "-z", "--", *PUBLIC_FILES,
                                f"docs/releases/v{release}.md", "skills/devflow-record", "skills/devflow-resolve"],
                               capture_output=True, check=True)
        tracked = {}
        for entry in query.stdout.decode("utf-8").split("\0"):
            if entry:
                identity, file = entry.split("\t", 1)
                mode, _, stage = identity.split()
                if mode not in ("100644", "100755") or stage != "0":
                    raise ValueError(f"Unsupported tracked input mode or unresolved merge: {file}")
                tracked[file] = mode
        if set(tracked) != set(selected):
            raise ValueError(f"Tracked public whitelist mismatch; missing={sorted(set(selected)-set(tracked))}, extra={sorted(set(tracked)-set(selected))}")
    else:
        commit = source_revision
    check_skill_tree(root)
    payload = {file: read_regular(root / file) for file in selected}
    if sum(map(len, payload.values())) > MAX_TOTAL_BYTES:
        raise ValueError("Public package inputs exceed the 32 MiB budget")
    payload["BUILD-INFO.json"] = (json.dumps({"schemaVersion": 1, "sourceCommit": commit,
                                            "releaseVersion": actual_release, "appVersion": app_version},
                                           indent=2) + "\n").encode("utf-8")
    payload["SKILLS_README.md"] = f"""# DevFlow agent skills — {release}

本包提供两个可分别复制、由用户或获得授权的开发代理显式调用的技能：

- [devflow-record](skills/devflow-record/SKILL.md)：从一句话需求记录原话、拆解、验收、动作和实际证据。
- [devflow-resolve](skills/devflow-resolve/SKILL.md)：核对监督发现，在授权内处理并保留修复、复验和历史。

先读[代理接入指南](docs/agent-quickstart.md)、[问题处理指南](docs/agent-resolution.md)和[用户指南](docs/USER_GUIDE.md)。复制技能时保留完整目录及其 references/assets/scripts；调用方式由所用 AI 宿主决定，本包不会安装或自动启动技能。

独立技能 ZIP 不含 CLI；同版本 Mac App 内含 DevFlowEvidence，无需源码。先读[安装与接入](AGENT_INSTALL.md)，其他环境见[获取 CLI](docs/agent-quickstart.md#获取实际可用的证据工具)。gated-delivery 是可选适配，不是必需依赖。教学例子必须先复制到独立目录；打包未执行例子，也不代表用户项目验收通过。

只包含明确白名单中的公开文档和已跟踪技能，没有用户会话、工作区或私人验收日志。适用[MIT 许可证](LICENSE)；发布版本与 App 版本的区别见[版本规则](docs/VERSIONING.md)。

[BUILD-INFO.json](BUILD-INFO.json) 保存打包来源提交和两个版本标识。它不替代 App 原生验收；独立技能 ZIP 不含二进制，CLI 可从同版本 Mac App 取得。
""".encode("utf-8")
    check_links(payload)
    return payload


def output_paths(output_dir, name):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,119}", name):
        raise ValueError("Package name must be 1–120 safe filename characters")
    output = no_symlinks(output_dir)
    folder, archive, checksum = output / name, output / (name + ".zip"), output / (name + ".zip.sha256")
    for path in (folder, archive, checksum):
        if path.exists() or path.is_symlink():
            raise ValueError(f"Output already exists; refusing to overwrite: {path}")
    return folder, archive, checksum


def reserve_output(output_dir, name):
    folder, _, _ = output_paths(output_dir, name)
    folder.parent.mkdir(parents=True, exist_ok=True)
    no_symlinks(folder.parent)
    output_paths(output_dir, name)
    folder.mkdir()
    return folder


def stage_public_files(root, destination, release, source_revision=None):
    payload = public_payload(root, release, source_revision)
    for name, data in payload.items():
        target = destination / name
        no_symlinks(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as handle:
            handle.write(data)


def verify_staged_files(destination, payload):
    no_symlinks(destination)
    actual = {}
    for path in destination.rglob("*"):
        no_symlinks(path)
        if not path.is_dir():
            actual[path.relative_to(destination).as_posix()] = read_regular(path)
    if actual != payload:
        raise ValueError("Bundled integration differs from the frozen public payload; rebuild the App")


def write_archive(folder):
    folder = no_symlinks(folder)
    archive, checksum = folder.with_name(folder.name + ".zip"), folder.with_name(folder.name + ".zip.sha256")
    for path in (archive, checksum):
        if path.exists() or path.is_symlink():
            raise ValueError(f"Output already exists; refusing to overwrite: {path}")
    with archive.open("xb") as output:
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for path in sorted(folder.rglob("*")):
                no_symlinks(path)
                if not path.is_file() and not path.is_dir():
                    raise ValueError(f"Unsupported package entry: {path}")
                package.write(path, path.relative_to(folder.parent).as_posix())
    digest = hashlib.sha256()
    with archive.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    with checksum.open("x", encoding="utf-8") as handle:
        handle.write(f"{digest.hexdigest()}  {archive.name}\n")
    return archive, checksum


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--version", help="Must exactly match REL_VERSION; defaults to that file")
    args = parser.parse_args(argv)
    try:
        release, _ = versions(ROOT, args.version)
        payload = public_payload(ROOT, release)
        folder = reserve_output(args.output_dir, f"DevFlow-agent-skills-{release}")
        for name, data in payload.items():
            target = folder / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as handle:
                handle.write(data)
        archive, checksum = write_archive(folder)
        print(f"Skills directory: {folder}\nArchive: {archive}\nSHA-256: {checksum}")
        print("No examples executed, no CLI binary included, and nothing uploaded.")
        return 0
    except (OSError, ValueError, UnicodeError, subprocess.CalledProcessError) as exc:
        print(f"Packaging refused: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
