#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage:" >&2
  echo "  $0 derived-data-path <simulator UDID>" >&2
  echo "  $0 <build|preflight|main|main-1|main-2|profile|profile-1|profile-2|messages|messages-1|messages-2|composer|continuity> <simulator UDID> <result label>" >&2
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
  build|preflight|main|main-1|main-2|profile|profile-1|profile-2|messages|messages-1|messages-2|composer|continuity)
    if (( $# != 3 )); then
      usage
      exit 64
    fi
    ;;
  *)
    echo "Expected phase derived-data-path, build, preflight, main, main-1, main-2, profile, profile-1, profile-2, messages, messages-1, messages-2, composer, or continuity; received: $phase" >&2
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
readonly profile_test_class="ProfileUITests"
readonly profile_test_source="SurroundUITests/${profile_test_class}.swift"
readonly profile_test_case="${test_target}/${profile_test_class}"
readonly messages_test_class="MessagesNavigationUITests"
readonly messages_test_source="SurroundUITests/${messages_test_class}.swift"
readonly messages_test_case="${test_target}/${messages_test_class}"
readonly continuity_test_class="GameContinuityUITests"
readonly continuity_test_source="SurroundUITests/${continuity_test_class}.swift"
readonly continuity_test_case="${test_target}/${continuity_test_class}"
readonly localization_test_class="LocalizationUITests"
readonly localization_test_source="SurroundUITests/${localization_test_class}.swift"
readonly localization_test_case="${test_target}/${localization_test_class}"
readonly keyboard_preflight_test_name="testKeyboardPreflightSupportsComposerInput"

# These tests intentionally focus a chat composer or exercise layout while that
# composer owns keyboard focus. Isolate them from the main suite so an XCTest
# keyboard-animation quiescence failure cannot slow unrelated journeys. The
# Messages and continuity classes have their own phases and time budgets.
readonly composer_test_names=(
  testCompactChatCanHideAndShowMainBoard
  testLiveGameBannerRestoresCompactChatBoard
  testCompactVariationSharingHidesMainBoardAndShowsComposerPreview
  testVariationSharingDraftSurvivesChatSelection
  testVariationSharingDraftSurvivesAnalyzeNavigation
  testVariationSharingDraftSurvivesZenModeRoundTrip
  testSharingAnotherVariationReplacesDraft
  testAnalyzeShareComposerAutomaticallyFocusesAndAcceptsName
  testShareVariationUsesSelectedChannelAndStaysInChatAfterSending
  testAnalyzeTrunkMarkersShareWithoutLeakingToLiveBoard
  testPrivateMessageProfileEntriesPreserveConversationDraft
)

# xcodebuild accepts an unknown -only-testing or -skip-testing selector and
# exits successfully after running zero tests. Keep the isolation manifest tied
# to its Swift declarations so a rename cannot silently move a composer test
# into main, or leave the profile, Messages, or continuity phase empty.
for class_and_source in "${test_class}:${test_source}" "${profile_test_class}:${profile_test_source}" "${messages_test_class}:${messages_test_source}" "${continuity_test_class}:${continuity_test_source}" "${localization_test_class}:${localization_test_source}"; do
  class_name="${class_and_source%%:*}"
  class_source="${class_and_source#*:}"
  test_class_count="$(
    grep -Ec \
      "^[[:space:]]*final[[:space:]]+class[[:space:]]+${class_name}[[:space:]]*:[[:space:]]*SurroundJourneyUITestCase[[:space:]]*\\{" \
      "$class_source" \
      || true
  )"
  if [[ "$test_class_count" != "1" ]]; then
    echo "Expected exactly one ${class_name} declaration in ${class_source}. Update the isolated UI-test manifest when renaming or moving it." >&2
    exit 1
  fi
  test_declaration_count="$(
    grep -Ec \
      "^[[:space:]]*func[[:space:]]+test[[:alnum:]_]*[[:space:]]*\\(" \
      "$class_source" \
      || true
  )"
  if [[ "$test_declaration_count" == "0" ]]; then
    echo "Expected test declarations in ${class_source}; ${class_name} cannot have an empty UI-test phase." >&2
    exit 1
  fi
done

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

# Each part runs under supervise-ipad-ui-test-part.py. CI gives each part step
# 50 minutes; at 46 the supervisor interrupts xcodebuild, which then has time
# to write its result bundle and the supervisor its evidence: at most 1:45 of
# signal grace and under a minute of bounded collection. A test that a
# simulator crash killed, or that failed only because XCTest timed out on a UI
# query, is rerun once, within the same 46 minutes.
readonly part_deadline_seconds=$((46 * 60))

# The main, profile, and Messages phases each outgrew one CI step, so CI runs
# each in two parts. Part 2 runs every second test declaration of the phase's
# class (the SurroundUITests class for main, less the tests main skips); part
# 1 runs the rest of the phase by skipping exactly those, so a test this scan
# misses still runs in part 1. Alternating declarations keeps the profile and
# Messages parts balanced as tests are added. Main's other classes stay in
# part 1, so main's part 2 also takes the whole, slow LocalizationUITests class.
second_part_test_names() {
  grep -Eo "^[[:space:]]*func[[:space:]]+test[[:alnum:]_]*[[:space:]]*\\([[:space:]]*\\)" "$1" \
    | sed -E 's/^[[:space:]]*func[[:space:]]+//; s/[[:space:]]*\([[:space:]]*\)$//' \
    | awk 'NR % 2 == 0'
}

is_excluded_from_main() {
  local excluded_name
  for excluded_name in "$keyboard_preflight_test_name" "${composer_test_names[@]}"; do
    if [[ "$1" == "$excluded_name" ]]; then
      return 0
    fi
  done
  return 1
}

select_main_tests() {
  selection_arguments=(
    "-only-testing:${test_target}"
    "-skip-testing:${test_case}/${keyboard_preflight_test_name}"
    "-skip-testing:${profile_test_case}"
    "-skip-testing:${messages_test_case}"
    "-skip-testing:${continuity_test_case}"
  )
  local composer_test_name
  for composer_test_name in "${composer_test_names[@]}"; do
    selection_arguments+=("-skip-testing:${test_case}/${composer_test_name}")
  done
}

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
    select_main_tests

    echo "Running the main iPad UI suite without profile, Messages, composer, or continuity tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "${selection_arguments[@]}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Main.xcresult"
    ;;

  profile)
    mkdir -p TestResults
    echo "Running the profile and friendship iPad UI journeys."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${profile_test_case}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Profile.xcresult"
    ;;

  main-1|main-2|profile-1|profile-2|messages-1|messages-2)
    mkdir -p TestResults
    part="${phase##*-}"
    case "$phase" in
      main-*)
        part_test_case="$test_case"
        part_test_source="$test_source"
        part_result_name="Main"
        ;;
      profile-*)
        part_test_case="$profile_test_case"
        part_test_source="$profile_test_source"
        part_result_name="Profile"
        ;;
      *)
        part_test_case="$messages_test_case"
        part_test_source="$messages_test_source"
        part_result_name="Messages"
        ;;
    esac
    second_part_names=()
    while IFS= read -r test_name; do
      if [[ "$phase" == main-* ]] && is_excluded_from_main "$test_name"; then
        continue
      fi
      second_part_names+=("$test_name")
    done < <(second_part_test_names "$part_test_source")
    if (( ${#second_part_names[@]} == 0 )); then
      echo "Expected at least two test declarations in ${part_test_source} to run it in two parts." >&2
      exit 1
    fi
    if [[ "$part" == "1" ]]; then
      if [[ "$phase" == main-* ]]; then
        select_main_tests
      else
        selection_arguments=("-only-testing:${part_test_case}")
      fi
      for test_name in "${second_part_names[@]}"; do
        selection_arguments+=("-skip-testing:${part_test_case}/${test_name}")
      done
      if [[ "$phase" == main-* ]]; then
        selection_arguments+=("-skip-testing:${localization_test_case}")
      fi
    else
      selection_arguments=()
      for test_name in "${second_part_names[@]}"; do
        selection_arguments+=("-only-testing:${part_test_case}/${test_name}")
      done
      if [[ "$phase" == main-* ]]; then
        selection_arguments+=("-only-testing:${localization_test_case}")
      fi
    fi

    echo "Running part ${part} of 2 of the iPad ${part_result_name} UI tests."
    part_result_bundle="TestResults/SurroundUITests-${result_label}-${part_result_name}-${part}.xcresult"
    python3 .github/ci-tools/supervise-ipad-ui-test-part.py \
      --simulator "$simulator_id" \
      --deadline-seconds "$part_deadline_seconds" \
      --diagnostics "${part_result_bundle%.xcresult}-Diagnostics" \
      -- \
      xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "${selection_arguments[@]}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath "$part_result_bundle"
    ;;

  messages)
    mkdir -p TestResults
    echo "Running the isolated iPad Messages navigation and conversation UI tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${messages_test_case}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Messages.xcresult"
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

  continuity)
    mkdir -p TestResults
    echo "Running the iPad game layout and interaction continuity UI tests."
    xcodebuild test-without-building \
      "${common_arguments[@]}" \
      "-only-testing:${continuity_test_case}" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 900 \
      -maximum-test-execution-time-allowance 900 \
      -resultBundlePath \
      "TestResults/SurroundUITests-${result_label}-Continuity.xcresult"
    ;;
esac
