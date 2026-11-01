#!/usr/bin/env bash
# Builds the CI host with the Protly keyboard, runs the screenshot scenarios and the phone checks in an iOS
# Simulator, measures them and writes <out>/report.txt (line 1: STATUS build-failed | bad-filter | test-failed |
# measured; a FILTER line in a debug run; the layout RESULT line; a CHECKS section from checks.py). Always exits 0 once the report is written; the workflow
# fails the job unless the report says RESULT PASS and no CHECK is FAIL. macOS only (bash 3.2 compatible).
#
# Usage: ios-app/CI/run-shots.sh <out-dir>
# Env: SOURCE_SHA (for the report), PROBE=1 (the phone checks' probe, plan Task 2.2: the preferences dump around
# Full Access and test0_probe), OCR_FALLBACK=1 (label checks RECORD a crop when Vision fails its self-test; off: they
# FAIL unreadable), HAS_KEY=true (write-secrets.sh wrote Secrets.swift with the CI key: the network checks run),
# SHOTS_MESSAGE (the head commit message: a `[shots:...]` tag runs only those tests, shotsfilter.py).
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

# A debug run (`[shots:<class>[/<method>],...]` in the head commit, shotsfilter.py): only the selected tests run,
# the report says FILTER, the layout RESULT is NOT-RUN unless KeyboardShotsUITests is selected and checks.py marks
# the IDs of other methods NOT-RUN. The message reaches shotsfilter.py through the environment only.
filter=""
if ! filter="$(python3 "$here/shotsfilter.py" 2> "$work/filter.err")"; then
  note "bad [shots:...] filter: $(tail -n 1 "$work/filter.err")"
  status="bad-filter"
  finish
fi
only_args=()
layout=1
if [ -n "$filter" ]; then
  layout=0
  while IFS= read -r entry; do
    only_args+=("-only-testing:ProtlyCIUITests/$entry")
    case "$entry" in KeyboardShotsUITests*) layout=1 ;; esac
  done <<< "$filter"
  note "FILTER $(printf '%s' "$filter" | tr '\n' ' ') (a debug run, outside the run budget; other IDs are NOT-RUN)"
fi
if ! mem_wait="$(python3 "$here/shotsfilter.py" mem-wait 2> "$work/filter.err")"; then
  note "memory sampler: no start line from shotsfilter.py ($(tail -n 1 "$work/filter.err")): waiting for test1"
  mem_wait=""
fi
[ -n "$mem_wait" ] || mem_wait="== PhoneChecksUITests.test1"  # no phone method: the sampler never starts

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

# A command with a deadline: TERM at the deadline, KILL 30 s later, exit 124 when stopped. Run 36 hung 71 minutes and
# the job limit cancelled it before anything was published; this way the run keeps time to measure and publish.
with_deadline() {  # seconds command...
  local limit="$1"
  shift
  rm -f "$work/deadline-hit"
  "$@" &
  local pid=$!
  (
    exec > /dev/null 2>&1  # holds no pipe of the caller's (a leftover sleep would keep the step's output open)
    sleep "$limit"
    if kill -0 "$pid" 2> /dev/null; then
      touch "$work/deadline-hit"
      kill -TERM "$pid" 2> /dev/null
      sleep 30
      kill -KILL "$pid" 2> /dev/null
    fi
  ) &
  local dog=$!
  wait "$pid"
  local code=$?
  pkill -P "$dog" 2> /dev/null
  kill "$dog" 2> /dev/null
  wait "$dog" 2> /dev/null
  if [ -f "$work/deadline-hit" ]; then
    rm -f "$work/deadline-hit"
    return 124
  fi
  return $code
}

# Progress for the step log while the tests run, every 20 s: each method's start, each CHECK's ID and status (no
# evidence), request counts, group deadlines, and a heartbeat every 5 minutes. Nothing else from the logs.
progress() {
  local log_n=0 chk_n=0 ticks=0 n
  while sleep 20; do
    ticks=$((ticks + 1))
    if [ -f "$out/ui-log.txt" ]; then
      n=$(wc -l < "$out/ui-log.txt" | tr -d ' ')
      if [ "$n" -gt "$log_n" ]; then
        sed -n "$((log_n + 1)),${n}p" "$out/ui-log.txt" \
          | grep -E '^(== |request [0-9]+ of|full access:|group deadline|MARK )' | cut -c1-100 \
          | sed "s/^/[$(date -u +%H:%M:%S)] /"
        log_n=$n
      fi
    fi
    if [ -f "$out/checks.txt" ]; then
      n=$(wc -l < "$out/checks.txt" | tr -d ' ')
      if [ "$n" -gt "$chk_n" ]; then
        sed -n "$((chk_n + 1)),${n}p" "$out/checks.txt" | awk '{print $1, $2, $3}' | sed "s/^/[$(date -u +%H:%M:%S)] /"
        chk_n=$n
      fi
    fi
    if [ $((ticks % 15)) -eq 0 ]; then
      echo "[$(date -u +%H:%M:%S)] still running: ui-log $log_n lines, checks $chk_n lines"
    fi
  done
}

# One test method on its own (the probe's Full Access step).
run_one() {  # test-id log
  with_deadline 600 env TEST_RUNNER_SHOTS_DIR="$out" TEST_RUNNER_PROBE="${PROBE:-0}" TEST_RUNNER_NETWORK="$network" \
    xcodebuild test-without-building \
    -project "$here/ProtlyCI.xcodeproj" -scheme ProtlyCI \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$dd" -test-timeouts-enabled YES -only-testing:"$1" > "$2" 2>&1
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
  --wait-for "$out/ui-log.txt" "$mem_wait" > "$work/memsample.log" 2>&1 &
sampler=$!
note "memory sampler pid $sampler, probe ${PROBE:-0}, network $network"

# Layout scenarios (KeyboardShotsUITests), then the phone checks (PhoneChecksUITests). Each method has an XCTest
# time allowance (PhoneChecksUITests.allowance, -test-timeouts-enabled), and the whole run a deadline
# (MAIN_TEST_DEADLINE, 65 minutes: run 53, a slow runner, ran past 50 in test7_77) that leaves the 85-minute step
# time to build, measure and publish.
rm -rf "$work/Tests.xcresult"
progress &
progress_pid=$!
main_deadline="${MAIN_TEST_DEADLINE:-3900}"
with_deadline "$main_deadline" env TEST_RUNNER_SHOTS_DIR="$out" TEST_RUNNER_PROBE="${PROBE:-0}" \
  TEST_RUNNER_OCR_FALLBACK="${OCR_FALLBACK:-0}" TEST_RUNNER_NETWORK="$network" \
  xcodebuild test-without-building \
  -project "$here/ProtlyCI.xcodeproj" -scheme ProtlyCI \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$dd" -test-timeouts-enabled YES -resultBundlePath "$work/Tests.xcresult" \
  ${only_args[@]+"${only_args[@]}"} > "$work/test.log" 2>&1
test_code=$?
pkill -P "$progress_pid" > /dev/null 2>&1  # its sleep, which holds the step's output
kill "$progress_pid" > /dev/null 2>&1
wait "$progress_pid" > /dev/null 2>&1
if [ $test_code -eq 124 ]; then note "main tests stopped at the ${main_deadline} s deadline (see the last CHECK and == lines)"; fi
kill "$sampler" > /dev/null 2>&1
wait "$sampler" > /dev/null 2>&1
if [ -s "$work/memsample.log" ]; then note "memsample: $(tail -n 3 "$work/memsample.log" | tr '\n' ' ')"; fi
grep -E '^Test Case .*(passed|failed|skipped)' "$work/test.log" > "$out/test-cases.txt" 2>/dev/null
# The reason a test failed sits far above the log tail (run 44: testScenarios stopped in app.launch() and the tail
# did not say why), so the error lines go to their own file and the report.
grep -E ': error: |Failed to |failed - |exceeded execution time allowance|Restarting after unexpected exit' "$work/test.log" 2>/dev/null | cut -c1-400 | head -n 40 > "$out/test-failures.txt"
if [ -s "$out/test-failures.txt" ]; then
  note "test failures ($(wc -l < "$out/test-failures.txt" | tr -d ' ') lines, test-failures.txt):"
  while IFS= read -r line; do note "  $line"; done < <(head -n 8 "$out/test-failures.txt")
else
  rm -f "$out/test-failures.txt"
fi

# The runner writes the PNGs straight to $out; if it could not, take them from the result bundle.
if [ "$layout" = 1 ] && ! ls "$out"/0*.png > /dev/null 2>&1 && [ -d "$work/Tests.xcresult" ]; then
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
# The web composer's DOM event log (typing-fixes 004, HostApp.swift `-screen web`): the host appends it in its
# Documents folder; it goes into the run folder next to the ret-* lines.
host_data="$(xcrun simctl get_app_container "$udid" com.northprot.protly.cihost data 2> "$work/container.err")"
if [ -n "$host_data" ] && [ -s "$host_data/Documents/web-events.txt" ]; then
  cp "$host_data/Documents/web-events.txt" "$out/web-events.txt"
  note "web-events.txt: $(wc -l < "$out/web-events.txt" | tr -d ' ') lines"
elif grep -q '^CHECK ret-' "$out/checks.txt" 2> /dev/null; then
  note "web-events.txt: MISSING although ret-* ran (container ${host_data:-not found}: $(tail -n 1 "$work/container.err" 2> /dev/null))"
else
  note "web-events.txt: none (the web screen did not run)"
fi
xcrun simctl shutdown "$udid" > /dev/null 2>&1

if [ $test_code -ne 0 ]; then
  note "tests failed (xcodebuild exit $test_code)"
  status="test-failed"; failing_log="$work/test.log"
fi
# A filtered run measures only what it selected: an entry with no passing test case (skipped, renamed, zero tests
# run) would otherwise leave nothing but NOT-RUN lines and pass.
if [ -n "$filter" ]; then
  unran="$(python3 "$here/shotsfilter.py" unran "$out/test-cases.txt" 2>&1 | tr '\n' ' ')"
  if [ -n "$unran" ]; then
    note "filter entries with no passing test case: $unran"
    status="test-failed"; failing_log="$work/test.log"
  fi
fi

if [ "$layout" = 1 ]; then
  python3 "$here/measure.py" "$out" --points "$points" > "$out/measure.txt" 2>&1
else
  echo "RESULT NOT-RUN (filtered run: KeyboardShotsUITests not selected)" > "$out/measure.txt"
fi
check_args=()
if [ "$network" = 1 ]; then check_args+=(--network-key); fi  # a SKIP for want of the key is then the CI's FAIL
if [ -n "$filter" ]; then check_args+=(--ran "$(printf '%s' "$filter" | tr '\n' ',')"); fi
python3 "$here/checks.py" "$out" ${check_args[@]+"${check_args[@]}"} > "$work/checks-section.txt" 2>&1
finish
