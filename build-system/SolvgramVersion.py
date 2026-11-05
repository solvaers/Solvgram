#!/usr/bin/env python3
"""Choose Solvgram's internal build number (CFBundleVersion).

Release names use the Solvgram version from versions.json ("solvgram", major.minor),
never this number. The build number only has to keep increasing: it stays above the
builds encoded in older release tags (v<version>-<build>) and above a date-based
floor (yy, day of year, hour), which keeps it well inside Int32.
"""
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def next_build_number(tags, now=None):
    builds = [100000]
    for tag in tags:
        match = re.fullmatch(r"v\d+(?:\.\d+)+-(\d+)", tag.strip())
        if match:
            builds.append(int(match[1]))
    now = now or datetime.now(timezone.utc)
    floor = int(now.strftime("%y%j%H"))
    return max(max(builds) + 1, floor)


if __name__ == "__main__":
    print(next_build_number(Path(sys.argv[1]).read_text().splitlines()))
