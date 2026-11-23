"""Collect Ciggy crash reports from the named simulators, including companion watchdog kills."""

import argparse
import json
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("devices", nargs="+")
    args = parser.parse_args()
    coalitions = {f"com.apple.CoreSimulator.SimDevice.{device}" for device in args.devices}
    reports = Path.home() / "Library/Logs/DiagnosticReports"
    bundles = {"That-Canadian-Software-Services.ciggy", "That-Canadian-Software-Services.ciggy.watchkitapp"}
    failures = []
    for path in sorted(reports.glob("ciggy*.ips")):
        with path.open() as stream:
            header = json.loads(stream.readline())
            if header.get("bundleID") not in bundles:
                continue
            incident = json.load(stream)
        if incident.get("coalitionName") in coalitions:
            args.output.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, args.output / path.name)
            failures.append(path.name)
    if failures:
        raise SystemExit("Ciggy crashed during the paired run. Inspect the saved reports: " + ", ".join(failures))
    print("No Ciggy crash reports found for this simulator pair.")


if __name__ == "__main__":
    main()
