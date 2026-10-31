#!/usr/bin/env bash
# Builds the CI host with the Protly keyboard, runs the screenshot scenarios and the phone checks in an iOS
# Simulator, measures them and writes <out>/report.txt (line 1: STATUS build-failed | test-failed | measured; the
# layout RESULT line; a CHECKS section from checks.py). Always exits 0 once the report is written; the workflow
# fails the job unless the report says RESULT PASS and no CHECK is FAIL. macOS only (bash 3.2 compatible).
#
# Usage: ios-app/CI/run-shots.sh <out-dir>
# Env: SOURCE_SHA (for the report), PROBE=1 (the phone checks' probe, plan Task 2.2: the preferences dump around
# Full Access and test0_probe), OCR_FALLBACK=1 (label checks RECORD a crop when Vision fails its self-test; off: they
# FAIL unreadable), HAS_KEY=true (write-secrets.sh wrote Secrets.swift with the CI key: the network checks run).
# Nothing here reads or prints Secrets.swift's key; the run folder goes through leak-guard.sh before any publish.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$1"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
work="${RUNNER_TEMP:-/tmp}/protly-shots-work"
mkdir -p "$work"
rm -f "$work/checks-section.txt"  # never a previous run's checks in this report
dd="$here/build/DerivedData"
report="$out/report.txt"
keyboard_id="com.northprot.protly.cihost.keyboard"
points=390

status="measured"
info=""
failing_log=""

note() { info="${info}$1"$'\n'; echo "$1"; }

finish() {
  {
    echo "STATUS $status"
    printf '%s' "$info"
    if [ -f "$out/measure.txt" ]; then cat "$out/measure.txt"; fi
    if [ -f "$work/checks-section.txt" ]; then cat "$work/checks-section.txt"; fi
    if [ -n "$failing_log" ] && [ -f "$failing_log" ]; then
      echo "--- last 200 lines of $(basename "$failing_log")"
      tail -n 200 "$failing_log"
    fi
  } > "$report"
  echo "wrote $report"
  exit 0
}

note "source $(printf '%s' "${SOURCE_SHA:-$(git -C "$here" rev-parse HEAD)}")"
note "xcode $(xcodebuild -version | tr '\n' ' ')"

# Secrets.swift is gitignored; the keyboard types without a key (only Translate/Polish need one). With HAS_KEY=true
# write-secrets.sh has written it; grep -q only tests that it holds a key-shaped value (prints nothing).
secrets="$here/../Sources/ProtlyKeyboard/Secrets.swift"
network=0
if [ "${HAS_KEY:-}" = "true" ]; then
  if ! grep -qE 'apiKey = "sk-ant-[A-Za-z0-9_-]+"' "$secrets" 2> /dev/null; then
    note "HAS_KEY=true but Secrets.swift holds no key"
    status="build-failed"
    finish
  fi
  network=1
  note "network key: present (CI key); DerivedData cache: restore only, not saved in this run"
else
  # A key-shaped Secrets.swift in a run without the key would be compiled into a DerivedData that gets cached.
  if grep -q 'sk-ant-' "$secrets" 2> /dev/null; then
    note "Secrets.swift holds a key but HAS_KEY is not true: refusing (the cache would keep it)"
    status="build-failed"
    finish
  fi
  if [ ! -f "$secrets" ]; then
    printf '// CI stand-in written by ios-app/CI/run-shots.sh: no key.\nenum Secrets {\n    static let apiKey = ""\n}\n' > "$secrets"
  fi
  note "network key: none (network checks SKIP); DerivedData cache: saved after the run"
fi

# Newest iOS 26 runtime, then iPhone 13 Pro or the first 390 pt wide iPhone that the runtime takes.
runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"]
       if r.get("platform") == "iOS" and r.get("isAvailable") and r["version"].startswith("26.")]
rts.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(rts[-1]["identifier"] + " " + rts[-1]["version"] if rts else "")
')"
if [ -z "$runtime" ]; then
  note "no iOS 26 simulator runtime"
  status="build-failed"
  finish
fi
runtime_id="${runtime%% *}"
note "runtime iOS ${runtime##* } ($runtime_id)"

udid=""
for devtype in iPhone-13-Pro iPhone-14 iPhone-13 iPhone-16e iPhone-12-Pro; do
  udid="$(xcrun simctl create "protly-shots" "com.apple.CoreSimulator.SimDeviceType.$devtype" "$runtime_id" 2>/dev/null)" && break
  udid=""
done
if [ -z "$udid" ]; then
  note "no 390 pt iPhone available for $runtime_id"
  status="build-failed"
  finish
fi
note "device $devtype ($udid), $points pt wide"

# Build.
(cd "$here" && xcodegen generate --quiet) > "$work/xcodegen.log" 2>&1 || {
  note "xcodegen failed"
  status="build-failed"; failing_log="$work/xcodegen.log"; finish
}
xcodebuild build-for-testing \
  -project "$here/ProtlyCI.xcodeproj" -scheme ProtlyCI \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$dd" > "$work/build.log" 2>&1
if [ $? -ne 0 ]; then
  note "build failed"
  status="build-failed"; failing_log="$work/build.log"; finish
fi
note "build ok"

# Simulator: dark, English, software keyboard, Protly then Emoji then English (US).
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl ui "$udid" appearance dark
xcrun simctl install "$udid" "$dd/Build/Products/Debug-iphonesimulator/ProtlyCIHost.app"
xcrun simctl install "$udid" "$dd/Build/Products/Debug-iphonesimulator/ProtlyCIApp.app" \
  || note "ProtlyCIApp install failed: the icon check will FAIL"
xcrun simctl shutdown "$udid"

prefs="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences"
mkdir -p "$prefs"
plist_set() {  # file key plutil-type value
  [ -f "$1" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' > "$1"
  plutil -replace "$2" "-$3" "$4" "$1"
}
global="$prefs/.GlobalPreferences.plist"
plist_set "$global" AppleKeyboards json "[\"$keyboard_id\",\"emoji@sw=Emoji\",\"en_US@sw=QWERTY;hw=Automatic\"]"
plist_set "$global" AppleKeyboardsExpanded integer 1
plist_set "$global" AppleLanguages json '["en-US"]'
plist_set "$global" AppleLocale string en_US
for f in "$global" "$prefs/com.apple.keyboard.preferences.plist"; do
  plist_set "$f" DidShowContinuousPathIntroduction bool true
  plist_set "$f" KeyboardPrediction bool true
done

boot() {
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl ui "$udid" appearance dark
  # Keep the keyboard's debug log (ProtlyHeight.swift); debug messages are not stored by default.
  xcrun simctl spawn "$udid" log config --subsystem com.northprot.protly --mode "level:debug,persist:debug" > /dev/null 2>&1
}

# One test method on its own (the probe's Full Access step).
run_one() {  # test-id log
  TEST_RUNNER_SHOTS_DIR="$out" TEST_RUNNER_PROBE="${PROBE:-0}" TEST_RUNNER_NETWORK="$network" \
    xcodebuild test-without-building \
    -project "$here/ProtlyCI.xcodeproj" -scheme ProtlyCI \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$dd" -only-testing:"$1" > "$2" 2>&1
}

devdata="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data"
if [ "${PROBE:-0}" = "1" ]; then
  # Plan Task 2.2 step 1: where Full Access is kept. Snapshots of the shut-down device before and after test0_access
  # turns it on in Settings; the difference goes to probe-prefs.txt.
  python3 "$here/prefsdump.py" snapshot "$devdata" "$work/prefs-before" > "$work/prefsdump.log" 2>&1 \
    || note "probe: snapshot before failed ($(tail -n 1 "$work/prefsdump.log"))"
  boot
  run_one ProtlyCIUITests/PhoneChecksUITests/test0_access "$work/test-access.log"
  note "probe: test0_access alone, xcodebuild exit $?"
  xcrun simctl shutdown "$udid"
  python3 "$here/prefsdump.py" snapshot "$devdata" "$work/prefs-after" > "$work/prefsdump.log" 2>&1 \
    || note "probe: snapshot after failed ($(tail -n 1 "$work/prefsdump.log"))"
  {
    echo "Device data changes around test0_access (Full Access in Settings), each snapshot after simctl shutdown:"
    echo "$(grep -h 'full access' "$out/network.txt" 2> /dev/null)"
  } > "$out/probe-prefs.txt"
  python3 "$here/prefsdump.py" diff "$work/prefs-before" "$work/prefs-after" "$out/probe-prefs.txt" \
    || note "probe: prefsdump diff failed"
fi

boot
note "AppleKeyboards $(xcrun simctl spawn "$udid" defaults read -g AppleKeyboards 2>&1 | tr -d ' \n')"
note "appearance $(xcrun simctl ui "$udid" appearance 2>&1)"

# The keyboard process's memory from the macOS side during the phone checks (plan Task 1.4): mem.txt,
# probe-mem.txt. It starts at test1_68 (test0_access and the probe come first and need no samples): in run 8, with
# the sampler attached from the start, scenario 04 lost the host-active notification (band 69).
python3 "$here/memsample.py" "$out/mem.txt" "$out/probe-mem.txt" --name ProtlyCIKeyboard --interval 2 \
  --wait-for "$out/ui-log.txt" "== PhoneChecksUITests.test1" > "$work/memsample.log" 2>&1 &
sampler=$!
note "memory sampler pid $sampler, probe ${PROBE:-0}, network $network"

# Layout scenarios (KeyboardShotsUITests), then the phone checks (PhoneChecksUITests).
rm -rf "$work/Tests.xcresult"
TEST_RUNNER_SHOTS_DIR="$out" TEST_RUNNER_PROBE="${PROBE:-0}" TEST_RUNNER_OCR_FALLBACK="${OCR_FALLBACK:-0}" \
  TEST_RUNNER_NETWORK="$network" \
  xcodebuild test-without-building \
  -project "$here/ProtlyCI.xcodeproj" -scheme ProtlyCI \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$dd" -resultBundlePath "$work/Tests.xcresult" > "$work/test.log" 2>&1
test_code=$?
kill "$sampler" > /dev/null 2>&1
wait "$sampler" > /dev/null 2>&1
if [ -s "$work/memsample.log" ]; then note "memsample: $(tail -n 3 "$work/memsample.log" | tr '\n' ' ')"; fi
grep -E '^Test Case .*(passed|failed|skipped)' "$work/test.log" > "$out/test-cases.txt" 2>/dev/null

# The runner writes the PNGs straight to $out; if it could not, take them from the result bundle.
if ! ls "$out"/0*.png > /dev/null 2>&1 && [ -d "$work/Tests.xcresult" ]; then
  note "no PNGs in the output folder: exporting attachments from the result bundle"
  xcrun xcresulttool export attachments --path "$work/Tests.xcresult" --output-path "$work/attachments" > /dev/null 2>&1
  python3 - "$work/attachments" "$out" <<'EOF'
import json, os, shutil, sys
src, dst = sys.argv[1:]
try:
    manifest = json.load(open(os.path.join(src, "manifest.json")))
except OSError:
    sys.exit(0)
for test in manifest:
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "")
        for scenario in ("01-apple", "02-first-open", "03-after-emoji", "04-after-background",
                         "05-after-second-emoji", "06-word-typed", "07-empty-left-slot"):
            if name.startswith(scenario):
                shutil.copy(os.path.join(src, a["exportedFileName"]), os.path.join(dst, scenario + ".png"))
EOF
fi
# The keyboard's own height log (ProtlyHeight.swift), for what iOS did between the screenshots.
xcrun simctl spawn "$udid" log show --last 30m --debug --info --style compact \
  --predicate 'subsystem == "com.northprot.protly"' > "$out/keyboard-log.txt" 2>&1
xcrun simctl shutdown "$udid" > /dev/null 2>&1

if [ $test_code -ne 0 ]; then
  note "tests failed (xcodebuild exit $test_code)"
  status="test-failed"; failing_log="$work/test.log"
fi

python3 "$here/measure.py" "$out" --points "$points" > "$out/measure.txt" 2>&1
key_flag=""
if [ "$network" = 1 ]; then key_flag="--network-key"; fi  # a SKIP for want of the key is then the CI's FAIL
python3 "$here/checks.py" "$out" $key_flag > "$work/checks-section.txt" 2>&1
finish
