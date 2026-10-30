#!/usr/bin/env python3
"""Run only the copied teaching example and append real DevFlow evidence.

Not a general agent command executor. Requires an explicit, trusted Evidence CLI.
The original skill assets should remain untouched. Python standard library only.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import tempfile
import uuid


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def cli_json(cli, operation, package):
    run = subprocess.run([str(cli), operation, str(package)], capture_output=True, timeout=30)
    if run.returncode != 0:
        raise ValueError(f"Evidence CLI {operation} failed: {run.stderr.decode('utf-8', errors='replace')}")
    return json.loads(run.stdout)


def parse_counts(output):
    reports = []
    for line in output.decode("utf-8", errors="replace").splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict) and "counts" in item:
            reports.append(item["counts"])
    if len(reports) != 1 or not isinstance(reports[0], dict):
        return None
    counts = reports[0]
    keys = ("total", "passed", "failed", "skipped")
    if any(type(counts.get(k)) is not int or counts[k] < 0 for k in keys):
        return None
    if counts["total"] != sum(counts[k] for k in keys[1:]):
        return None
    return {k: counts[k] for k in keys}


def run_example(root, cli):
    original_assets = Path(__file__).resolve().parent.parent / "assets" / "example"
    if root == original_assets.resolve():
        raise ValueError("Copy assets/example to a separate directory before running.")
    paths = ["devflow-supervision.json", "feature.py", "checks.py", "requirements.md"]
    for relative in paths:
        source = root / relative
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Expected an ordinary demo file: {relative}")
    evidence = root / "evidence"
    if evidence.is_symlink():
        raise ValueError("The demo evidence directory must not be a symlink.")
    evidence.mkdir(exist_ok=True)
    lock = root / ".devflow-demo.lock"
    lock_fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(lock_fd)
    try:
        package = root / "devflow-supervision.json"
        original = package.read_bytes()
        doc = json.loads(original)
        plan = doc["supervision"]
        if [t["id"] for t in plan["testCases"]] != ["T-demo"]:
            raise ValueError("This runner only supports the provided T-demo example.")
        contracts = cli_json(cli, "contracts", package)
        test = plan["testCases"][0]
        source_paths = sorted(set(test["sourcePaths"]) | {
            p for a in plan["criteria"] if a["id"] in test["criterionIDs"] for p in a["sourcePaths"]
        })
        if source_paths != ["checks.py", "feature.py"]:
            raise ValueError("Demo source scope must remain checks.py and feature.py.")
        if test["level"] != "unit":
            raise ValueError("The demo is a unit check, not native/runtime/release acceptance.")
        run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:10]
        run_dir = evidence / run_id
        run_dir.mkdir()
        (run_dir / "package-before.json").write_bytes(original)
        save_json(run_dir / "contracts-before.json", contracts)
        identities = [{"path": p, "sha256": digest((root / p).read_bytes())} for p in source_paths]
        command = [sys.executable, "-B", "checks.py"]
        environment = f"Python {platform.python_version()}; {platform.platform()}; cwd=project root"
        save_json(run_dir / "frozen-before.json", {
            "frozenAt": now(), "contractDigest": contracts["T-demo"], "sourceFiles": identities,
            "candidateVersion": plan["version"], "command": command,
            "runnerSHA256": digest(Path(__file__).read_bytes()), "cliSHA256": digest(cli.read_bytes()),
        })
        started = now()
        timeout = False
        try:
            proc = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
            output, exit_code = proc.stdout, proc.returncode
        except subprocess.TimeoutExpired as exc:
            output, exit_code, timeout = exc.output or b"", None, True
        finished = now()
        log_path = run_dir / "checks.log"
        log_path.write_bytes(output)
        counts = parse_counts(output)
        source_errors = []
        unchanged = True
        for item in identities:
            try:
                if digest((root / item["path"]).read_bytes()) != item["sha256"]:
                    unchanged = False
            except OSError as exc:
                unchanged = False
                source_errors.append(f"{item['path']}: {type(exc).__name__}")
        passed = (not timeout and exit_code == 0 and counts is not None and counts["total"] > 0
                  and counts["passed"] >= test["minimumPassed"] and counts["failed"] == counts["skipped"] == 0)
        result = "passed" if passed else "failed" if timeout or exit_code not in (None, 0) or (counts and counts["failed"] > 0) else "unknown"
        limitations = ["Only the teaching example's unit behavior was checked."]
        if counts is None:
            limitations.append("No single complete counts report; counts remain unknown.")
        if timeout:
            limitations.append("Timed out after 30 seconds; no actual process exit code was captured.")
        if not unchanged:
            limitations.append("Sources changed or became unreadable during execution; rerun before relying on this result.")
        if source_errors:
            limitations.append("Source recheck errors: " + "; ".join(source_errors))
        relative_log = log_path.relative_to(root).as_posix()
        text_lines = output.decode("utf-8", errors="replace").splitlines()
        log_ref = {"path": relative_log, "excerpt": text_lines[-1][:1500] if text_lines else "", "digest": digest(output)}
        rec_id, execution_id = "rec-demo-" + run_id, "E-demo-" + run_id
        execution = {
            "id": execution_id, "testCaseID": "T-demo", "occurredAt": finished,
            "command": shlex.join(command), "environment": environment, "result": result, "level": "unit",
            "counts": counts, "sourceFiles": identities, "log": log_ref, "recordIDs": [rec_id],
            "exitCode": exit_code, "startedAt": started, "finishedAt": finished,
            "candidateVersion": plan["version"], "contractDigest": contracts["T-demo"],
        }
        save_json(run_dir / "execution.json", {"execution": execution, "sourcesUnchanged": unchanged, "limitations": limitations})
        if package.read_bytes() != original:
            raise ValueError(f"Package changed concurrently; evidence retained in {run_dir}. Merge explicitly.")
        plan["executions"].append(execution)
        doc["records"].append({
            "id": rec_id, "kind": "test", "title": "Teaching example check execution", "summary": f"Actual result: {result}; counts: {counts}",
            "status": result, "origin": "execution", "source": log_ref,
            "relatedIDs": ["rec-demo-request"], "limitations": limitations,
            "occurredAt": finished, "version": plan["version"], "action": {"kind": "command"},
        })
        # A sibling temp file provides an atomic rename; never replace old run evidence.
        fd, temporary = tempfile.mkstemp(prefix=".devflow-package-", suffix=".json", dir=root)
        os.close(fd)
        pending = Path(temporary)
        try:
            save_json(pending, doc)
            cli_json(cli, "contracts", pending)  # Validate the candidate before replacing the package.
            if package.read_bytes() != original:
                raise ValueError(f"Package changed concurrently; evidence retained in {run_dir}. Merge explicitly.")
            os.replace(pending, package)
        finally:
            pending.unlink(missing_ok=True)
        assessment = cli_json(cli, "inspect", package)
        save_json(run_dir / "assessment.json", assessment)
        current = next(e for e in assessment["executions"] if e["id"] == execution_id)
        print(json.dumps({"package": str(package), "executionID": execution_id, "result": result,
                          "counts": counts, "assessment": assessment}, ensure_ascii=False, indent=2))
        return 0 if passed and unchanged and current["validPass"] else 1
    finally:
        lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--evidence-cli", required=True, type=Path)
    args = parser.parse_args()
    try:
        root, cli = args.project.resolve(strict=True), args.evidence_cli.resolve(strict=True)
        if not root.is_dir() or not cli.is_file() or not os.access(cli, os.X_OK):
            raise ValueError("Expected an existing demo directory and an executable Evidence CLI.")
        return run_example(root, cli)
    except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError) as exc:
        print(f"Example not completed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
