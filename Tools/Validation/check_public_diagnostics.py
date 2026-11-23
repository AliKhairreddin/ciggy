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

HEADING = re.compile(r"^ {0,3}(#{1,6})[ \t]+")
BLOCK = re.compile(r"(?m)^ {0,3}#{1,6}[ \t]+.*|^.+(?:\n(?! {0,3}(?:#{1,6}[ \t]|[-*+] |\d+[.)] )).+)*")
FIXTURE_SOURCE = re.compile(
    r"\b(?:synthetic|simulated|mock)\s+$"
    r"|\b(?:synthetic|simulated) (?:tests?|fixtures?|examples?) "
    r"(?:models?|simulates?|mocks?) (?:an? |the )?$",
    re.IGNORECASE,
)
CAPACITY = re.compile(
    r"\b(?:limit|maximum|capacity) of\s+$"
    r"|\b(?:can|may) (?:process|accept|load|store|display) (?:at most|up to)\s+$"
    r"|\b(?:supports?|allows?) (?:at most|up to)\s+$",
    re.IGNORECASE,
)


def measured_lines(text):
    private_heading = None
    for block in BLOCK.finditer(text):
        value = block.group()
        heading = HEADING.match(value)
        if heading and private_heading and len(heading[1]) <= private_heading:
            private_heading = None
        sources = list(PRIVATE_SOURCE.finditer(value))
        fixture_sources = [source for source in sources if FIXTURE_SOURCE.search(value[:source.start()])]
        private = len(sources) > len(fixture_sources)
        if heading and private and private_heading is None:
            private_heading = len(heading[1])
        if not private and private_heading is None:
            continue
        for measurement in MEASURED_DATA.finditer(value):
            prefix = value[:measurement.start()]
            if CAPACITY.search(prefix):
                continue
            if any(prefix[source.end():].strip().lower() in {"with", "containing"}
                   for source in fixture_sources if source.end() <= measurement.start()):
                continue
            yield 1 + text.count("\n", 0, block.start() + measurement.start())
            break


def main():
    names = subprocess.check_output(["git", "ls-files", "-z", "--", "*.md"]).decode().split("\0")
    rejected = False
    for name in filter(None, names):
        path = Path(name)
        if not path.is_file():
            continue
        for line in measured_lines(path.read_text()):
            print(f"{name}:{line}: keep measured tester data in the private dashboard "
                  "and describe the software behavior here.", file=sys.stderr)
            rejected = True
    return int(rejected)


if __name__ == "__main__":
    sys.exit(main())
