#!/bin/bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

files=()
while IFS= read -r -d '' path; do
    if [[ -f "$path" ]]; then files+=("$path"); fi
done < <(git ls-files -z --cached --others --exclude-standard -- '*.swift' ':!Shared/Services/RecordedAccelerometer.swift')

host="$(dirname "$(xcrun --find swift)")/../lib/swift/host"
xcrun swift -I "$host" -L "$host" -Xlinker -rpath -Xlinker "$host" - "${files[@]}" <<'SWIFT'
import Foundation
import SwiftParser
import SwiftSyntax

var violations = 0
for path in CommandLine.arguments.dropFirst() {
    let tree = Parser.parse(source: try String(contentsOfFile: path, encoding: .utf8))
    for token in tree.tokens(viewMode: .sourceAccurate) {
        guard case let .identifier(name) = token.tokenKind,
              name.trimmingCharacters(in: CharacterSet(charactersIn: "`")) == "CMSensorRecorder" else { continue }
        let location = token.startLocation(converter: SourceLocationConverter(fileName: path, tree: tree))
        print("\(path):\(location.line): error: Use RecordedAccelerometer. Its history.samples(from:to:) applies Core Motion's wall-clock bounds.")
        violations += 1
    }
}
exit(violations == 0 ? 0 : 1)
SWIFT
