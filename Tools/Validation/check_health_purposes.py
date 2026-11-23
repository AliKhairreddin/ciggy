"""Check the HealthKit permission prompts in a built iPhone and companion Watch app."""

import argparse
import plistlib
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phone_app", type=Path)
    phone = parser.parse_args().phone_app
    watches = list((phone / "Watch").glob("*.app"))
    if len(watches) != 1:
        sys.exit(f"{phone}: embed one Watch companion with the Embed Watch Content phase.")

    errors = []
    for app in [phone, *watches]:
        with (app / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
            value = info.get(key)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{app.name}: restore {key} through Configuration/HealthKit.xcconfig.")
    if errors:
        sys.exit("\n".join(errors))
    print("Both packaged apps include HealthKit read and update purpose strings.")


if __name__ == "__main__":
    main()
