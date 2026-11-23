"""Catch measured tester telemetry in public Markdown without echoing its contents."""

import re
import subprocess
import sys
from pathlib import Path


PRIVATE_SOURCE = re.compile(
    r"\b(?:production (?:checks?|diagnostics?|dashboard|graph|recordings?|uploads?)"
    r"|live diagnostics?|authenticated dashboard|real tester|physical tester)\b",
    re.IGNORECASE,
)
MEASURED_DATA = re.compile(
    r"\b(?:\d[\d,.]*|zero)\s+(?:(?:ready|received|uploaded|raw|motion|background|live)\s+)*"
    r"(?:recordings?|fragments?|samples?|uploads?)\b"
    r"|\blatest (?:motion|upload) at \d{1,2}:\d{2}\b",
    re.IGNORECASE,
)


def main():
    names = subprocess.check_output(["git", "ls-files", "-z", "--", "*.md"]).decode().split("\0")
    rejected = False
    for name in filter(None, names):
        path = Path(name)
        if not path.is_file():
            continue
        content = path.read_text()
        for paragraph in re.finditer(r"(?m)^.+(?:\n(?![-*+] ).+)*", content):
            measurement = MEASURED_DATA.search(paragraph.group())
            if measurement and PRIVATE_SOURCE.search(paragraph.group()):
                line = 1 + content.count("\n", 0, paragraph.start() + measurement.start())
                print(f"{name}:{line}: keep measured tester data in the private dashboard "
                      "and describe the software behavior here.", file=sys.stderr)
                rejected = True
    return int(rejected)


if __name__ == "__main__":
    sys.exit(main())
