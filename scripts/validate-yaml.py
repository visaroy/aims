#!/usr/bin/env python3
import re
import sys
from pathlib import Path
from typing import NoReturn
import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_KEYS = {"name", "run-name", "on", True, "permissions", "env", "defaults", "concurrency", "jobs"}
ACTION_SHA = re.compile(r"^[^/\s]+/[^@\s]+@[0-9a-f]{40}$")

def fail(path: Path, message: str) -> NoReturn:
    print(f"{path.relative_to(ROOT)}: {message}", file=sys.stderr)
    raise SystemExit(1)

paths = sorted((ROOT / ".github").rglob("*.yml")) + sorted((ROOT / ".github").rglob("*.yaml"))
for path in paths:
    text = path.read_text(encoding="utf-8")
    try:
        parsed = yaml.safe_load(text)
    except yaml.YAMLError as error:
        fail(path, str(error))
    if not isinstance(parsed, dict):
        fail(path, "expected a YAML mapping")
    if ".github/workflows" in path.as_posix():
        unknown = set(parsed) - WORKFLOW_KEYS
        if unknown:
            fail(path, f"unknown workflow keys: {sorted(map(str, unknown))}")
        trigger = parsed.get("on", parsed.get(True))
        if trigger is None:
            fail(path, "missing workflow trigger")
        jobs = parsed.get("jobs")
        if not isinstance(jobs, dict) or not jobs:
            fail(path, "jobs must be a non-empty mapping")
        if text.count("${{") != text.count("}}"):
            fail(path, "unbalanced GitHub Actions expression delimiters")
        for job_name, job in jobs.items():
            if not isinstance(job, dict) or not (job.get("runs-on") or job.get("uses")):
                fail(path, f"job {job_name!r} needs runs-on or uses")
            steps = job.get("steps", [])
            if not isinstance(steps, list):
                fail(path, f"job {job_name!r} steps must be a list")
            for index, step in enumerate(steps, 1):
                if not isinstance(step, dict) or (("run" in step) == ("uses" in step)):
                    fail(path, f"job {job_name!r} step {index} needs exactly one of run or uses")
                action = step.get("uses", "")
                if action and not action.startswith(("./", "docker://")) and not ACTION_SHA.match(action):
                    fail(path, f"job {job_name!r} step {index} action is not pinned to a commit SHA: {action}")
    print(f"OK: {path.relative_to(ROOT)}")
