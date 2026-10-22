#!/usr/bin/env bash
# Prints the id of the newest iPhone simulator on the newest iOS runtime that has an ordinary iPhone.
#
# Picking by name ("iPhone 16") breaks as soon as the Xcode on the machine changes, and a name can exist under
# several runtimes (`OS:latest` in a destination follows the newest one). So: take the runtime with the highest
# version that has an "iPhone <number>" device, and on it the highest number, preferring the plain model over
# Pro / Pro Max / e. Unusual form factors (iPhone Duo and the like) are used only if nothing else exists.
#
#   xcodebuild test -scheme ZDTaffy-Package -destination "id=$(scripts/latest-iphone-simulator.sh)"
set -euo pipefail

xcrun simctl list devices available iOS -j | python3 -I -c '
import json, re, sys

devices = json.load(sys.stdin)["devices"]

def runtime_version(runtime):
    # "com.apple.CoreSimulator.SimRuntime.iOS-27-0" -> (27, 0)
    return tuple(int(part) for part in runtime.rsplit("iOS-", 1)[1].split("-"))

def phones(runtime):
    return [d for d in devices[runtime] if d["name"].startswith("iPhone") and d.get("isAvailable", True)]

def generation(device):
    match = re.match(r"iPhone (\d+)", device["name"])
    return int(match.group(1)) if match else None

runtimes = sorted((r for r in devices if "iOS-" in r), key=runtime_version, reverse=True)

# 1. An ordinary numbered iPhone on the newest runtime that has one.
for runtime in runtimes:
    numbered = [d for d in phones(runtime) if generation(d) is not None]
    if numbered:
        best = sorted(numbered, key=lambda d: (-generation(d), len(d["name"])))[0]
        break
else:
    # 2. Anything that is an iPhone, newest runtime first.
    candidates = [(runtime, d) for runtime in runtimes for d in phones(runtime)]
    if not candidates:
        sys.exit("error: no available iPhone simulator found")
    runtime, best = candidates[0]

print("Using {} on {}".format(best["name"], runtime.rsplit(".", 1)[1]), file=sys.stderr)
print(best["udid"])
'
