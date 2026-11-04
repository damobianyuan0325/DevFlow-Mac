#!/usr/bin/env python3
"""Exercise the actual consumer binary with identical small/10 MiB JSON inputs."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def check(binary: Path) -> dict:
    binary = binary.resolve(strict=True)
    binary_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
    fixture = {
        "schemaVersion": 2, "name": "Synthetic CLI capacity check", "records": [],
        "supervision": {
            "schemaVersion": 1, "title": "Synthetic CLI capacity check", "version": "fixture-1",
            "originalRequest": "Accept the same valid ledger beyond the old byte limit", "assumptions": [], "scope": [],
            "requirements": [{"id": "R1", "title": "Read full JSON", "originalText": "Read full JSON",
                              "details": "Synthetic fixture", "assumptions": [], "scope": [], "outOfScope": [], "recordIDs": []}],
            "criteria": [{"id": "A1", "requirementID": "R1", "title": "Keep contract identity", "expected": "Same contract",
                          "requiredLevel": "unit", "sourcePaths": []}],
            "tasks": [{"id": "U1", "title": "Check CLI", "criterionIDs": ["A1"], "status": "planned", "recordIDs": []}],
            "testCases": [{"id": "T1", "title": "Same JSON, different whitespace", "criterionIDs": ["A1"], "taskIDs": ["U1"],
                           "input": "Small and padded JSON", "expected": "Identical contract", "level": "unit", "sourcePaths": [], "minimumPassed": 1}],
            "executions": [], "issues": [], "artifacts": []
        }
    }
    with tempfile.TemporaryDirectory(prefix="devflow-cli-check-") as directory:
        root = Path(directory)
        small = root / "small.json"
        large = root / "large.json"
        data = json.dumps(fixture, separators=(",", ":")).encode()
        small.write_bytes(data)
        large.write_bytes(data + b" " * (10 * 1024 * 1024 - len(data)))
        expected_hash = hashlib.sha256(large.read_bytes()).hexdigest()
        outputs = []
        for path in (small, large):
            run = subprocess.run([str(binary), "contracts", str(path)], capture_output=True, text=True, timeout=60)
            if run.returncode != 0:
                raise RuntimeError(f"{binary}: contracts rejected {path.stat().st_size} bytes (exit {run.returncode}): {run.stderr.strip()}")
            outputs.append(json.loads(run.stdout))
        if set(outputs[0]) != {"T1"} or outputs[0] != outputs[1]:
            raise RuntimeError("Whitespace changed the contract output, or the expected contract is missing")
        if hashlib.sha256(large.read_bytes()).hexdigest() != expected_hash:
            raise RuntimeError("CLI changed its read-only input")
    if hashlib.sha256(binary.read_bytes()).hexdigest() != binary_hash:
        raise RuntimeError("CLI identity changed during the check")
    return {"binary": str(binary), "sha256": binary_hash,
            "probeBytes": 10 * 1024 * 1024, "contracts": 1, "sameContract": True}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/test-cli-entrypoint.py /absolute/path/to/DevFlowEvidence")
    try:
        print(json.dumps(check(Path(sys.argv[1])), ensure_ascii=False))
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
