#!/bin/bash
# Runs the DzzReader test suites and prints a summary.
#
#   Scripts/run-tests.sh                 core + unit + UI (everything except the corpus smoke test)
#   Scripts/run-tests.sh core unit       just those suites, in that order
#   Scripts/run-tests.sh ui -only ContinuousReadingUITests
#                                        one UI test class (or Class/testMethod)
#   Scripts/run-tests.sh corpus          index every corpus file and report 卷数 mismatches (slow)
#
# Suites: core (DzzCore, swift test), corpus (DzzCore corpus smoke test), unit (DzzReaderTests),
#         ui (DzzReaderUITests), all (core unit ui).
#
# Environment:
#   DZZ_SIM     simulator UDID or name (default: iPhone 17 Pro Max)
#   DZZ_SHOTS   directory for UI-test screenshots (default: build/test-logs/<run>/shots)
#   DZZ_CORPUS  corpus folder for the corpus suite (default: ../dzz)
#
# Logs and .xcresult bundles go to build/test-logs/<timestamp>/. Exit status is non-zero if any suite failed.
# Note: ImportUITests needs dzz-import-sample.txt in the simulator's On My iPhone storage (see the test file).

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# ---- arguments ---------------------------------------------------------------

SUITES=""
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    -only|--only)
      [ $# -ge 2 ] || { echo "error: -only needs a test name" >&2; exit 2; }
      ONLY="$2"; shift 2 ;;
    all) SUITES="$SUITES core unit ui"; shift ;;
    core|corpus|unit|ui) SUITES="$SUITES $1"; shift ;;
    *) echo "error: unknown argument '$1'" >&2; usage 2 ;;
  esac
done
[ -n "$SUITES" ] || SUITES="core unit ui"

# ---- setup -------------------------------------------------------------------

RUN_DIR="$ROOT/build/test-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"
SHOTS="${DZZ_SHOTS:-$RUN_DIR/shots}"
mkdir -p "$SHOTS"

SIM_WANTED="${DZZ_SIM:-iPhone 17 Pro Max}"

# Resolve a simulator name to a UDID: '-destination name=' can resolve to "My Mac" on this machine.
resolve_sim() {
  if echo "$SIM_WANTED" | grep -Eq '^[0-9A-F-]{36}$'; then
    echo "$SIM_WANTED"
    return
  fi
  # Prefer a booted device with that name, else the first available one.
  local line
  line=$(xcrun simctl list devices available | grep -F "    $SIM_WANTED (" | grep -F "(Booted)" | head -1)
  [ -n "$line" ] || line=$(xcrun simctl list devices available | grep -F "    $SIM_WANTED (" | head -1)
  echo "$line" | grep -Eo '[0-9A-F-]{36}' | head -1
}

SIM_ID=""
needs_sim() {
  case " $SUITES " in *" unit "*|*" ui "*) return 0 ;; esac
  return 1
}
if needs_sim; then
  SIM_ID=$(resolve_sim)
  if [ -z "$SIM_ID" ]; then
    echo "error: no available simulator named '$SIM_WANTED' (set DZZ_SIM to a name or UDID)" >&2
    exit 2
  fi
  echo "Simulator: $SIM_WANTED ($SIM_ID)"
  xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true   # already booted is fine

  # New test files only reach the Xcode project through XcodeGen.
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --quiet >/dev/null 2>&1 || { echo "error: xcodegen generate failed" >&2; exit 1; }
  else
    echo "warning: xcodegen not found; newly added files may be missing from the project" >&2
  fi
fi

echo "Logs: $RUN_DIR"
echo

RESULTS=""
FAILED=0

record() {   # record <suite> <status> <seconds> <detail>
  RESULTS="$RESULTS$(printf '  %-7s %-6s %5ss  %s' "$1" "$2" "$3" "$4")
"
  [ "$2" = "PASS" ] || FAILED=1
}

# ---- suites ------------------------------------------------------------------

run_core() {
  local log="$RUN_DIR/core.log" start=$SECONDS
  echo "▶ core (swift test)"
  (cd DzzCore && swift test) >"$log" 2>&1
  local status=$?
  local summary
  summary=$(grep -E "Test run with .* (passed|failed)" "$log" | tail -1 | sed -E 's/^[^A-Za-z]*//')
  if [ $status -eq 0 ]; then record core PASS $((SECONDS - start)) "$summary"
  else
    record core FAIL $((SECONDS - start)) "${summary:-see core.log}"
    grep -E "✘|error:" "$log" | head -20 | sed 's/^/    /'
  fi
}

run_corpus() {
  local log="$RUN_DIR/corpus.log" start=$SECONDS
  local corpus="${DZZ_CORPUS:-$ROOT/../dzz}"
  echo "▶ corpus smoke test ($corpus)"
  (cd DzzCore && DZZ_CORPUS="$corpus" swift test --filter CorpusSmoke) >"$log" 2>&1
  local status=$?
  if [ $status -eq 0 ]; then record corpus PASS $((SECONDS - start)) "report in corpus.log"
  else
    record corpus FAIL $((SECONDS - start)) "see corpus.log"
    grep -E "✘|error:" "$log" | head -20 | sed 's/^/    /'
  fi
}

run_xcode() {   # run_xcode <suite> <target>
  local suite="$1" target="$2"
  local log="$RUN_DIR/$suite.log" bundle="$RUN_DIR/$suite.xcresult" start=$SECONDS
  local filter="$target"
  [ -n "$ONLY" ] && filter="$target/$ONLY"
  echo "▶ $suite (-only-testing:$filter)"
  TEST_RUNNER_DZZ_SHOTS="$SHOTS" xcodebuild test \
    -project DzzReader.xcodeproj -scheme DzzReader \
    -destination "id=$SIM_ID" \
    -only-testing:"$filter" \
    -resultBundlePath "$bundle" >"$log" 2>&1
  local status=$?

  # Swift Testing (unit) and XCTest (UI) report differently.
  local passed failed
  passed=$(grep -cE "Test Case .* passed|✔ Test .* passed" "$log")
  failed=$(grep -cE "Test Case .* failed|✘ Test .* failed" "$log")
  local detail="$passed passed, $failed failed"
  local swiftTesting
  swiftTesting=$(grep -E "Test run with .* (passed|failed)" "$log" | tail -1 | sed -E 's/^[^A-Za-z]*//')
  [ -n "$swiftTesting" ] && detail="$swiftTesting"

  if [ $status -eq 0 ]; then
    record "$suite" PASS $((SECONDS - start)) "$detail"
  else
    if grep -q "BUILD FAILED\|Testing cancelled because the build failed" "$log"; then
      detail="build failed"
      grep -E "error:" "$log" | grep -v "^ *[0-9]* |" | sort -u | head -10 | sed 's/^/    /'
    else
      grep -E "Test Case .* failed|✘|: error: -\[" "$log" | grep -v "^ *[0-9]* |" | head -20 | sed 's/^/    /'
    fi
    record "$suite" FAIL $((SECONDS - start)) "$detail"
  fi
}

for suite in $SUITES; do
  case "$suite" in
    core) run_core ;;
    corpus) run_corpus ;;
    unit) run_xcode unit DzzReaderTests ;;
    ui) run_xcode ui DzzReaderUITests ;;
  esac
done

# ---- summary -----------------------------------------------------------------

echo
echo "Summary"
printf '%s' "$RESULTS"
if ls "$SHOTS"/*.png >/dev/null 2>&1; then echo "Screenshots: $SHOTS"; fi
echo "Logs: $RUN_DIR"
exit $FAILED
