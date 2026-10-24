"""Reject failed/empty UI test runs and runtime warnings, even if Xcode passed.

Usage: python3 Tools/Validation/check_ui_test_result.py /path/to/run.xcresult
"""

import argparse
import json
import os
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle")
    args = parser.parse_args()
    environment = dict(os.environ)
    environment.setdefault("DEVELOPER_DIR", "/Applications/dev/Xcode.app/Contents/Developer")
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", args.result_bundle],
        env=environment, text=True, capture_output=True,
    )
    if result.returncode:
        print(result.stderr, file=sys.stderr)
        return 1
    summary = json.loads(result.stdout)
    warnings = summary["runtimeWarnings"]
    print(f"{summary['result']}: {summary['passedTests']} passed, "
          f"{summary['failedTests']} failed, {summary['skippedTests']} skipped, "
          f"{len(warnings)} runtime warnings")
    for warning in warnings:
        print(warning["message"], file=sys.stderr)
    return int(summary["result"] != "Passed" or summary["totalTestCount"] == 0
               or summary["failedTests"] != 0 or bool(warnings))


if __name__ == "__main__":
    sys.exit(main())
