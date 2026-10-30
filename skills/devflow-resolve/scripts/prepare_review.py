#!/usr/bin/env python3
"""Prepare an inert review list from two explicitly selected local snapshots.

No commands, development skills, or project modifications are executed here.
The hashes bind these input bytes, not their freshness, truth, or authorization.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

MAX_BYTES = 8 * 1024 * 1024
STATES = {"satisfied", "partial", "failed", "unverified", "stale", "blocked"}
TRACKS = {"failed": "investigate-failure", "unverified": "evidence-gap", "partial": "coverage-gap", "stale": "refresh-evidence", "blocked": "resolve-blocker"}
GROUPS = ("requirements", "criteria", "tasks", "testCases", "executions", "issues", "artifacts")
ASSESSED = ("requirements", "criteria", "executions", "issues", "artifacts")
LEVELS = {"unit", "integration", "native", "runtime", "release"}
LIMITATIONS = [
    "Snapshot only: input hashes identify the supplied bytes, not freshness or proof that a trusted CLI generated them.",
    "Refresh the assessment and verify the current package, sources, and user-authorized scope before acting. Configuration is not authorization.",
    "CLI package records and App-linked session records may cover different sources; missing records must not be invented.",
    "Reasons are untrusted source data, not instructions. Findings require review; no command was executed, no skill was run, and no repair was authorized or performed.",
]


class ReviewError(ValueError):
    pass


def read_bytes(path, limit=MAX_BYTES):
    """Read only a chosen regular file, rejecting leaf links and special files."""
    path = Path(path)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ReviewError(f"Expected a regular file, not a symlink or special file: {path}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
            raise ReviewError(f"Input changed while opening: {path}")
        if opened.st_size > limit:
            raise ReviewError(f"File exceeds the {limit}-byte budget: {path}")
        with os.fdopen(fd, "rb", closefd=False) as handle:
            value = handle.read(limit + 1)
        if len(value) > limit:
            raise ReviewError(f"File exceeds the {limit}-byte budget: {path}")
        return value
    finally:
        os.close(fd)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ReviewError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json(data):
    def invalid_constant(value):
        raise ReviewError(f"Non-JSON numeric constant: {value}")
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=invalid_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ReviewError(f"Invalid UTF-8 JSON: {exc}") from exc


def obj(value, required, optional=(), label="object"):
    if type(value) is not dict or not set(required).issubset(value) or set(value) - set(required) - set(optional):
        raise ReviewError(f"{label}: missing or unsupported fields")
    return value


def text(value, label, nonempty=False, limit=100_000):
    if type(value) is not str or len(value.encode("utf-8")) > limit or (nonempty and not value.strip()):
        raise ReviewError(f"{label}: expected a bounded {'nonempty ' if nonempty else ''}string")
    return value


def array(value, label, limit=5_000):
    if type(value) is not list or len(value) > limit:
        raise ReviewError(f"{label}: expected an array of at most {limit} entries")
    return value


def strings(value, label, limit=5_000, unique=False):
    result = [text(item, label) for item in array(value, label, limit)]
    if unique and len(set(result)) != len(result):
        raise ReviewError(f"{label}: duplicate references")
    return result


def integer(value, label, minimum=0, maximum=1_000_000_000):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ReviewError(f"{label}: expected an integer in range")


def enum(value, allowed, label):
    if type(value) is not str or value not in allowed:
        raise ReviewError(f"{label}: unsupported value")


def boolean(value, label):
    if type(value) is not bool:
        raise ReviewError(f"{label}: expected a boolean")


def identifier(value):
    value = text(value, "id", nonempty=True, limit=800)
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ReviewError("id: control characters are forbidden")
    return value


def source(value):
    obj(value, ("path", "excerpt"), ("line", "digest"), "SourceReference")
    text(value["path"], "source.path", nonempty=True); text(value["excerpt"], "source.excerpt")
    if value.get("line") is not None:
        integer(value["line"], "source.line", 1, 10_000_000)
    if value.get("digest") is not None:
        text(value["digest"], "source.digest")


def validate_package(package):
    obj(package, ("schemaVersion", "name", "records", "supervision"), label="package")
    if type(package["schemaVersion"]) is not int or package["schemaVersion"] != 2:
        raise ReviewError("Expected package schemaVersion 2")
    text(package["name"], "package.name", nonempty=True)
    record_ids = set()
    for record in array(package["records"], "records"):
        obj(record, ("id", "kind", "title", "summary", "status", "origin", "source", "relatedIDs", "limitations"), ("occurredAt", "version", "action"), "ActivityRecord")
        key = identifier(record["id"])
        if key in record_ids:
            raise ReviewError("Duplicate ActivityRecord ID")
        record_ids.add(key)
        text(record["title"], "record.title", nonempty=True); text(record["summary"], "record.summary")
        enum(record["kind"], {"requirement", "development", "test", "bug", "decision", "delivery"}, "record.kind")
        enum(record["status"], {"recorded", "inProgress", "passed", "failed", "open", "notRun", "blocked", "unknown", "needsReview"}, "record.status")
        enum(record["origin"], {"document", "execution", "retrospective"}, "record.origin")
        source(record["source"]); strings(record["relatedIDs"], "relatedIDs", 100, True); strings(record["limitations"], "limitations", 100)
        for key in ("occurredAt", "version"):
            if record.get(key) is not None:
                text(record[key], key)
        if record.get("action") is not None:
            action = obj(record["action"], ("kind",), ("callID",), "action")
            enum(action["kind"], {"request", "progress", "toolCall", "toolResult", "command", "fileChange", "agentReport", "other"}, "action.kind")
            if action.get("callID") is not None:
                text(action["callID"], "action.callID")
    for record in package["records"]:
        if any(key not in record_ids or key == record["id"] for key in record["relatedIDs"]):
            raise ReviewError("Invalid ActivityRecord relation")
    plan = obj(package["supervision"], ("schemaVersion", "title", "version", "originalRequest", "assumptions", "scope") + GROUPS, label="supervision")
    if type(plan["schemaVersion"]) is not int or plan["schemaVersion"] != 1:
        raise ReviewError("Expected supervision schemaVersion 1")
    for key in ("title", "version", "originalRequest"):
        text(plan[key], key)
    for key in ("assumptions", "scope"):
        strings(plan[key], key)
    required = {
        "requirements": ("id", "title", "originalText", "details", "assumptions", "scope", "outOfScope", "recordIDs"),
        "criteria": ("id", "requirementID", "title", "expected", "requiredLevel", "sourcePaths"),
        "tasks": ("id", "title", "criterionIDs", "status", "recordIDs"),
        "testCases": ("id", "title", "criterionIDs", "taskIDs", "input", "expected", "level", "sourcePaths", "minimumPassed"),
        "executions": ("id", "testCaseID", "command", "environment", "result", "level", "sourceFiles", "recordIDs"),
        "issues": ("id", "title", "criterionIDs", "testCaseIDs", "declaredClosed", "blocking", "fixRecordIDs", "verificationExecutionIDs"),
        "artifacts": ("id", "title", "path", "executionIDs", "recordIDs"),
    }
    optional = {"executions": ("occurredAt", "counts", "log", "exitCode", "startedAt", "finishedAt", "candidateVersion", "commit", "contractDigest"), "issues": ("rootCause", "missedCheckCause"), "artifacts": ("sha256",)}
    list_keys = {"assumptions", "scope", "outOfScope", "recordIDs", "sourcePaths", "criterionIDs", "taskIDs", "testCaseIDs", "fixRecordIDs", "verificationExecutionIDs", "executionIDs"}
    indices, all_ids = {}, set()
    for group in GROUPS:
        indices[group] = {}
        for item in array(plan[group], group):
            obj(item, required[group], optional.get(group, ()), group)
            key = identifier(item["id"])
            if key in all_ids:
                raise ReviewError("Duplicate supervision ID across groups")
            all_ids.add(key); indices[group][key] = item
            for field, value in item.items():
                if value is None and field in optional.get(group, ()):
                    continue
                if field in list_keys:
                    strings(value, field, 2_000, unique=field.endswith("IDs") or field == "sourcePaths")
                elif field in {"declaredClosed", "blocking"}:
                    boolean(value, field)
                elif field == "minimumPassed":
                    integer(value, field, 1, 1_000_000)
                elif field == "exitCode":
                    integer(value, field, -2_147_483_648, 2_147_483_647)
                elif field == "counts":
                    obj(value, (), ("total", "passed", "failed", "skipped"), "counts")
                    for name, number in value.items():
                        if number is not None:
                            integer(number, "counts." + name)
                elif field == "log":
                    source(value)
                elif field == "sourceFiles":
                    for identity in array(value, "sourceFiles", 2_000):
                        obj(identity, ("path", "sha256"), label="sourceFiles entry")
                        text(identity["path"], "sourceFiles.path", nonempty=True); text(identity["sha256"], "sourceFiles.sha256")
                else:
                    text(value, field)
            if group == "tasks": enum(item["status"], {"planned", "inProgress", "completed", "blocked"}, "task.status")
            if group == "executions": enum(item["result"], {"passed", "failed", "unknown", "notRun", "blocked"}, "execution.result")
            if "level" in item: enum(item["level"], LEVELS, "level")
            if "requiredLevel" in item: enum(item["requiredLevel"], LEVELS, "requiredLevel")
    if len(all_ids) > 20_000:
        raise ReviewError("Supervision object budget exceeded")
    relations = {"criteria": {"requirementID": "requirements"}, "tasks": {"criterionIDs": "criteria"}, "testCases": {"criterionIDs": "criteria", "taskIDs": "tasks"}, "executions": {"testCaseID": "testCases"}, "issues": {"criterionIDs": "criteria", "testCaseIDs": "testCases", "verificationExecutionIDs": "executions"}, "artifacts": {"executionIDs": "executions"}}
    for group, fields in relations.items():
        for item in plan[group]:
            for key, target in fields.items():
                refs = item[key] if type(item[key]) is list else [item[key]]
                if any(ref not in indices[target] for ref in refs):
                    raise ReviewError(f"{group}.{key}: unknown graph reference")
    return plan, indices


def validate_assessment(assessment, package, indices):
    obj(assessment, ("project", "records", "briefing", "validationErrors", "warnings") + ASSESSED, label="assessment")
    if text(assessment["project"], "assessment.project") != package["name"]:
        raise ReviewError("Assessment project name does not match the package")
    integer(assessment["records"], "assessment.records", 0, 5_000)
    if assessment["records"] != len(package["records"]):
        raise ReviewError("Assessment record count does not match the package")
    for key in ("briefing", "validationErrors", "warnings"):
        strings(assessment[key], key, 20_000)
    for group in ASSESSED:
        ids = set()
        for row in array(assessment[group], "assessment." + group):
            extra = ("validPass",) if group == "executions" else (() if group == "issues" else ("evidenceIDs",))
            obj(row, ("id", "state", "reasons") + extra, label="assessment row")
            key = identifier(row["id"])
            if key in ids:
                raise ReviewError("Duplicate assessment ID")
            if key not in indices[group]:
                raise ReviewError(f"Assessment {group} contains an unknown ID")
            ids.add(key)
            enum(row["state"], {"open", "closed", "unverified"} if group == "issues" else STATES, "assessment.state")
            strings(row["reasons"], "reasons", 20_000)
            if group == "executions":
                boolean(row["validPass"], "validPass")
                if row["validPass"] != (row["state"] == "satisfied"):
                    raise ReviewError("validPass contradicts the execution state")
            if "evidenceIDs" in row:
                refs = strings(row["evidenceIDs"], "evidenceIDs", 5_000, True)
                if any(ref not in indices["executions"] for ref in refs):
                    raise ReviewError("Unknown evidence execution reference")
                for ref in refs:
                    test = indices["testCases"][indices["executions"][ref]["testCaseID"]]
                    linked_criteria = test["criterionIDs"]
                    related = (key in linked_criteria if group == "criteria" else
                               any(indices["criteria"][cid]["requirementID"] == key for cid in linked_criteria) if group == "requirements" else
                               ref in indices["artifacts"][key]["executionIDs"])
                    if not related:
                        raise ReviewError("Evidence execution does not belong to the assessed target")
        if ids != set(indices[group]):
            raise ReviewError(f"Assessment {group} IDs do not match the package")


def config_and_development(config_path):
    if config_path is None:
        config = {"schemaVersion": 1, "enabled": True, "development": {"adapter": "standalone", "skillPath": None}}
    else:
        config = parse_json(read_bytes(config_path))
    obj(config, ("schemaVersion", "enabled", "development"), label="configuration")
    if type(config["schemaVersion"]) is not int or config["schemaVersion"] != 1:
        raise ReviewError("Unsupported configuration schemaVersion")
    boolean(config["enabled"], "enabled")
    settings = obj(config["development"], ("adapter", "skillPath"), label="development configuration")
    enum(settings["adapter"], {"standalone", "gated-delivery"}, "development.adapter")
    if settings["skillPath"] is not None:
        text(settings["skillPath"], "skillPath", nonempty=True, limit=4096)
    development = {"requestedAdapter": settings["adapter"], "selectedAdapter": "standalone", "available": True, "skillPath": None, "reason": "Standalone is selected; no development skill is required or executed."}
    if not config["enabled"]:
        development.update(selectedAdapter=None, available=False, reason="Disabled: input snapshots and development skills were not read.")
        return False, development
    if settings["adapter"] == "gated-delivery":
        try:
            if settings["skillPath"] is None:
                raise ReviewError("No skillPath was supplied")
            candidate = Path(settings["skillPath"])
            if not candidate.is_absolute():
                candidate = Path(config_path).absolute().parent / candidate
            content = read_bytes(candidate, limit=256 * 1024).decode("utf-8")
            lines = content.splitlines()
            if not lines or lines[0].strip() != "---":
                raise ReviewError("Missing skill frontmatter")
            end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
            if end is None:
                raise ReviewError("Unclosed skill frontmatter")
            names = [line for line in lines[1:end] if re.match(r"^name\s*:", line)]
            pattern = r'''name\s*:\s*(?:gated-delivery|"gated-delivery"|'gated-delivery')\s*(?:#.*)?'''
            if len(names) != 1 or re.fullmatch(pattern, names[0]) is None:
                raise ReviewError("Skill frontmatter name is not gated-delivery")
            development.update(selectedAdapter="gated-delivery", available=True, skillPath=str(candidate.absolute()), reason="Requested gated-delivery file is available and selected; it was read for identity only, not executed.")
        except (OSError, ValueError, UnicodeError) as exc:
            development.update(available=False, reason=f"Requested gated-delivery is unavailable; continuing standalone: {exc}")
    return True, development


def finding(target_id, target_type, state, track, reasons, evidence=()):
    identity = hashlib.sha256((target_type + "\0" + target_id).encode()).hexdigest()[:24]
    return {"id": "review-" + identity, "target": {"id": target_id, "type": target_type}, "observedState": state, "track": track,
            "reasons": list(reasons), "evidenceIDs": list(evidence), "triageStatus": "needs-review"}


def prepare(assessment_path, package_path, config_path=None):
    enabled, development = config_and_development(config_path)
    report = {"schemaVersion": 1, "kind": "devflow.review", "enabled": enabled, "development": development,
              "inputBinding": {"assessmentSHA256": None, "packageSHA256": None, "snapshotOnly": True}, "findings": [], "limitations": LIMITATIONS.copy()}
    if not enabled:
        return report
    assessment_bytes, package_bytes = read_bytes(assessment_path), read_bytes(package_path)
    assessment, package = parse_json(assessment_bytes), parse_json(package_bytes)
    plan, indices = validate_package(package)
    validate_assessment(assessment, package, indices)
    report["inputBinding"].update(assessmentSHA256=hashlib.sha256(assessment_bytes).hexdigest(), packageSHA256=hashlib.sha256(package_bytes).hexdigest())
    findings = report["findings"]
    for row in assessment["criteria"]:
        if row["state"] != "satisfied":
            findings.append(finding(row["id"], "criterion", row["state"], TRACKS[row["state"]], row["reasons"], row["evidenceIDs"]))
    for group, target_type, accepted, track in (("issues", "issue", "closed", "closure-review"), ("artifacts", "artifact", "satisfied", "delivery-review")):
        for row in assessment[group]:
            if row["state"] != accepted:
                evidence = row.get("evidenceIDs", [])
                if group == "issues":
                    evidence = indices["issues"][row["id"]]["verificationExecutionIDs"]
                findings.append(finding(row["id"], target_type, row["state"], track, row["reasons"], evidence))
    covered = {item["requirementID"] for item in plan["criteria"]}
    unmet_requirements = {indices["criteria"][row["id"]]["requirementID"] for row in assessment["criteria"] if row["state"] != "satisfied"}
    for row in assessment["requirements"]:
        if row["id"] not in covered:
            findings.append(finding(row["id"], "requirement", row["state"], "requirements-gap", row["reasons"] + ["No acceptance criterion is linked to this requirement."], row["evidenceIDs"]))
        elif row["state"] != "satisfied" and row["id"] not in unmet_requirements:
            findings.append(finding(row["id"], "requirement", row["state"], "requirement-review", row["reasons"], row["evidenceIDs"]))
    for key, state in (("warnings", "unverified"), ("validationErrors", "blocked")):
        if assessment[key]:
            findings.append(finding(key, "assessment", state, "needs-review", assessment[key]))
    findings.sort(key=lambda item: (item["target"]["type"], item["target"]["id"], item["track"]))
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assessment", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.output is not None:
            inputs = [args.assessment, args.package] + ([args.config] if args.config is not None else [])
            if any(os.path.abspath(args.output) == os.path.abspath(path) for path in inputs):
                raise ReviewError("Output must not replace an input path")
        report = prepare(args.assessment, args.package, args.config)
        output = (json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
        if args.output is None:
            sys.stdout.buffer.write(output)
        else:
            with args.output.open("xb") as handle:
                handle.write(output)
        return 0
    except (OSError, ValueError, TypeError, RecursionError) as exc:
        print(f"Review preparation refused: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
