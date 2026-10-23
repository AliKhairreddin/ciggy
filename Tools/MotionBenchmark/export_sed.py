#!/usr/bin/env python3
"""Export the pinned official SED release using a data-only pickle interpreter.

No pickle.load, NumPy/Pandas import, imported pickle globals, or executable
reducers are used. Only the exact protocol-3 descriptor vocabulary in this
release is accepted. Object-array *metadata* can contain known column names;
numeric sample blocks must be plain float64/int64 bytes, never object dtype.
"""

import argparse
import array
import csv
import hashlib
import json
import math
import pathlib
import pickletools
import sys
import urllib.request
from dataclasses import dataclass

SOURCE = "https://zenodo.org/api/records/4507451/files/SED.pkl/content"
SHA256 = "0c21f6a78dc1c2c2814f596bdcc9339c229255dd860d5c1ae92c3836b65fa414"
SIZE = 30_686_808
COLUMNS = ("T", "AccX", "AccY", "AccZ", "GyrX", "GyrY", "GyrZ", "GT")
GLOBALS = {
    "pandas.core.frame DataFrame", "pandas.core.internals.managers BlockManager",
    "pandas.core.indexes.base _new_Index", "pandas.core.indexes.base Index",
    "pandas.core.indexes.range RangeIndex", "numpy.core.multiarray _reconstruct",
    "numpy ndarray", "numpy dtype", "builtins slice",
}


@dataclass
class Descriptor:
    kind: str
    args: tuple = ()
    state: object = None


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse_data_only(data):
    """Interpret literals and inert descriptors; never resolve/call pickle code."""
    stack, memo = [], {}
    marker = object()

    def marked():
        index = next((i for i in range(len(stack) - 1, -1, -1) if stack[i] is marker), None)
        require(index is not None, "Missing stack marker")
        values = stack[index + 1:]
        del stack[index:]
        return values

    for count, (opcode, argument, _) in enumerate(pickletools.genops(data)):
        require(count < 50_000, "Too many pickle operations")
        name = opcode.name
        if name == "PROTO":
            require(argument == 3, "Only pinned protocol 3 is supported")
        elif name == "GLOBAL":
            require(argument in GLOBALS, "Unsupported pickle global: " + str(argument))
            stack.append(Descriptor("global", (argument,)))
        elif name in {"BINUNICODE", "BINBYTES", "SHORT_BINBYTES", "BININT", "BININT1", "BININT2"}:
            stack.append(argument)
        elif name in {"NONE", "NEWFALSE", "NEWTRUE"}:
            stack.append({"NONE": None, "NEWFALSE": False, "NEWTRUE": True}[name])
        elif name == "EMPTY_DICT":
            stack.append({})
        elif name == "EMPTY_LIST":
            stack.append([])
        elif name == "EMPTY_TUPLE":
            stack.append(())
        elif name == "MARK":
            stack.append(marker)
        elif name == "TUPLE":
            stack.append(tuple(marked()))
        elif name in {"TUPLE1", "TUPLE2", "TUPLE3"}:
            length = int(name[-1])
            values = tuple(stack[-length:])
            del stack[-length:]
            stack.append(values)
        elif name in {"BINPUT", "LONG_BINPUT"}:
            require(0 <= argument < 50_000, "Invalid memo index")
            memo[argument] = stack[-1]
        elif name in {"BINGET", "LONG_BINGET"}:
            stack.append(memo[argument])
        elif name == "APPEND":
            value = stack.pop()
            require(type(stack[-1]) is list, "APPEND requires a list")
            stack[-1].append(value)
        elif name == "APPENDS":
            values = marked()
            require(type(stack[-1]) is list, "APPENDS requires a list")
            stack[-1].extend(values)
        elif name == "SETITEM":
            value, key = stack.pop(), stack.pop()
            require(type(stack[-1]) is dict and type(key) in (str, int), "Invalid dictionary")
            stack[-1][key] = value
        elif name == "SETITEMS":
            values = marked()
            require(type(stack[-1]) is dict and len(values) % 2 == 0, "Invalid dictionary")
            for key, value in zip(values[::2], values[1::2]):
                require(type(key) in (str, int), "Invalid dictionary key")
                stack[-1][key] = value
        elif name in {"REDUCE", "NEWOBJ"}:
            arguments, function = stack.pop(), stack.pop()
            require(isinstance(function, Descriptor) and function.kind == "global" and type(arguments) is tuple,
                    "Only inert known descriptors are supported")
            global_name = function.args[0]
            if name == "NEWOBJ":
                require(global_name in {"pandas.core.frame DataFrame", "pandas.core.internals.managers BlockManager"}
                        and arguments == (), "Unsupported object descriptor")
                result = Descriptor(global_name)
            elif global_name == "numpy dtype":
                require(len(arguments) == 3 and arguments[0] in {"O8", "f8", "i8"}, "Unsupported dtype")
                result = Descriptor("dtype", arguments)
            elif global_name == "numpy.core.multiarray _reconstruct":
                require(len(arguments) == 3 and isinstance(arguments[0], Descriptor)
                        and arguments[0].args == ("numpy ndarray",) and arguments[1:] == ((0,), b"b"),
                        "Unsupported array descriptor")
                result = Descriptor("array")
            elif global_name == "pandas.core.indexes.base _new_Index":
                require(len(arguments) == 2 and isinstance(arguments[0], Descriptor)
                        and arguments[0].args[0] in {"pandas.core.indexes.base Index", "pandas.core.indexes.range RangeIndex"}
                        and type(arguments[1]) is dict, "Unsupported index")
                result = Descriptor("index", arguments)
            elif global_name == "builtins slice":
                require(len(arguments) == 3 and all(type(x) is int for x in arguments), "Invalid slice")
                result = Descriptor("slice", arguments)
            else:
                raise ValueError("Unsupported reducer: " + global_name)
            stack.append(result)
        elif name == "BUILD":
            state, descriptor = stack.pop(), stack[-1]
            require(isinstance(descriptor, Descriptor) and descriptor.kind != "global", "Invalid BUILD")
            if descriptor.kind == "dtype":
                require(type(state) is tuple and len(state) == 8 and state[0] == 3
                        and state[1] in {"<", ">", "|"} and state[2:5] == (None, None, None),
                        "Structured or executable dtype metadata is forbidden")
            elif descriptor.kind == "array":
                require(type(state) is tuple and len(state) == 5 and state[0] == 1, "Invalid array state")
                _, shape, dtype, fortran, payload = state
                require(type(shape) is tuple and 1 <= len(shape) <= 2
                        and all(type(x) is int and 0 < x <= 1_000_000 for x in shape), "Invalid array dimensions")
                require(isinstance(dtype, Descriptor) and dtype.kind == "dtype" and dtype.state is not None,
                        "Missing dtype")
                require(fortran is False, "Fortran arrays are not supported")
                length = math.prod(shape)
                if dtype.args[0] == "O8":
                    require(len(shape) == 1 and type(payload) is list and len(payload) == length
                            and all(type(x) is str and x in COLUMNS for x in payload),
                            "Object sample arrays are forbidden; only known column-name metadata is allowed")
                else:
                    require(type(payload) is bytes and len(payload) == length * 8, "Invalid numeric block")
            else:
                require(descriptor.kind in {"pandas.core.frame DataFrame", "pandas.core.internals.managers BlockManager"},
                        "Unsupported BUILD target")
            descriptor.state = state
        elif name == "STOP":
            require(len(stack) == 1 and type(stack[0]) is dict, "Invalid root")
            return stack[0]
        else:
            raise ValueError("Unsupported pickle opcode: " + name)
        require(len(stack) < 10_000 and len(memo) < 50_000, "Descriptor limits exceeded")
    raise ValueError("Missing STOP")


def columns_for(frame):
    require(isinstance(frame, Descriptor) and frame.kind == "pandas.core.frame DataFrame", "Expected DataFrame")
    manager = frame.state["_data"]
    require(isinstance(manager, Descriptor) and manager.kind == "pandas.core.internals.managers BlockManager",
            "Expected BlockManager")
    layout = manager.state[-1]["0.14.1"]
    names = layout["axes"][0].args[1]["data"].state[-1]
    require(tuple(names) == COLUMNS, "Unexpected sample columns")
    columns = {}
    for block in layout["blocks"]:
        values, locations = block["values"], block["mgr_locs"]
        require(isinstance(values, Descriptor) and values.kind == "array", "Expected numeric array")
        _, shape, dtype, _, payload = values.state
        require(dtype.args[0] in {"f8", "i8"} and len(shape) == 2, "Numeric sample blocks only")
        numbers = array.array("d" if dtype.args[0] == "f8" else "q")
        numbers.frombytes(payload)
        endian = dtype.state[1]
        if (endian == "<") != (sys.byteorder == "little"):
            numbers.byteswap()
        indices = list(range(*locations.args))
        require(len(indices) == shape[0], "Invalid block locations")
        for row, column_index in enumerate(indices):
            require(0 <= column_index < len(names), "Invalid column location")
            columns[names[column_index]] = numbers[row * shape[1]:(row + 1) * shape[1]]
    require(set(columns) == set(COLUMNS) and len({len(x) for x in columns.values()}) == 1, "Incomplete recording")
    return columns


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pickle", type=pathlib.Path, required=True, help="Pinned SED.pkl path outside the repository")
    parser.add_argument("--output", type=pathlib.Path, required=True, help="New CSV output directory outside the repository")
    parser.add_argument("--download", action="store_true", help="Download the official pinned SED release if missing")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    require(not args.pickle.resolve().is_relative_to(root) and not args.output.resolve().is_relative_to(root),
            "Keep research data outside the repository")
    if not args.pickle.exists() and args.download:
        args.pickle.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(SOURCE, timeout=120) as response:
            data = response.read(SIZE + 1)
        require(len(data) == SIZE and hashlib.sha256(data).hexdigest() == SHA256, "Downloaded checksum mismatch")
        args.pickle.write_bytes(data)
    require(args.pickle.stat().st_size == SIZE, "Unexpected SED release size")
    data = args.pickle.read_bytes()
    require(hashlib.sha256(data).hexdigest() == SHA256, "Only the pinned official SED release is supported")
    dataset = parse_data_only(data)
    args.output.mkdir(parents=True, exist_ok=False)
    recordings = []
    for subject, sessions in sorted(dataset.items(), key=lambda x: int(x[0])):
        require(type(subject) is str and subject.isdigit() and type(sessions) is list, "Invalid subject")
        for index, frame in enumerate(sessions):
            columns = columns_for(frame)
            count = len(columns["T"])
            require(count > 1, "Empty recording")
            previous, active, puffs = None, False, 0
            filename = f"subject-{subject}-session-{index + 1}.csv"
            with (args.output / filename).open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(COLUMNS)
                for row in zip(*(columns[name] for name in COLUMNS)):
                    require(all(math.isfinite(x) for x in row), "Nonfinite measured value")
                    require(previous is None or row[0] > previous, "Nonmonotonic time")
                    require(row[7] in {-1, 1}, "Unknown SED puff label")
                    if row[7] > 0 and not active:
                        puffs += 1
                    active, previous = row[7] > 0, row[0]
                    writer.writerow(row)
            recordings.append({"subject": subject, "session": index + 1, "file": filename,
                               "samples": count, "durationSeconds": columns["T"][-1] - columns["T"][0],
                               "groundTruthPuffs": puffs})
    manifest = {"dataset": "SED", "doi": "10.5281/zenodo.4507451", "license": "CC-BY-4.0",
                "sourceSHA256": SHA256, "accelerationUnit": "m/s^2 (includes gravity)",
                "gyroscopeUnit": "rad/s", "labels": "+1 puff cycle; -1 other samples within a smoking recording",
                "recordings": recordings}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"recordings": len(recordings), "participants": len(dataset),
                      "samples": sum(x["samples"] for x in recordings),
                      "groundTruthPuffs": sum(x["groundTruthPuffs"] for x in recordings),
                      "output": str(args.output)}))


if __name__ == "__main__":
    main()
