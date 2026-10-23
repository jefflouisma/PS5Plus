#!/usr/bin/env python3
"""Print what upstream KytyPS5 CI uses for a platform: build targets, ctest filter, apt packages or Qt version.

PS5Plus builds and tests exactly what upstream CI does, so new upstream tests and dependencies
are picked up by the nightly merge without editing this repository.
"""
from pathlib import Path
import re
import sys

import yaml

FIELDS = {"targets", "tests", "apt", "qt"}


def main() -> None:
    if len(sys.argv) != 4 or sys.argv[3] not in FIELDS:
        sys.exit(f"usage: upstream-ci.py WORKFLOW linux|macos|windows {'|'.join(sorted(FIELDS))}")
    workflow, platform, field = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    steps = yaml.safe_load(workflow.read_text())["jobs"][platform]["steps"]
    runs = {step.get("name"): step.get("run", "") for step in steps}
    value = ""
    if field == "targets":
        match = re.search(r"--target\s+(.*?)--parallel", runs.get("Build", ""), re.S)
        value = " ".join(target for target in re.split(r"[\s\\^]+", match.group(1)) if target) if match else ""
    elif field == "tests":
        match = re.search(r"-R\s+['\"]([^'\"]+)['\"]", runs.get("Test", ""))
        value = match.group(1) if match else ""
    elif field == "apt":
        match = re.search(r"apt-get install\s+(.*)", runs.get("Install build dependencies", ""), re.S)
        words = re.split(r"[\s\\]+", match.group(1)) if match else []
        value = " ".join(word for word in words if word and not word.startswith("-"))
    else:
        qt = [step["with"]["version"] for step in steps if str(step.get("uses", "")).startswith("jurplel/install-qt-action")]
        value = str(qt[0]) if qt else ""
    if not value:
        sys.exit(f"Upstream {platform} CI no longer declares {field} in the expected form: {workflow}")
    print(value)


if __name__ == "__main__":
    main()
