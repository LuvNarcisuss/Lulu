#!/usr/bin/env python3
"""Preserve Lulu's nested IAP capability with older XcodeGen releases."""
import argparse
import copy
from pathlib import Path
import plistlib
import re
import subprocess


def read_project(path):
    return plistlib.loads(subprocess.check_output([
        "plutil", "-convert", "xml1", "-o", "-", str(path)
    ]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    project = read_project(args.project)
    objects = project["objects"]
    targets = [key for key, value in objects.items()
               if value.get("isa") == "PBXNativeTarget" and value.get("name") == "TravelApp"]
    if len(targets) != 1:
        raise SystemExit("Expected exactly one TravelApp target.")
    attributes = objects[project["rootObject"]]["attributes"]["TargetAttributes"][targets[0]]
    capability = attributes.get("SystemCapabilities")
    if isinstance(capability, dict):
        if str(capability.get("com.apple.InAppPurchase", {}).get("enabled")) != "1":
            raise SystemExit("TravelApp must enable In-App Purchase.")
        print("PASS: Xcode can read the In-App Purchase capability dictionary.")
        return
    if args.check:
        raise SystemExit("FAIL: SystemCapabilities is not a plist dictionary.")
    # XcodeGen 2.45.4 serializes nested target attributes as a Swift description.
    # Refuse unknown input instead of removing any additional capabilities.
    if capability != '["com.apple.InAppPurchase": ["enabled": 1]]':
        raise SystemExit("Unexpected capability representation; refusing to modify it.")
    original = args.project.read_text()
    pattern = r'(?m)^(\s*)SystemCapabilities = "\[\\"com\.apple\.InAppPurchase\\": \[\\"enabled\\": 1\]\]";$'
    def replacement(match):
        indent = match.group(1)
        return (f'{indent}SystemCapabilities = {{\n'
                f'{indent}\tcom.apple.InAppPurchase = {{\n'
                f'{indent}\t\tenabled = 1;\n{indent}\t}};\n{indent}}};')
    updated, count = re.subn(pattern, replacement, original)
    if count != 1:
        raise SystemExit("Expected one malformed capability declaration.")
    candidate = args.project.with_suffix(".iap-check")
    try:
        candidate.write_text(updated)
        expected = copy.deepcopy(project)
        expected["objects"][project["rootObject"]]["attributes"]["TargetAttributes"][targets[0]][
            "SystemCapabilities"] = {"com.apple.InAppPurchase": {"enabled": "1"}}
        if read_project(candidate) != expected:
            raise SystemExit("Unexpected project change; original project preserved.")
        candidate.replace(args.project)
    finally:
        candidate.unlink(missing_ok=True)
    print("Repaired XcodeGen's nested In-App Purchase capability.")


if __name__ == "__main__":
    main()
