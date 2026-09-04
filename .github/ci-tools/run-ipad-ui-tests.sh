#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage:" >&2
  echo "  $0 derived-data-path <simulator UDID>" >&2
  echo "  $0 <build|preflight|main|composer> <simulator UDID> <result label>" >&2
}

if (( $# == 0 )); then
  usage
  exit 64
fi
phase="$1"
case "$phase" in
  derived-data-path)
    if (( $# != 2 )); then
      usage
      exit 64
    fi
    ;;
  build|preflight|main|composer)
    if (( $# != 3 )); then
      usage
      exit 64
    fi
    ;;
  *)
    echo "Expected phase derived-data-path, build, preflight, main, or composer; received: $phase" >&2
    exit 64
    ;;
esac

simulator_id="$2"
if ! [[ "$simulator_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
  echo "Expected a simulator UDID, received: $simulator_id" >&2
  exit 64
fi

if [[ -n "${RUNNER_TEMP:-}" ]]; then
  derived_data_root="$RUNNER_TEMP"
else
  derived_data_root="${TMPDIR:-/private/tmp}"
fi
derived_data_path="${derived_data_root%/}/Surround-iPadUITests-${simulator_id}"

if [[ "$phase" == "derived-data-path" ]]; then
  printf '%s\n' "$derived_data_path"
  exit 0
fi

result_label="$3"
if ! [[ "$result_label" =~ ^[[:alnum:]._-]+$ ]]; then
  echo "Expected an alphanumeric result label, received: $result_label" >&2
  exit 64
fi

readonly test_target="SurroundUITests"
readonly test_class="SurroundUITests"
readonly test_source="SurroundUITests/${test_class}.swift"
readonly test_case="${test_target}/${test_class}"
readonly keyboard_preflight_test_name="testKeyboardPreflightSupportsComposerInput"

# These tests intentionally focus a chat composer or exercise layout while that
# composer owns keyboard focus. Run them after the rest of the suite so an
# XCTest keyboard-animation quiescence failure cannot slow unrelated journeys.
readonly composer_test_names=(
  testCompactChatAutomaticallyFocusesComposer
  testCompactChatCanHideAndShowMainBoard
  testCompactVariationSharingHidesMainBoardAndShowsComposerPreview
  testVariationSharingDraftSurvivesChatSelection
  testVariationSharingDraftSurvivesAnalyzeNavigation
  testVariationSharingDraftSurvivesZenModeRoundTrip
  testSharingAnotherVariationReplacesDraft
  testAnalyzeShareComposerAutomaticallyFocusesAndAcceptsName
  testShareVariationUsesSelectedChannelAndStaysInChatAfterSending
  testAnalyzeTrunkMarkersShareWithoutLeakingToLiveBoard
)

# xcodebuild accepts an unknown -only-testing selector and exits successfully
# after running zero tests. Keep the isolation manifest tied to its Swift
# declarations so a rename cannot silently move a composer test into main.
test_class_count="$(
  grep -Ec \
    "^[[:space:]]*final[[:space:]]+class[[:space:]]+${test_class}[[:space:]]*:[[:space:]]*SurroundUITestCase[[:space:]]*\\{" \
    "$test_source" \
    || true
)"
if [[ "$test_class_count" != "1" ]]; then
  echo "Expected exactly one ${test_class} declaration in ${test_source}. Update the isolated UI-test manifest when renaming or moving it." >&2
  exit 1
fi

for test_name in "$keyboard_preflight_test_name" "${composer_test_names[@]}"; do
  declaration_count="$(
    grep -Ec \
      "^[[:space:]]*func[[:space:]]+${test_name}[[:space:]]*\\([[:space:]]*\\)" \
      "$test_source" \
      || true
  )"
  if [[ "$declaration_count" != "1" ]]; then
    echo "Expected exactly one ${test_name} declaration in ${test_source}. Update the isolated UI-test manifest when renaming or moving it." >&2
    exit 1
  fi
done

common_arguments=(
  -scheme Surround
  -project Surround.xcodeproj
  -configuration Debug
  -destination "platform=iOS Simulator,id=${simulator_id}"
  -derivedDataPath "$derived_data_path"
  -parallel-testing-enabled NO
)

case "$phase" in
  build)
    echo "Building the shared iPad UI-test products."
    xcodebuild build-for-testing \
      "${common_arguments[@]}" \
      "-only-testing:${test_target}"
    ;;

  preflight)
    mkdir -p TestResults
    echo "Verifying that the selected iPad can focus the composer and accept complete keyboard input."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${test_case}/${keyboard_preflight_test_name}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 180 \
      -maximum-test-execution-time-allowance 180 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-KeyboardPreflight.xcresult"
    ;;

  main)
    mkdir -p TestResults
    selection_arguments=(
      "-only-testing:${test_target}"
      "-skip-testing:${test_case}/${keyboard_preflight_test_name}"
    )
    for test_name in "${composer_test_names[@]}"; do
      selection_arguments+=("-skip-testing:${test_case}/${test_name}")
    done

    echo "Running the main iPad UI suite without composer-sensitive tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "${selection_arguments[@]}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Main.xcresult"
    ;;

  composer)
    mkdir -p TestResults
    selection_arguments=()
    for test_name in "${composer_test_names[@]}"; do
      selection_arguments+=("-only-testing:${test_case}/${test_name}")
    done

    echo "Running the isolated iPad composer and keyboard UI tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "${selection_arguments[@]}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Composer.xcresult"
    ;;
esac
